unit NPCRC_CommonUtils;

interface

function GetBoolSLValue(const key: string): Boolean;
function ShowCheckboxForm(const options, disableOpts: TStringList; caption: string): Boolean;
function FormIDInputValidation(const s: string): Boolean;
function EditorIDInputValidation(const s: string; useUnderScore: boolean): Boolean;
function RemoveLeadingZeros(const s: string): string;
function FindRecordByRecordID(const recordID, signature: string; useFormID: boolean): IwbMainRecord;

implementation

function GetBoolSLValue(const s: string): Boolean;
var
  value: string;
begin
  value := LowerCase(s);
  Result := (value = 'true') or (value = '1') or (value = 'yes');
end;

function ShowCheckboxForm(const options, disableOpts: TStringList; caption: string): Boolean;
var
  form: TForm;
  checklist: TCheckListBox;
  btnOK, btnCancel: TButton;
  i: Integer;
  shouldDisable: Boolean;
begin
  Result := False;

  // デバッグ: 入力内容を確認
{  AddMessage('=== Debug Info ===');
  AddMessage('Options count: ' + IntToStr(options.Count));
  AddMessage('DisableOpts count: ' + IntToStr(disableOpts.Count));
}  
  form := TForm.Create(nil);
  try
    form.Caption := caption;
    form.Width := 350;
    form.Height := 300;
    form.Position := poScreenCenter;

    checklist := TCheckListBox.Create(form);
    checklist.Parent := form;
    checklist.Align := alTop;
    checklist.Height := 200;

    for i := 0 to options.Count - 1 do begin
      checklist.Items.Add(options.Names[i]);
      
      shouldDisable := false;
      
      // このオプションを無効化すべきか判定
      shouldDisable := (disableOpts.Count > 0) and (disableOpts.IndexOf(options.Names[i]) >= 0);
      
      // デバッグ: 各項目の判定結果
{      AddMessage('Item ' + IntToStr(i) + ': ' + options.ValueFromIndex[i]);
      
      if shouldCheck then
        AddMessage('  shouldCheck: True')
      else
        AddMessage('  shouldCheck: False');
            
      if shouldDisable then
        AddMessage('  shouldDisable: True')
      else
        AddMessage('  shouldDisable: False');
}
      
      // このオプションをチェックすべきか判定
      if GetBoolSLValue(options.ValueFromIndex[i]) then
        checklist.Checked[i] := true;
      
      // 注意：ItemEnabledはtrue:無効化、false:有効化となる
      // 一般的な論理イメージと逆転している。
      if shouldDisable then begin
        checklist.Checked[i] := false;
        checklist.ItemEnabled[i] := true;
      end;

    end;

    btnOK := TButton.Create(form);
    btnOK.Parent := form;
    btnOK.Caption := 'OK';
    btnOK.ModalResult := mrOk;
    btnOK.Width := 75;
    btnOK.Top := checklist.Top + checklist.Height + 10;
    btnOK.Left := (form.ClientWidth div 2) - btnOK.Width - 10;

    btnCancel := TButton.Create(form);
    btnCancel.Parent := form;
    btnCancel.Caption := 'Cancel';
    btnCancel.ModalResult := mrCancel;
    btnCancel.Width := 75;
    btnCancel.Top := btnOK.Top;
    btnCancel.Left := (form.ClientWidth div 2) + 10;

    form.BorderStyle := bsDialog;
    form.Position := poScreenCenter;

    if form.ShowModal = mrOk then
    begin
      Result := True;
      for i := 0 to checklist.Items.Count - 1 do
        if checklist.Checked[i] then
          options.ValueFromIndex[i] := 'True'
        else
          options.ValueFromIndex[i] := 'False';
    end;
  finally
    form.Free;
  end;
end;

function FormIDInputValidation(const s: string): Boolean;
var
  i: Integer;
  ch: Char;
begin
  Result := true;
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    if not ((ch >= 'A') and (ch <= 'F') or
            (ch >= 'a') and (ch <= 'f') or
            (ch >= '0') and (ch <= '9')) then
    begin
      Result := false;
      Break;
    end;
  end;
end;


function EditorIDInputValidation(const s: string; useUnderScore: boolean): Boolean;
var
  i: Integer;
  ch: Char;
begin
  Result := true;
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    if useUnderScore then begin
      if not ((ch >= 'A') and (ch <= 'Z') or
              (ch >= 'a') and (ch <= 'z') or
              (ch >= '0') and (ch <= '9') or
              (ch = '_')) then
      begin
        Result := false;
        Break;
      end;
    end
    else begin
      if not ((ch >= 'A') and (ch <= 'Z') or
              (ch >= 'a') and (ch <= 'z') or
              (ch >= '0') and (ch <= '9')) then
      begin
        Result := false;
        Break;
      end;
    end;
  end;
end;

function RemoveLeadingZeros(const s: string): string;
var
  i: Integer;
begin
  i := 1;
  // 先頭の '0' をスキップ
  while (i <= Length(s)) and (s[i] = '0') do
    Inc(i);
  // すべてが '0' の場合は '0' を返す
  if i > Length(s) then
    Result := '0'
  else
    Result := Copy(s, i, Length(s) - i + 1);
end;

function FindRecordByRecordID(const recordID, signature: string; useFormID: boolean): IwbMainRecord;
var
  formID, i: cardinal;
  editorID: string;
  f:  IwbFile;
  rec: IwbMainRecord;
  npcRecordGroup: IwbGroupRecord;
begin
  Result := nil;
  
  if useFormID then begin
    // StrToIntでは負数になってしまうので、StrToInt64で変換し、Cardinal型で受け取る。
    formID := StrToInt64('$' + recordID);
  //  AddMessage('Converted Form ID: ' + IntToStr(formID));
  end
  else
    editorID := recordID;

  // 0始まりに加えて、Skyrim.exeの分も足してループ回数を減らす。
  for i := 0 to FileCount - 2 do begin
    f := FileByLoadOrder(i);
//    AddMessage('Searching file name: ' + GetFileName(f));
    if useFormID then begin
      rec := RecordByFormID(f, formID, True);
  //    AddMessage('Record Form ID: ' + IntToStr(GetLoadOrderFormID(rec)));
      // Form IDを取得する関数はいくつかあるが、ロードオーダーを含めたForm IDを取得できるのはGetLoadOrderFormID
      if Assigned(rec) and (GetLoadOrderFormID(rec) = formID) then begin
        AddMessage('Record is found by Form ID');
        if (Signature(rec) = signature) then begin
          AddMessage('Record signature is correct.');
          Result := rec;
        end
        else
          AddMessage('Record signature is incorrect.');
        break;
      end;
    end
    else begin
      npcRecordGroup := GroupBySignature(f, signature);
      rec := MainRecordByEditorID(npcRecordGroup, editorID);
      if Assigned(rec) then begin
        AddMessage('Record is found by Editor ID');
        if (Signature(rec) = signature)  then begin
          AddMessage('Record signature is correct.');
          Result := rec;
        end
        else
          AddMessage('Record signature is incorrect.');
        break;
      end;
    end;
  end;
  if Assigned(Result) then
    AddMessage('Target Record is found')
  else
    AddMessage('No target record found for the entered ID. Check the entered ID is correct and target file is loaded.');

end;


end.
