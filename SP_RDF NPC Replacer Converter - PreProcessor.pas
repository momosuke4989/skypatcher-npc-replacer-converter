unit SPRDF_NPCReplacerConverter_PreProcessor;


interface

function RunPreProcInitialize: integer;
function RunPreProcessor(e: IInterface): integer;
function RunPreProcFinalize: integer;

implementation

const
  // デバッグ用定数
  STOPFACEGENMANIPULATION = false;

  // Facegenファイルの操作用定数
  MESHMODE = true;
  TEXTUREMODE = false;

  // ESLフラグ付きespのテストで利用する定数
  OLDESLMAXRECORDS = 2047;
  NEWESLMAXRECORDS = 4095;
  ESLMAXFORMID = $FFF;
  ESLSTARTFORMID = $800;
  EXTESLVER = 1.71;

var
  // 外部呼出し時の処理済判定用
  RunPreProcDone: Boolean;
  
  // ファイル関連変数
  firstRecordFileName, baseFileName, replacerFileName: string;
  testFile: boolean;

  // イニシャル処理で設定・使用する変数
  prefix: string;
  removeFaceGen, removeFaceGenMissingRec, isInputProvided: boolean;

function ShowCheckboxForm(const options: TStringList; out selected: TStringList): Boolean;
var
  form: TForm;
  checklist: TCheckListBox;
  btnOK, btnCancel: TButton;
  i: Integer;
begin
  Result := False;

  form := TForm.Create(nil);
  try
    form.Caption := 'Select Options';
    form.Width := 350;
    form.Height := 300;
    form.Position := poScreenCenter;

    checklist := TCheckListBox.Create(form);
    checklist.Parent := form;
    checklist.Align := alTop;
    checklist.Height := 200;

    // 選択肢を追加
    for i := 0 to options.Count - 1 do begin
      checklist.Items.Add(options[i]);
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
          selected.Add('True')
        else
          selected.Add('False');
    end;
  finally
    form.Free;
  end;
end;

function InputValidation(const s: string): Boolean;
var
  i: Integer;
  ch: Char;
begin
  Result := true;
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    if not ((ch >= 'A') and (ch <= 'Z') or
            (ch >= 'a') and (ch <= 'z') or
            (ch >= '0') and (ch <= '9')) then
    begin
      Result := false;
      Break;
    end;
  end;
end;

function IsMasterAEPlugin(plugin: IInterface): Boolean;
var
  pluginName  : String;
Begin
  pluginName := GetFileName(plugin);
  Result := (CompareStr(pluginName, 'Skyrim.esm') = 0) or (CompareStr(pluginName, 'Update.esm') = 0) or (CompareStr(pluginName, 'Dawnguard.esm') = 0) or (CompareStr(pluginName, 'HearthFires.esm') = 0) or (CompareStr(pluginName, 'Dragonborn.esm') = 0) or (CompareStr(pluginName, 'ccBGSSSE001-Fish.esm') = 0) or (CompareStr(pluginName, 'ccQDRSSE001-SurvivalMode.esl') = 0) or (CompareStr(pluginName, 'ccBGSSSE037-Curios.esl') = 0) or (CompareStr(pluginName, 'ccBGSSSE025-AdvDSGS.esm') = 0) or (CompareStr(pluginName, '_ResourcePack.esl') = 0);
End;

function GetFaceGenPath(pluginName, formID: string; isNewPath, mode: boolean): string;
begin
  if mode = MESHMODE then
    if isNewPath = true then
      Result := Format('%sSP_RDF NPC Replacer Converter\meshes\actors\character\FaceGenData\FaceGeom\%s\%s.nif', [DataPath, pluginName, formID])
    else
      Result := Format('%smeshes\actors\character\FaceGenData\FaceGeom\%s\%s.nif', [DataPath, pluginName, formID]);
  if mode = TEXTUREMODE then
    if isNewPath = true then
      Result := Format('%sSP_RDF NPC Replacer Converter\textures\actors\character\FaceGenData\FaceTint\%s\%s.dds', [DataPath, pluginName, formID])
    else
      Result := Format('%stextures\actors\character\FaceGenData\FaceTint\%s\%s.dds', [DataPath, pluginName, formID]);
end;

function ManipulateFaceGenFile(oldPath, newPath: string; removeFlag: boolean): boolean;
begin
  Result := false;

  // 新しいフォルダがなければ作成
  if not DirectoryExists(ExtractFilePath(newPath)) then
    ForceDirectories(ExtractFilePath(newPath));

  if removeFlag then begin
    if RenameFile(PChar(oldPath), PChar(newPath)) then begin
      AddMessage('Move to: ' + oldPath + ' -> ' + newPath);
      Result := true;
    end else
      AddMessage('Failed to move: ' + oldPath);
  end
  else begin
    // ファイルをコピー
    if CopyFile(PChar(oldPath), PChar(newPath), False) then begin
      AddMessage('Copied: ' + oldPath + ' -> ' + newPath);
      Result := true;
    end else
      AddMessage('Failed to copy: ' + oldPath);
  end;
end;

function GetNPCRecordCount(aFile: IwbFile): Cardinal;
var
  i, count: Cardinal;
  rec:  IInterface;
  group: IwbGroupRecord;
begin
  count := 0;
  group := GroupBySignature(aFile, 'NPC_');
  
  // グループが存在する場合
  if Assigned(group) then begin
    // グループ内のレコード数を取得
    for i := 0 to ElementCount(group) - 1 do begin
      rec := ElementByIndex(group, i);
      // レコードが 'NPC_' シグネチャを持つか確認
      if Signature(rec) = 'NPC_' then
        Inc(count);
    end;
  end;
  
  Result := count;
end;

function ESLFlagedPluginTest(f: IwbFile): boolean;
var
  recordNum, maxRecordNum, npcRecordNum, nextObjectID, numUsedFormID, estRemainingFormID: Cardinal;
  headerVer: Float;
  invalidObjectID: boolean;
begin
  Result := false;
  invalidObjectID := false;

  AddMessage('Checking ESL Plugin: ' + GetFileName(f));

  // レコード数の取得
  recordNum := RecordCount(f);
  AddMessage('Total Records:' + IntToStr(recordNum));
  // ヘッダーバージョンの取得
  headerVer := GetElementNativeValues(ElementByIndex(f, 0), 'HEDR\Version');
  AddMessage('Header version:' + FloatToStr(headerVer));

  // 次に使用される Form ID の取得
  nextObjectID := GetElementNativeValues(ElementByIndex(f, 0), 'HEDR\Next Object ID');
  AddMessage('Next Object ID:' + IntToHex(nextObjectID and $FFFFFF, 1));
  
  // NPCレコードの数を取得
  npcRecordNum := GetNPCRecordCount(f);
  AddMessage('NPC Records:' + IntToStr(npcRecordNum));
  
  // ヘッダーバージョンに応じて変化する値の設定
  if headerVer < EXTESLVER then begin
    // レコード最大数を設定
    maxRecordNum := OLDESLMAXRECORDS;
    // 使用済みForm IDの数を設定
    if (nextObjectID >= ESLSTARTFORMID) and (nextObjectID <= ESLMAXFORMID) then
      numUsedFormID := nextObjectID - ESLSTARTFORMID
    else 
      numUsedFormID := nextObjectID;
  end
  else begin
    // レコード最大数を設定
    maxRecordNum := NEWESLMAXRECORDS;
    // 使用済みForm IDの数を設定
    if nextObjectID < ESLSTARTFORMID then
      numUsedFormID := nextObjectID + ESLSTARTFORMID
    else if (nextObjectID >= ESLSTARTFORMID) and (nextObjectID <= ESLMAXFORMID) then
      numUsedFormID := nextObjectID - ESLSTARTFORMID
    else
      numUsedFormID := nextObjectID;
  end;
  
  AddMessage('Max Record Count:' + IntToStr(maxRecordNum));
  
  // 利用可能なForm ID数の予想値を計算
  estRemainingFormID := maxRecordNum - numUsedFormID;
  AddMessage('Estimate Remaining Form IDs:' + IntToStr(estRemainingFormID));
  
  // Next Object IDが制限範囲を超えていないか判定
  if headerVer < EXTESLVER then begin
    if (nextObjectID < ESLSTARTFORMID) or (nextObjectID > ESLMAXFORMID) then
      invalidObjectID := true;
  end
  else begin
    if nextObjectID > ESLMAXFORMID then
      invalidObjectID := true;
  end;
    


  // Form IDの判定
  // Next Object IDが範囲外
  if invalidObjectID then begin
    AddMessage('Script aborted: Next Object ID is invalid.');
    if MessageDlg('Next Object ID is invalid. Do you want to reset the Next Object ID?', mtConfirmation, [mbOK, mbCancel], 0) = mrOK then begin
      SetElementNativeValues(ElementByIndex(f, 0), 'HEDR\Next Object ID', $800);
      AddMessage('Reset Next Object ID to 800');
      MessageDlg('The Next Object ID has been reset to 800. Check the HEDR field in the File Header and rerun the script.', mtConfirmation, [mbOK], 0);
    end;
    Result := true;
    Exit;
  end;
  
  // Form IDの空きスペースが足りない
  if (estRemainingFormID > 0) and (npcRecordNum > estRemainingFormID) then begin
    AddMessage('Script aborted: Not enough Form ID space.');
    if MessageDlg('Not enough Form IDs available. Do you want to reset the Next Object ID?', mtConfirmation, [mbOK, mbCancel], 0) = mrOK then begin
      SetElementNativeValues(ElementByIndex(f, 0), 'HEDR\Next Object ID', $800);
      AddMessage('Reset Next Object ID to 800');
      MessageDlg('The Next Object ID has been reset to 800. Check the HEDR field in the File Header and rerun the script.', mtConfirmation, [mbOK], 0);
    end;
    Result := true;
    Exit;
  end;
  
  // レコード数が上限以上
  if recordNum >= maxRecordNum then begin
    AddMessage('Script aborted: Too many records.');
    AddMessage('-- Fix Guide --');
    AddMessage('The script has stopped because the number of records (' + IntToStr(maxRecordNum) + ') is equal to or exceeds the number that the ESL-flagged ESP can hold.');
    AddMessage('To make space to edit the ESP, temporarily turn off the ESL flag, then set it again after running the script.');
    AddMessage('If you are familiar with Extended ESL, you may be able to fix this by changing the header version to 1.71.');
    Result := true;
    Exit;
  end;

end;

function DoInitialize: integer;
var
  validInput : boolean;
  opts, selected: TStringList;
  i: Integer;
begin
  testFile            := false;

  firstRecordFileName := '';
  baseFileName        := '';
  replacerFileName    := '';

  removeFaceGen       := false;
  removeFaceGenMissingRec   := false;
  isInputProvided     := false;
  validInput          := false;
  
  opts                := TStringList.Create;
  selected            := TStringList.Create;
  
  Result              := 0;

  {if not RunPreProcDone then begin
    AddMessage('PreProcessor: Initialized');
    RunPreProcDone := True;
  end;
  }
  
  // 各オプションの設定
  try

    opts.Add('Remove FaceGen files in the replacer mod');
    opts.Add('Remove NPC records without FaceGen files');

    if ShowCheckboxForm(opts, selected) then
    begin
      AddMessage('You selected:');
      for i := 0 to selected.Count - 1 do
        AddMessage(opts[i] + ' - ' + selected[i]);
    end
    else begin
      AddMessage('Selection was canceled.');
      Result := -1;
      Exit;
    end;
    

    // コピー元のFaceGenファイルを残すか
    if selected[0] = 'True' then
      removeFaceGen := true;
    
    // FaceGenファイルを持たないNPCレコードをコピーするか
    if selected[1] = 'True' then
      removeFaceGenMissingRec := true;
      
  finally
    opts.Free;
    selected.Free;
  end;

  // プレフィックスを入力
  repeat
    isInputProvided := InputQuery('New Editor ID Prefix Input', 'Enter the prefix. Only letters (a-z, A-Z) and digits (0-9) are allowed.' + #13#10 + 'Underscore (_) will be added to the prefix you enter:', prefix);
    if not isInputProvided then begin
      MessageDlg('Cancel was pressed, aborting the script.', mtInformation, [mbOK], 0);
      Result := -1;
      Exit;
    end;
//    AddMessage('now prefix:' + prefix);
    // 入力のチェック
    if prefix = '' then begin
        MessageDlg('Input is empty. Please reenter prefix.', mtInformation, [mbOK], 0);
        validInput := false;
    end
    else begin
      if InputValidation(prefix) then begin
        AddMessage('The input is valid.');
        validInput := true;
      end
      else begin
        MessageDlg('The input is invalid. Only enter valid characters.', mtInformation, [mbOK], 0);
        AddMessage('The input is invalid.');
        validInput := false;
      end;
    end;
      
    if validInput = false then
      prefix := '';

  until (isInputProvided) and (validInput);

  AddMessage('Prefix set to: ' + prefix);
end;

function DoProcess(e: IInterface): integer;
var
  replacerFile: IwbFile;
  newRecord:  IInterface;
  recordFlag, compareStrRslt: Cardinal;
  eslFlag, useTraitsFlag, missingFacegeom, missingFacetint: boolean;
  oldFormID, newFormID, oldEditorID, newEditorID, recordID: string; // レコードID関連
  oldMeshPath, oldTexturePath, newMeshPath, newTexturePath: string; // FaceGenファイルのパス格納用

begin

  {if not Assigned(e) then begin
    Result := 1; // スキップ
    exit;
  end;
  }
  // 選択中のプラグインを検証、最初のレコードのみ実行する
  if testFile = false then begin
    //  マスターファイルを編集しようとしていたら中止
    if IsMasterAEPlugin(e) then begin
      AddMessage(GetElementEditValues(e, 'EDID') + ' is a member of ' + GetFileName(e) + '! Do not Edit it!');
      Result = -1;
      Exit;
    end;

    // ESLフラグを取得
    replacerFile := GetFile(e);
    eslFlag := GetElementNativeValues(ElementByIndex(replacerFile, 0), 'Record Header\Record Flags\ESL');

    if eslFlag then
      AddMessage('ESLFlag is true.')
    else
      AddMessage('ESLFlag is false.');

    if eslFlag then begin
      // ESLフラグがオンの場合、レコード数と振り分け可能なForm IDの上限チェックを実施
      if ESLFlagedPluginTest(replacerFile) then begin
        Result := -1;
        Exit;
      end;
    end;

    // 最初のレコードからプラグイン名を取得
    firstRecordFileName := GetFileName(replacerFile);
    //AddMessage('Set firstRecordFileName:' + firstRecordFileName);

    // ファイルのテストフラグをオンにして、以後テストはしないようにする
    testFile := true;
  end;

  // Mod名を取得（レコードが所属するファイル名）
  replacerFileName := GetFileName(GetFile(e));
  baseFileName := GetFileName(GetFile(MasterOrSelf(e)));
  
  //AddMessage('firstRecordFileName:' + firstRecordFileName);
  //AddMessage('Now plugin name:' + replacerFileName);
  
  // 最初のレコードが所属するプラグインと異なるプラグインが選択されていたらスキップ
  compareStrRslt := CompareStr(firstRecordFileName, replacerFileName);
  //AddMessage('Set compareStrRslt:' + IntToStr(compareStrRslt));
  if compareStrRslt <> 0 then begin
    AddMessage('A different plugin was found than the one the first record belongs to. Further processing will be skipped.');
    Exit;
  end;

  // NPCレコードでなければスキップ
  if Signature(e) <> 'NPC_' then begin
    AddMessage(GetElementEditValues(e, 'EDID') + ' is not NPC record.');
    Exit;
  end;

  // 選択中のレコードが他のレコードをオーバーライドしていなかったらスキップ
  if IsMaster(e) then begin
    AddMessage(GetElementEditValues(e, 'EDID') + ' does not overwrite other record.');
    Exit;
  end;

  // フラグを初期化
  missingFacegeom := false;
  missingFacetint := false;
  useTraitsFlag := false;

  // コピー元のFormID,EditorID,FaceGenファイルのパスを取得
  oldFormID := IntToHex64(GetElementNativeValues(e, 'Record Header\FormID') and  $FFFFFF, 8);
  oldEditorID := GetElementEditValues(e, 'EDID');

  oldMeshPath := GetFaceGenPath(baseFileName, oldFormID, false, MESHMODE);
//    AddMessage('oldMeshPath:' + oldMeshPath);
  oldTexturePath := GetFaceGenPath(baseFileName, oldFormID, false, TEXTUREMODE);
//    AddMessage('oldTexturePath:' + oldTexturePath);

  // FaceGenファイルが存在するかチェック
  if not FileExists(oldMeshPath) then begin
    AddMessage('File not found: ' + oldMeshPath);
    missingFacegeom := true
  end;
  
  if not FileExists(oldTexturePath) then begin
    AddMessage('File not found: ' + oldTexturePath);
    missingFacetint := true;
  end;

  // レコードがuse traitsフラグを持っているか確認
  recordFlag := GetElementNativeValues(ElementBySignature(e, 'ACBS'), 'Template Flags');
  if (recordFlag and $01) <> 0 then
    useTraitsFlag := true;
  
  // レコードIDを変数に格納
  recordID := 'Form ID: ' + oldFormID + ', Editor ID: ' + oldEditorID;
  // FaceGenファイルが存在しない場合の処理
  // FaceGeomかFaceTintのどちらか片方が存在していない場合
  if (missingFacegeom and not missingFacetint) or (not missingFacegeom and missingFacetint) then begin
    if missingFacegeom then
      AddMessage('FaceGeom file associated with this record is missing.')
    else
      AddMessage('FaceTint file associated with this record is missing.');
    
    AddMessage(recordID);
    AddMessage('The script will be aborted.');
    Result := -1;
    Exit;    
  end
  // 両方のファイルが存在していない場合
  else if missingFacegeom and missingFacetint then begin
    AddMessage('Neither a FaceGeom file nor a FaceTint file exists associated with this record.');
    // ユーザオプションに基づいてレコードを削除するか判断、削除したら次のレコードの処理へ移行
    if removeFaceGenMissingRec then begin
      AddMessage('Remove this record based on the user''s options. ' + recordID);
      Remove(e);
      Exit;
    end;
    // Use Traitsフラグを持っていない場合は異常と判断してスクリプトを中断する
    if useTraitsFlag then
      AddMessage('This record (' + recordID + ') uses a template and has the Use Traits flag, so it''s normal that it doesn''t have FaceGen files.')
    else begin
      AddMessage('This record (' + recordID + ') is expected to have a FaceGen files, but no associated with FaceGen files were found.');
      AddMessage('The script will be aborted.');
      Result := -1;
      Exit;
    end;
  end;

  // レコードを複製
  newRecord := wbCopyElementToFile(e, GetFile(e), True, True);
  if not Assigned(newRecord) then begin
    AddMessage('Error: Failed to copy record for ' + Name(e));
    Exit;
  end;

  // 新しいForm ID, Editor IDを作成し,コピーしたレコードに新しいEditor IDを設定
  newFormID := IntToHex64(GetElementNativeValues(newRecord, 'Record Header\FormID') and  $FFFFFF, 8);
  // AddMessage('New record Form ID: ' + newFormID);
  newEditorID := prefix + '_' + oldEditorID;
  SetElementEditValues(newRecord, 'EDID', newEditorID);
  // AddMessage('Created new record with Editor ID: ' + newEditorID);
  
  // 新しいFaceGenファイルのパスを取得
  newMeshPath := GetFaceGenPath(replacerFileName, newFormID, true, MESHMODE);
//    AddMessage('newMeshPath:' + newMeshPath);
  newTexturePath := GetFaceGenPath(replacerFileName, newFormID, true, TEXTUREMODE);
//    AddMessage('newTexturePath:' + newTexturePath);

  if not STOPFACEGENMANIPULATION then begin
    // FaceGenファイルを新しいパスにコピー&リネームまたは移動&リネーム
    ManipulateFaceGenFile(oldMeshPath, newMeshPath, removeFaceGen);
    ManipulateFaceGenFile(oldTexturePath, newTexturePath, removeFaceGen);
  end;
  
  // TODO:meshファイル内のfacetintのパスが古い情報のままなので変更する(必要？)
  
  // コピー元レコードを削除
  Remove(e);

end;

function DoFinalize: integer;
begin
  AddMessage('PreProcessor: Finalize');
end;

function RunPreProcInitialize: integer;
begin
  Result := DoInitialize;
end;

function RunPreProcessor(e: IInterface): integer;
begin
  Result := DoInitialize;
  if Result <> 0 then exit;

  Result := DoProcess(e);
end;

function RunPreProcFinalize: integer;
begin
  Result := DoFinalize;
end;


function Initialize: integer;
begin
  Result := DoInitialize;
end;

function Process(e: IInterface): integer;
begin
  Result := DoProcess(e);
end;

function Finalize: integer;
begin
  DoFinalize;
end;

end.
