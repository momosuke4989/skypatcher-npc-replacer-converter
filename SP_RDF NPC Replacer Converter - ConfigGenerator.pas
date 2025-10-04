{
  ==============================================================================
   SP_RDF_NPCReplacerConverter_ConfigGenerator.pas
  ==============================================================================

   Description:
     This script is part of the "SkyPatcher RDF NPC Replacer Converter" toolset.
     It functions as the *Config Generator (ConfigGen)* phase, executed after
     the PreProcessor. Its purpose is to create configuration files for either
     **SkyPatcher** or **Race Distribution Framework (RDF)** based on user-selected
     options and NPC record data gathered from the list of plugins currently loaded
     in xEdit.

   Features:
     - Integrates seamlessly with the PreProcessor phase (optional).
     - Prompts user to select output mode (SkyPatcher / RDF) and generation options.
     - Scans and compares NPC records (original vs. replacer) to determine
       which parameters (appearance, race, gender, etc.) should be replaced.
     - Generates structured `.ini` (for SkyPatcher) or `.txt` (for RDF) config files.
     - Automatically comments out or enables settings according to user preferences.

   Usage:
     1. Run this script in xEdit (SSEEdit) on your replacer plugin.
     2. Select whether to run in Integration Mode (to invoke PreProcessor).
     3. Choose your config generation target (SkyPatcher or RDF).
     4. Select desired options in the checklist dialog.
     5. The script will process NPC records and output a ready-to-use config file
        under the `Data\SkyPatcher RDF NPC Replacer Converter\...` directory.

   Notes:
      - Intended for Skyrim SE/AE with SkyPatcher and RDF support.
      - Uses `SP_RDF_NPCReplacerConverter_PreProcessor.pas` when Integration Mode is selected.
      - This script can also be run standalone if the PreProcessor has already been applied.
      - Compatible with both FormID- and EditorID-based reference methods.

   Author:mmsk4989
   Version: 2.0
   Last Updated: [2025-10-04]
  ==============================================================================
}

unit SP_RDF_NPCReplacerConverter_ConfigGenerator;

uses 'SP_RDF NPC Replacer Converter - PreProcessor';

const
  USE_EDITOR_ID = false;

var
  // 設定ファイル出力用変数
  slExport: TStringList;
  targetFileName, replacerFileName: string;
  
  // イニシャル処理で設定・使用する変数
  callPreProcessor, useSkyPatcher, useFormID, disableAll, replaceVS, replaceSkin, forceEnableRace, forceEnableGender, forceEnableName, forceEnableVoiceType: boolean;

function ShowCheckboxForm(const options: TStringList; var selected: TStringList; caption: string): Boolean;
var
  form: TForm;
  checklist: TCheckListBox;
  btnOK, btnCancel: TButton;
  i: Integer;
begin
  Result := False;

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

    // 選択肢を追加
    for i := 0 to options.Count - 1 do begin
      checklist.Items.Add(options[i]);
      // skinオプションはデフォルトをオンに設定
      if (options[i] = 'Replace Visual Style') or (options[i] = 'Replace Skin') then
        checklist.Checked[i] := true;
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

function GenerateVisualStyleString(const targetID, replacerID: string; useSkyPatcher: boolean): string;
begin
  Result := '';
    if useSkyPatcher then
      Result := 'filterByNpcs=' + TargetID + ':copyVisualStyle=' + ReplacerID
    else
      Result := 'match=' + TargetID + ' swap=' + ReplacerID;
end;

function Initialize: integer;
var
  validInput: boolean;
  opts, selected: TStringList;
  checkBoxCaption: string;
  i: Integer;
begin
  slExport            := TStringList.Create;

  callPreProcessor    := false;
  useSkyPatcher       := false;
  useFormID           := false;
  
  disableAll          := false;
  replaceVS           := false;
  replaceSkin         := false;
  
  forceEnableRace         := false;
  forceEnableGender       := false;
  forceEnableName         := false;
  forceEnableVoiceType    := false;
  
  opts                := TStringList.Create;
  selected            := TStringList.Create;
  
  checkBoxCaption := '';
  
  Result              := 0;
  
  if MessageDlg(
    'Run in Integration Mode?' + #13#10 +
    'Yes = Run with PreProcessor' + #13#10 +
    'No = Run ConfigGenerator only', mtConfirmation, [mbYes, mbNo], 0
    ) = mrYes then
    callPreProcessor := true;
    
  if MessageDlg(
    'Select which config file to generate:' + #13#10 +
    'Yes = Generate for SkyPatcher' + #13#10 +
    'No = Generate for RDF',
    mtConfirmation, [mbYes, mbNo], 0
    ) = mrYes then
    useSkyPatcher := true;
  
  if useSkyPatcher then
    checkBoxCaption := 'Choose SkyPatcher Option'
  else
    checkBoxCaption := 'Choose RDF Option';

  if callPreProcessor then
    Result := RunPreProcInitialize;
    
  // 各オプションの設定
  try
    opts.Add('Use Form ID for config file output');
    opts.Add('Disable the config file by default');
    
    if useSkyPatcher then begin
      opts.Add('Replace Visual Style');
      opts.Add('Replace Skin');
      opts.Add('Force Replace Race');
      opts.Add('Force Replace Gender');
      opts.Add('Force Replace Name');
      opts.Add('Force Replace VoiceType');
    end;

    if ShowCheckboxForm(opts, selected, checkBoxCaption) then
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
    

    // 出力ファイルに使うのはFormIDとEditorIDのどちらか
    useFormID := (selected.Count > 0) and (selected[0] = 'True');
      
    // 出力ファイルの記述をすべてコメントアウトするか
    disableAll := (selected.Count > 1) and (selected[1] = 'True');
      
    // SkyPatcher利用時のオプション設定
    if useSkyPatcher and (selected.Count >= 8) then begin
      replaceVS := selected[2] = 'True';            // 見た目を変更するか
      replaceSkin := selected[3] = 'True';          // 肌を変更するか
      forceEnableRace := selected[4] = 'True';      // 種族を強制的に変更するか
      forceEnableGender := selected[5] = 'True';    // 性別を強制的に変更するか
      forceEnableName := selected[6] = 'True';      // 名前を強制的に変更するか
      forceEnableVoiceType := selected[7] = 'True'; // 音声タイプを強制的に変更するか
    end;
  finally
    opts.Free;
    selected.Free;
  end;

end;

function Process(e: IInterface): integer;

var
  replacerFlags, templateFlags, replacerRaceElement, replacerVoiceTypeElement, targetFlags, targetRaceElement, targetVoiceTypeElement: IInterface;
  replacerRecord, targetRecord, replacerRaceRecord, replacerVoiceTypeRecord, targetRaceRecord, targetVoiceTypeRecord: IwbMainRecord;
  replacerName, targetName: string;
  replacerFormID, underscorePos: Cardinal;
  originalTargetID, recordSignature, targetFormID, targetEditorID, replacerEditorID: string; // レコードID関連
  coChar, commentOutCopyVS, commentOutSkin, commentOutRace, commentOutGender, commentOutName, commentOutVoiceType: string; //コメントアウト用変数
  trimedTargetFormID, trimedReplacerFormID, slTargetID, slReplacerID, wnamID, slSkinID, slRace, slGender, slName, slVoiceType: string; // SkyPatcher iniファイルの記入用
  useTraits, sameRace, sameGender, sameName, sameVoiceType: boolean;
begin
  targetFormID    := '';
  targetEditorID  := '';
  
  coChar               := '';
  commentOutCopyVS     := '';
  commentOutSkin       := '';
  commentOutRace       := '';
  commentOutGender     := '';
  commentOutName       := '';
  commentOutVoiceType  := '';
  
  recordSignature := 'NPC_';

  // NPCレコードでなければスキップ
  if Signature(e) <> 'NPC_' then begin
    AddMessage(GetElementEditValues(e, 'EDID') + ' is not NPC record.');
    Exit;
  end;
  
  // リプレイサーMod名を取得
  replacerFileName := GetFileName(GetFile(e));
  
  if callPreProcessor then
    Result := RunPreProcessor(e, replacerRecord)
  else
    replacerRecord := e;
  
  // リプレイサーNPCのForm ID, Editor IDを取得
  replacerFormID := GetElementNativeValues(replacerRecord, 'Record Header\FormID');
   //AddMessage('Replacer Form ID: ' + IntToStr(replacerFormID));
   //AddMessage('Replacer Form ID: ' + IntToHex(replacerFormID, 8));
  replacerEditorID := GetElementEditValues(replacerRecord, 'EDID');
  // AddMessage('Replacer Editor ID: ' + replacerEditorID);
  
  // リプレイサーNPCのEditor IDからオリジナルのEditor IDを取得
  underscorePos := Pos('_', replacerEditorID);
  originalTargetID := Copy(replacerEditorID, underscorePos + 1, Length(replacerEditorID) - underscorePos);
  
  // オリジナルのEditor IDからターゲットNPCのレコードを取得
  targetRecord := FindRecordByRecordID(originalTargetID, 'NPC_', USE_EDITOR_ID);
  
  if not Assigned(targetRecord) then begin
    AddMessage('Target record not found. Processing will be skipped.');
    Exit;
  end;
  AddMessage('Found record: Editor ID: ' + GetElementEditValues(targetRecord, 'EDID') + ' Name: ' + GetElementEditValues(targetRecord, 'FULL'));
  targetFileName := GetFileName(targetRecord);
  AddMessage('Target file name set to: ' + targetFileName);
  
  // ターゲットNPCのFormID,EditorIDを取得
  targetFormID := IntToHex64(GetElementNativeValues(targetRecord, 'Record Header\FormID') and  $FFFFFF, 8);
    //AddMessage('Target Record Form ID: ' + targetFormID);
  targetEditorID := GetElementEditValues(targetRecord, 'EDID');
    //AddMessage('Target Record Editor ID: ' + targetEditorID);
  
  // リプレイサーNPCのフラグ、種族、名前、音声タイプを取得
  replacerFlags := ElementByPath(replacerRecord, 'ACBS - Configuration');
  replacerRaceElement := ElementByPath(replacerRecord, 'RNAM');
  replacerRaceRecord := MasterOrSelf(LinksTo(replacerRaceElement));
  replacerName := GetElementEditValues(replacerRecord, 'FULL');
  replacerVoiceTypeElement := ElementByPath(replacerRecord, 'VTCK');
  replacerVoiceTypeRecord := MasterOrSelf(LinksTo(replacerVoiceTypeElement));
  
  // レコードがuse traitsフラグを持っているか確認し、持っていた場合はスキップ
  templateFlags := ElementByPath(replacerFlags, 'Template Flags');
  useTraits := GetElementNativeValues(templateFlags, 'Use Traits') <> 0;
  
  if useTraits then begin
    AddMessage('This NPC Record has Use Traits Template Flag. Processing will be skipped.');
    Exit;
  end;
  
  // ターゲットNPCのフラグ、種族、名前、音声タイプを取得
  targetFlags := ElementByPath(targetRecord, 'ACBS - Configuration');
  targetRaceElement := ElementByPath(targetRecord, 'RNAM');
  targetRaceRecord := MasterOrSelf(LinksTo(targetRaceElement));
  targetName := GetElementEditValues(targetRecord, 'FULL');
  targetVoiceTypeElement := ElementByPath(targetRecord, 'VTCK');
  targetVoiceTypeRecord := MasterOrSelf(LinksTo(targetVoiceTypeElement));
  
  // フォロワーNPCとターゲットNPCの種族、性別、音声タイプを比較して、結果をフラグに反映する。
  if GetElementNativeValues(replacerRaceRecord, 'Record Header\FormID') = GetElementNativeValues(targetRaceRecord, 'Record Header\FormID') then
    sameRace := true
  else
    sameRace := false;
    
  if GetElementEditValues(targetFlags, 'Flags\Female') = GetElementEditValues(replacerFlags, 'Flags\Female') then
    sameGender := true
  else
    sameGender := false;
    
  if replacerName = targetName then
    sameName := true
  else
    sameName := false;
  
  if GetElementNativeValues(replacerVoiceTypeRecord, 'Record Header\FormID') = GetElementNativeValues(targetVoiceTypeRecord, 'Record Header\FormID') then
    sameVoiceType := true
  else
    sameVoiceType := false;
  
  // SkyPatcherかRDFの利用に応じてコメントアウト文字を切り替え
  if useSkyPatcher then
    coChar := ';'
  else
    coChar := '#';
  
  // オプションの選択に応じて、設定行をコメントアウトする
  if disableAll then begin
    commentOutCopyVS    := coChar;
    commentOutSkin      := coChar;
    commentOutRace      := coChar;
    commentOutGender    := coChar;
    commentOutName      := coChar;
    commentOutVoiceType := coChar;
  end
  else begin
    if useSkyPatcher and not replaceVS then
      commentOutCopyVS := coChar;
      
    if not replaceSkin then
      commentOutSkin := coChar;
    
    if not forceEnableRace and sameRace then
      commentOutRace := coChar;
    
    if not forceEnableGender and sameGender then
      commentOutGender := coChar;
    
    if not forceEnableName and sameName then
      commentOutName := coChar;
    
    if not forceEnableVoiceType and sameVoiceType then
      commentOutVoiceType := coChar;
  end;
  
  // 出力ファイル用の配列操作
  if useFormID then begin
    // ゼロパディングしない形式のForm IDを設定、iniファイルへの記入はこちらを利用する  
    if  UpperCase(Copy(targetFormID, 1, 2)) = 'FE' then
      trimedTargetFormID := Copy(targetFormID, 6, 8)
    else
      trimedTargetFormID := Copy(targetFormID, 3, 8);
      
    trimedTargetFormID := RemoveLeadingZeros(trimedTargetFormID);
    
    trimedReplacerFormID := IntToHex(replacerFormID and  $FFFFFF, 1);
    
    if useSkyPatcher then begin
      slTargetID := targetFileName + '|' + trimedTargetFormID;
      slReplacerID := replacerFileName + '|' + trimedReplacerFormID;
    end
    else begin
      slTargetID := trimedTargetFormID + '~' + targetFileName;
      slReplacerID := trimedReplacerFormID + '~' + replacerFileName;
    end;
    
    slRace  := GetFileName(replacerRaceRecord) + '|' + IntToHex(FormID(replacerRaceRecord) and  $FFFFFF, 1);
    slVoiceType := GetFileName(replacerVoiceTypeRecord) + '|' + IntToHex(FormID(replacerVoiceTypeRecord) and  $FFFFFF, 1);
  end
  else begin
    slTargetID := targetEditorID;
    slReplacerID := replacerEditorID;
    slRace  := EditorID(replacerRaceRecord);
    slVoiceType := EditorID(replacerVoiceTypeRecord);
  end;
  
  // NPCレコードのWNAMフィールドが設定されていたらWNAMのスキンを反映。
  // 設定されていない場合はnullでデフォルトボディを指定。
  wnamID := IntToHex(GetElementNativeValues(replacerRecord, 'WNAM') and  $FFFFFF, 1);
  //  AddMessage('wnamID is:' + wnamID);
  if wnamID = '0' then
    slSkinID := 'null'
  else
    slSkinID := replacerFileName + '|' + wnamID;
    
  // 性別フラグを反映する文字列を入力
  if GetElementEditValues(replacerFlags, 'Flags\Female') = 1 then
    slGender := ':setFlags=female'
  else
    slGender := ':removeFlags=female';
  
  // 名前を入力
  slName := replacerName;
  
  
  slExport.Add(coChar + GetElementEditValues(targetRecord, 'FULL'));
  //slExport.Add(commentOutCopyVS + 'filterByNpcs=' + slTargetID + ':copyVisualStyle=' + slReplacerID);
  slExport.Add(commentOutCopyVS + GenerateVisualStyleString(slTargetID, slReplacerID, useSkyPatcher));
  
  // SkyPatcher利用時のみ出力する
  if useSkyPatcher then begin
    slExport.Add(commentOutSkin + 'filterByNpcs=' + slTargetID + ':skin=' + slSkinID);
    slExport.Add(commentOutRace + 'filterByNpcs=' + slTargetID + ':race=' + slRace);
    slExport.Add(commentOutGender + 'filterByNpcs=' + slTargetID + slGender);
    slExport.Add(commentOutName + 'filterByNpcs=' + slTargetID + ':fullName=~' + slName + '~');
    slExport.Add(commentOutVoiceType + 'filterByNpcs=' + slTargetID + ':voiceType=' + slVoiceType);
  end;
  
  slExport.Add(#13#10);

end;

function Finalize: integer;
var
  dlgSave: TSaveDialog;
  ExportFileName, saveDir, filterString, fileExtension: string;
begin
  RunPreProcFinalize;
  if slExport.Count <> 0 then 
  begin
  
  // SkyPatcherかRDFの利用に応じて出力先、拡張子を変更
  if useSkyPatcher then begin
    saveDir := DataPath + 'SkyPatcher RDF NPC Replacer Converter\SKSE\Plugins\SkyPatcher\npc\SkyPatcher NPC Replacer Converter\';
    filterString := 'Ini (*.ini)|*.ini';
    fileExtension := '.ini';
  end
  else begin
    saveDir := DataPath + 'SkyPatcher RDF NPC Replacer Converter\SKSE\Plugins\RaceSwap\';
    filterString := 'Txt (*.txt)|*.txt';
    fileExtension :=  '.txt';
  end;
  
  // 設定ファイルの出力処理
  if not DirectoryExists(saveDir) then
    ForceDirectories(saveDir);

  dlgSave := TSaveDialog.Create(nil);
    try
      dlgSave.Options := dlgSave.Options + [ofOverwritePrompt];
      dlgSave.Filter := filterString;
      dlgSave.InitialDir := saveDir;
      dlgSave.FileName := replacerFileName + fileExtension;
  if dlgSave.Execute then 
    begin
      ExportFileName := dlgSave.FileName;
      AddMessage('Saving ' + ExportFileName);
      slExport.SaveToFile(ExportFileName);
    end;
  finally
    dlgSave.Free;
    end;
  end;
    slExport.Free;
end;

end.
