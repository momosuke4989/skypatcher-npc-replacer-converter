unit UserScript;

interface
implementation
uses xEditAPI, SysUtils, StrUtils, Windows;
const
  MeshMode = true;
  TextureMode = false;
  OldESLMaxRecords = 2047;
  NewESLMaxRecords = 4095;
  ESLMaxFormID = 4095;
  ESLMinFormID = 2048;
var
  slExport: TStringList;
  prefix, addSemicolon: string;
  firstRecordFileName, baseFileName, replacerFileName: string;
  testFile, useFormID, isInputProvided: boolean;
  removeFacegen, missingFacegeom, missingFacetint : boolean;



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
            (ch >= '0') and (ch <= '9') or
            (ch = '_')) then
    begin
      Result := false;
      Break;
    end;
  end;
end;

function IsMasterAEPlugin(plugin: IInterface): Boolean;
var
  PluginName  : String;
Begin
  PluginName := GetFileName(plugin);
  Result := (CompareStr(PluginName, 'Skyrim.esm') = 0) or (CompareStr(PluginName, 'Update.esm') = 0) or (CompareStr(PluginName, 'Dawnguard.esm') = 0) or (CompareStr(PluginName, 'HearthFires.esm') = 0) or (CompareStr(PluginName, 'Dragonborn.esm') = 0) or (CompareStr(PluginName, 'ccBGSSSE001-Fish.esm') = 0) or (CompareStr(PluginName, 'ccQDRSSE001-SurvivalMode.esl') = 0) or (CompareStr(PluginName, 'ccBGSSSE037-Curios.esl') = 0) or (CompareStr(PluginName, 'ccBGSSSE025-AdvDSGS.esm') = 0) or (CompareStr(PluginName, '_ResourcePack.esl') = 0);
End;

function GetFaceGenPath(pluginName, formID: string; isNewPath, Mode: boolean): string;
begin
  if Mode = MeshMode then
    if isNewPath = true then
      Result := Format('%sSkypatcher NPC Replacer Converter\meshes\actors\character\FaceGenData\FaceGeom\%s\%s.nif', [DataPath, pluginName, formID])
    else
      Result := Format('%smeshes\actors\character\FaceGenData\FaceGeom\%s\%s.nif', [DataPath, pluginName, formID]);
  if Mode = TextureMode then
    if isNewPath = true then
      Result := Format('%sSkypatcher NPC Replacer Converter\textures\actors\character\FaceGenData\FaceTint\%s\%s.dds', [DataPath, pluginName, formID])
    else
      Result := Format('%stextures\actors\character\FaceGenData\FaceTint\%s\%s.dds', [DataPath, pluginName, formID]);
end;

function ManipulateFaceGenFile(oldPath, newPath: string; removeFlag, Mode: boolean): boolean;
begin
  Result := false;
  // 元ファイルが存在するか確認
  if not FileExists(oldPath) then begin
    AddMessage('File not found: ' + oldPath);
    if Mode = MeshMode then
      missingFacegeom := true
    else
      missingFacetint := true;
    Exit;
  end;

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
  recordNum, maxRecordNum, NPCrecordNum, nextObjectID: Cardinal;
  headerVer: Float;
  invalidObjectID: boolean;
begin
  Result := false;
  invalidObjectID := false;

  AddMessage('Checking ESL Plugin: ' + GetFileName(f));

  // レコード数上限チェック
  // レコード数の取得
  recordNum := RecordCount(f);
  AddMessage('Total Records:' + IntToStr(recordNum));
  // ヘッダーバージョンの取得
  headerVer := GetElementNativeValues(ElementByIndex(f, 0), 'HEDR\Version');
  AddMessage('Header version:' + FloatToStr(headerVer));

  // ヘッダーバージョンに応じて最大レコード数を設定
  if headerVer < 1.71 then
    maxRecordNum := OldESLMaxRecords
  else
    maxRecordNum := NewESLMaxRecords;
    
  AddMessage('Max Record Count:' + IntToStr(maxRecordNum));

  // レコード数の上限チェック
  if recordNum >= maxRecordNum then begin
    AddMessage('Script aborted: Too many records.');
    Result := true;
    Exit;
  end;

  // Form IDの上限チェック
  // NPCレコードの数を取得
  NPCrecordNum := GetNPCRecordCount(f);
//  AddMessage('NPC Records:' + IntToStr(NPCrecordNum));
  
  // 次に使用される Form ID の取得
  nextObjectID := GetElementNativeValues(ElementByIndex(f, 0), 'HEDR\Next Object ID');
//  AddMessage('Next Object ID:' + IntToStr(nextObjectID));
  
  // Next Object IDが不正かどうかチェック
  if headerVer < 1.71 then begin
    if (nextObjectID < ESLMinFormID) or (nextObjectID > ESLMaxFormID) then
      invalidObjectID := true;
  end
  else begin
    if nextObjectID > ESLMaxFormID then
      invalidObjectID := true;
  end;

  if invalidObjectID then begin
    AddMessage('Script aborted: Next Object ID is invalid.');
    Result := true;
    Exit;
  end;

  // 残りの Form ID 数を計算し、足りるかチェック
  AddMessage('Remaining Form IDs:' + IntToStr(ESLMaxFormID - nextObjectID));
  if NPCrecordNum > (ESLMaxFormID - nextObjectID) then begin
    AddMessage('Script aborted: Not enough Form ID space.');
    Result := true;
    Exit;
  end;

end;

function Initialize: integer;
var
  validInput : boolean;
begin
  slExport            := TStringList.Create;
  testFile            := false;
  isInputProvided     := false;
  removeFacegen       := false;
  firstRecordFileName := '';
  baseFileName        := '';
  replacerFileName    := '';
  addSemicolon        := '';
  Result              := 0;
  
  validInput          := false;

  // 出力ファイルに使うのはFormIDとEditorIDのどちらか確認
  if MessageDlg('Use Editor ID for output? (Yes: Editor ID, No: Form ID)', mtConfirmation, [mbYes, mbNo], 0) = mrNo then
    useFormID := true
  else
    useFormID := false;

  // 出力ファイルのデフォルト設定をすべて有効にするか確認
  if MessageDlg('Enable output ini file by default? (Yes: Enable, No: Disable)', mtConfirmation, [mbYes, mbNo], 0) = mrNo then
    addSemicolon := ';';

  // コピー元のFacegenファイルを残すかどうか確認
  if MessageDlg('Do you want to keep the Facegen files in the Replacer Mod? (Yes: Keep, No: Remove)'  + #13#10#13#10 +  'Important: If you choose to remove, the file structure of the Replacer Mod will be changed. If you are not sure what this option does,choose to keep.', mtConfirmation, [mbYes, mbNo], 0) = mrNo then
    removeFacegen := true;

  // プレフィックスを入力
  repeat
    isInputProvided := InputQuery('New Editor ID Prefix Input', 'Enter the prefix. Only letters (a-z, A-Z), digits (0-9), and the underscore (_) are allowed.' + #13#10 + 'Underscore (_) will be added to the prefix you enter:', prefix);
    if not isInputProvided then
    begin
      MessageDlg('Cancel was pressed, aborting the script.', mtInformation, [mbOK], 0);
      Result := -1;
      Exit;
    end;
//    AddMessage('now prefix:' + prefix);
    if prefix = '' then // 入力のチェック
      begin
        MessageDlg('Input is empty. Please reenter prefix.', mtInformation, [mbOK], 0);
        validInput := false;
      end
    else
      begin
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
      
    if validInput = false then begin
      prefix := '';
    end;

  until (isInputProvided) and (validInput);

  AddMessage('Prefix set to: ' + prefix);

end;

function Process(e: IInterface): integer;

var
  replacerFile: IwbFile;
  newRecord:  IInterface;
  compareStrRslt: Cardinal;
  ESLFlag:  boolean;
  oldformID, newformID, trimedOldformID, trimedNewformID: String; 
  oldEditorID, newEditorID, slBaseID, slReplacerID, wnamID, slSkinID: string;
  oldMeshPath, oldTexturePath, newMeshPath, newTexturePath: string;
begin
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
    ESLFlag := GetElementNativeValues(ElementByIndex(replacerFile, 0), 'Record Header\Record Flags\ESL');

    if ESLFlag then
      AddMessage('ESLFlag is true.')
    else
      AddMessage('ESLFlag is false.');

    if ESLFlag then begin
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

  // Facegenファイルのフラグを初期化
  missingFacegeom := false;
  missingFacetint := false;

  // コピー元のEditor IDを取得
  oldEditorID := GetElementEditValues(e, 'EDID');

  // 新しいEditor IDを作成
  newEditorID := prefix + '_' + oldEditorID;

  // レコードを複製
  newRecord := wbCopyElementToFile(e, GetFile(e), True, True);
  if not Assigned(newRecord) then begin
    AddMessage('Error: Failed to copy record for ' + Name(e));
    Exit;
  end;

  // 新しいEditor IDを設定
  SetElementEditValues(newRecord, 'EDID', newEditorID);
  //AddMessage('Created new record with Editor ID: ' + newEditorID);

  // formID,顔ファイルのパスを取得
  oldformID := IntToHex64(GetElementNativeValues(e, 'Record Header\FormID') and  $FFFFFF, 8);
  newformID := IntToHex64(GetElementNativeValues(newRecord, 'Record Header\FormID') and  $FFFFFF, 8);

  oldMeshPath := GetFaceGenPath(baseFileName, oldformID, false, MeshMode);
//    AddMessage('oldMeshPath:' + oldMeshPath);
  newMeshPath := GetFaceGenPath(replacerFileName, newformID, true, MeshMode);
//    AddMessage('newMeshPath:' + newMeshPath);
    
  oldTexturePath := GetFaceGenPath(baseFileName, oldformID, false, TextureMode);
//    AddMessage('oldTexturePath:' + oldTexturePath);
  newTexturePath := GetFaceGenPath(replacerFileName, newformID, true, TextureMode);
//    AddMessage('newTexturePath:' + newTexturePath);

  // 顔ファイルを新しいパスにコピー&リネームまたは移動&リネーム
  if not ManipulateFaceGenFile(oldMeshPath, newMeshPath, removeFacegen, MeshMode) then begin
    AddMessage('failed copy FaceGeom file');
//    if missingFacegeom then
//    AddMessage('FaceGeom file is missing');
    end;

  if not ManipulateFaceGenFile(oldTexturePath, newTexturePath, removeFacegen, TextureMode) then begin
    AddMessage('failed copy FaceTint file');
//    if missingFacetint then
//    AddMessage('FaceTint file is missing');
    end;
    
  // TODO:meshファイル内のfacetintのパスが古い情報のままなので変更する（必要？）

  // 出力ファイル用の配列操作
  // Facegenファイルが見つからなかった場合はiniファイルへの追記をスキップ
  if not missingFacegeom and not missingFacetint then begin
    if useFormID then begin
      // ゼロパディングしない形式のForm IDを設定、iniファイルへの記入はこちらを利用する
      trimedOldformID := IntToHex(GetElementNativeValues(e, 'Record Header\FormID') and  $FFFFFF, 1);
      trimedNewformID := IntToHex(GetElementNativeValues(newRecord, 'Record Header\FormID') and  $FFFFFF, 1);
      
      slBaseID := baseFileName + '|' + trimedOldFormID;
      slReplacerID := replacerFileName + '|' + trimedNewFormID;
    end
    else begin
      slBaseID := oldEditorID;
      slReplacerID := newEditorID;
    end;

    // NPCレコードのWNAMフィールドが設定されていたらWNAMのスキンを反映
    wnamID := IntToHex(GetElementNativeValues(e, 'WNAM') and  $FFFFFF, 1);
//      AddMessage('wnamID is:' + wnamID);
    if wnamID = '0' then
      slSkinID := slReplacerID
    else
      slSkinID := replacerFileName + '|' + wnamID;

    slExport.Add(';' + GetElementEditValues(e, 'FULL'));
    slExport.Add(addSemicolon + 'filterByNpcs=' + slBaseID + ':copyVisualStyle=' + slReplacerID + ':skin=' + slSkinID + #13#10);
  end else begin
    AddMessage('Facegen files copy was failed. Skip adding to this record line into Skypatcher ini file.');
    // テンプレートを利用しているNPCだった場合は正常処理なのでその旨を表示
    if (GetElementEditValues(e, 'TPLT') <> '') then
      AddMessage('This NPC record is made from templates. Some NPC records that use templates do not have a Facegen files, so copying may fail, but this is normal.')
    else
    // テンプレートを利用していなかった場合は異常処理なのでその旨を表示
      AddMessage('This NPC record should have Facegen files but not found. There may be a problem with the mod file structure.');
  end;

  // コピー元レコードを削除
  Remove(e);

end;

function Finalize: integer;
var
  dlgSave: TSaveDialog;
  ExportFileName, saveDir: string;
begin
  if slExport.Count <> 0 then 
  begin
  // Skypatcher iniファイルの出力処理
  saveDir := DataPath + 'Skypatcher NPC Replacer Converter\SKSE\Plugins\Skypatcher\npc\Skypatcher NPC Replacer Converter\';
  if not DirectoryExists(saveDir) then
    ForceDirectories(saveDir);

  dlgSave := TSaveDialog.Create(nil);
    try
      dlgSave.Options := dlgSave.Options + [ofOverwritePrompt];
      dlgSave.Filter := 'Ini (*.ini)|*.ini';
      dlgSave.InitialDir := saveDir;
      dlgSave.FileName := replacerFileName + '.ini';
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
