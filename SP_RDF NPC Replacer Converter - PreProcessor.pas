{
  ==============================================================================
   SP_RDF_NPCReplacerConverter_PreProcessor.pas
  ==============================================================================

   Description:
     This script is part of the "SkyPatcher RDF NPC Replacer Converter" toolset.
     It serves as the *PreProcessor* phase that prepares NPC records before
     configuration generation. The script duplicates selected NPC records and
     renames the Editor ID, copies or moves their associated FaceGen files,
     and performs validation for ESL-flagged plugins to ensure safe FormID allocation.

   Features:
     - Prompts user for preprocessing options such as FaceGen removal.
     - Validates ESL-flagged ESPs and resets invalid FormIDs if necessary.
     - Copies or moves FaceGen (FaceGeom / FaceTint) files with renamed paths.
     - Adds a prefix to Editor IDs of duplicated NPC records.
     - Removes NPCs missing FaceGen files if specified by user.

   Usage:
     Run this script in xEdit (SSEEdit) on the target plugin before executing
     the ConfigGen script. It is intended to be called from the main converter
     or executed directly via "Apply Script" in the xEdit interface.

   Notes:
     - Compatible with ESL-flagged plugins (supports extended ESL headers).
     - Dependent on standard xEdit functions; no external libraries required.

   Author:mmsk4989
   Version: 2.2.0
   Last Updated: [2025-11-21]
  ==============================================================================
}

unit SP_RDF_NPCReplacerConverter_PreProcessor;

uses 'NPC Replacer Converter - Shared\NPCRC_CommonUtils';

interface

function RunPreProcInitialize: integer;
function RunPreProcessor(const e: IInterface; var createdRecord: IInterface): integer;
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
  // ファイル関連変数
  firstRecordFileName, baseFileName, replacerFileName: string;
  testFile: boolean;

  // イニシャル処理で設定・使用する変数
  prefix: string;
  removeFaceGen, removeFaceGenMissingRec, isInputProvided: boolean;
  
  // サマリー用変数
  recordCount, missingFaceGeomCount,
  missingFaceTintCount, missingFaceGenBothCount,
  useTraitsCount, removedRecordCount: integer;
  
  missingFaceGeomRecordID,
  missingFaceTintRecordID,
  missingFaceGenBothRecordID: TStringList;

function IsMasterAEPlugin(plugin: IInterface): Boolean;
var
  pluginName  : String;
Begin
  pluginName := GetFileName(plugin);
  Result := (CompareStr(pluginName, 'Skyrim.esm') = 0) or
            (CompareStr(pluginName, 'Update.esm') = 0) or
            (CompareStr(pluginName, 'Dawnguard.esm') = 0) or
            (CompareStr(pluginName, 'HearthFires.esm') = 0) or
            (CompareStr(pluginName, 'Dragonborn.esm') = 0) or
            (CompareStr(pluginName, 'ccBGSSSE001-Fish.esm') = 0) or
            (CompareStr(pluginName, 'ccQDRSSE001-SurvivalMode.esl') = 0) or
            (CompareStr(pluginName, 'ccBGSSSE037-Curios.esl') = 0) or
            (CompareStr(pluginName, 'ccBGSSSE025-AdvDSGS.esm') = 0) or
            (CompareStr(pluginName, '_ResourcePack.esl') = 0);
End;

function GetFaceGenPath(pluginName, formID: string; isNewPath, mode: boolean): string;
begin
  if mode = MESHMODE then
    if isNewPath = true then
      Result := Format('%sSkyPatcher RDF NPC Replacer Converter\meshes\actors\character\FaceGenData\FaceGeom\%s\%s.nif', [DataPath, pluginName, formID])
    else
      Result := Format('%smeshes\actors\character\FaceGenData\FaceGeom\%s\%s.nif', [DataPath, pluginName, formID]);
  if mode = TEXTUREMODE then
    if isNewPath = true then
      Result := Format('%sSkyPatcher RDF NPC Replacer Converter\textures\actors\character\FaceGenData\FaceTint\%s\%s.dds', [DataPath, pluginName, formID])
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

procedure ReplaceFaceTintPath(faceMeshPath, faceTextureFullPath: string);
var
    nif              : TwbNifFile;
    block            : TwbNifBlock;
    element          : TdfElement;
    lTextureList     : TList;
    i, j, p          : Integer;
    key,
    newFaceTintPath  : string;
    findFaceTintPath : boolean;
begin
    nif := TwbNifFile.Create;
    nif.LoadFromFile(faceMeshPath);
    
    findFaceTintPath := false;
    
    lTextureList := TList.Create;
    
    // Iterate over all blocks in a nif file and locate elements holding textures.
    for i := 0 to nif.BlocksCount - 1 do begin
        block := nif.Blocks[i];
        
        if block.BlockType = 'BSShaderTextureSet' then begin
            element := block.Elements['Textures'];
            for j := 0 to element.Count - 1 do
                lTextureList.Add(element[j]);
        end; 
    end;
    
    //AddMessage(Format('Found %d elements.', [Elements.Count]));

    // Skip to the next file If nothing was found.
    if lTextureList.Count = 0 then begin
      lTextureList.Free;
      nif.Free;
      Exit;
    end;
    
    // Do text replacement in collected elements.
    for i := 0 to lTextureList.Count - 1 do begin
      if not Assigned(lTextureList[i]) then
        continue;

      element := TdfElement(lTextureList[i]);
      
      if element.EditValue = '' then
        continue;
        
      if Pos('FaceTint', element.EditValue) > 0 then begin
        findFaceTintPath := true;
        break;
      end;
        
{
      // 元の文字列を取得
      oldFaceTintPath := element.EditValue;
      if oldFaceTintPath = '' then
        continue;

      if Pos('FaceTint', oldFaceTintPath) > 0 then begin
        key := 'textures\actors\character\FaceGenData\FaceTint\';
        p := Pos(LowerCase(key), LowerCase(faceTextureFullPath));
        newFaceTintPath := Copy(faceTextureFullPath, p, Length(faceTextureFullPath) - p + 1);
        element.EditValue := newFaceTintPath;
        // Get the root of the last processed element (the file element itself) and save.
        element.Root.SaveToFile(faceMeshPath);
        //AddMessage(Format('Processed face %s.', [faceMeshPath]));
      end;
      }
    end;
    
    if not findFaceTintPath then begin
      AddMessage('FaceTint file path not found.');
      Exit;
    end;
    
    // 新しいFaceTintパスをnifファイルに設定
    key := 'textures\actors\character\FaceGenData\FaceTint\';
    p := Pos(LowerCase(key), LowerCase(faceTextureFullPath));
    newFaceTintPath := Copy(faceTextureFullPath, p, Length(faceTextureFullPath) - p + 1);
    element.EditValue := newFaceTintPath;

    element.Root.SaveToFile(faceMeshPath);

    lTextureList.Free;
    nif.Free;    
end;

function DoInitialize: integer;
var
  validInput : boolean;
  slOpts, slDisableOpts: TStringList;
  checkBoxCaption: string;
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
  
  recordCount                 := 0;
  missingFaceGeomCount        := 0;
  missingFaceTintCount        := 0;
  missingFaceGenBothCount     := 0;
  useTraitsCount              := 0;
  removedRecordCount          := 0;
  
  missingFaceGeomRecordID     := TStringList.Create;
  missingFaceTintRecordID     := TStringList.Create;
  missingFaceGenBothRecordID  := TStringList.Create;
  
  slOpts                := TStringList.Create;
  slDisableOpts         := TStringList.Create;
  
  checkBoxCaption             := 'Choose PreProcessor Option';
  
  Result              := 0;


  // 各オプションの設定
  try

    slOpts.Values['Remove FaceGen files in the replacer mod'] := 'False';
    slOpts.Values['Remove NPC records without FaceGen files'] := 'False';

    if ShowCheckboxForm(slOpts, slDisableOpts, checkBoxCaption) then
    begin
      AddMessage('You selected:');
      for i := 0 to slOpts.Count - 1 do
        AddMessage(slOpts.Names[i] + ' - ' + slOpts.ValueFromIndex[i]);
    end
    else begin
      AddMessage('Selection was canceled.');
      Result := -1;
      Exit;
    end;
    

    // コピー元のFaceGenファイルを残すか
    removeFaceGen := GetBoolSLValue(slOpts.Values['Remove FaceGen files in the replacer mod']);
    
    // FaceGenファイルを持たないNPCレコードをコピーするか
    removeFaceGenMissingRec := GetBoolSLValue(slOpts.Values['Remove NPC records without FaceGen files']);
      
  finally
    slOpts.Free;
    slDisableOpts.Free;
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
      if EditorIDInputValidation(prefix, false) then begin
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

function DoProcess(const e: IInterface; var createdRecord: IInterface): integer;
var
  replacerFile: IwbFile;
  newRecord:  IInterface;
  recordFlag, compareStrRslt: Cardinal;
  eslFlag, useTraitsFlag,
  missingFacegeom, missingFacetint: boolean;
  oldFormID, newFormID,
  oldEditorID, newEditorID,
  recordID, recordFileName: string; // レコードID関連
  oldMeshPath, oldTexturePath,
  newMeshPath, newTexturePath: string; // FaceGenファイルのパス格納用

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
  
  Inc(recordCount);
  
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
  
  // レコードID,ファイル名を変数に格納
  recordID := 'Form ID: ' + oldFormID + ', Editor ID: ' + oldEditorID;
  recordFileName := 'File Name: ' + GetFileName(MasterOrSelf(e));
  
  // FaceGenファイルが存在しない場合の処理
  // FaceGeomかFaceTintのどちらも存在していない場合
  if missingFacegeom and missingFacetint then begin
    Inc(missingFaceGenBothCount);
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    AddMessage('Neither a FaceGeom file nor a FaceTint file exists associated with this record.');
    // ユーザオプションに基づいてレコードを削除するか判断、削除したら次のレコードの処理へ移行
    if removeFaceGenMissingRec then begin
      AddMessage('Remove this record based on the user''s options. ' + recordID);
      AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
      Inc(removedRecordCount);
      Remove(e);
      Exit;
    end;
    
    // Use Traitsフラグを持っていない場合は異常と判断し、処理をスキップ
    if useTraitsFlag then begin
      AddMessage('This record (' + recordID + ') uses a template and has the Use Traits flag, so it''s normal that it doesn''t have FaceGen files.');
      AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
      Inc(useTraitsCount);
      missingFaceGenBothRecordID.Add(recordID + ' (with UseTraits flag)');
    end
    else begin
      AddMessage('This record (' + recordID + ') should have FaceGen files, but none were found.');
      AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
      missingFaceGenBothRecordID.Add(recordFileName + ' ' + recordID);
      Exit;
    end;
  end
  else if missingFacegeom and not missingFacetint then begin
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    AddMessage('FaceGeom file associated with this record (' + recordID + ') is missing.');
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    Inc(missingFaceGeomCount);
    missingFaceGeomRecordID.Add(recordFileName + ' ' + recordID);
    Exit;
  end
  else if not missingFacegeom and missingFacetint then begin
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    AddMessage('FaceTint file associated with this record (' + recordID + ') is missing.');
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    Inc(missingFaceTintCount);
    missingFaceTintRecordID.Add(recordFileName + ' ' + recordID);
    Exit;
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
    if not missingFacegeom and not missingFacetint then begin
      // FaceGenファイルを新しいパスにコピー&リネームまたは移動&リネーム
      ManipulateFaceGenFile(oldMeshPath, newMeshPath, removeFaceGen);
      ManipulateFaceGenFile(oldTexturePath, newTexturePath, removeFaceGen);
      ReplaceFaceTintPath(newMeshPath, newTexturePath);
    end;
  end;
  
  if Assigned(newRecord) then
    createdRecord := newRecord;
  
  // コピー元レコードを削除
  Remove(e);

end;

function DoFinalize: integer;
var
  i: integer;
begin
  AddMessage('--------------------------------PreProcessing Summary--------------------------------');
  AddMessage('Total Records Processed: ' + IntToStr(recordCount));
  AddMessage('Total Records with Missing FaceGen Files: ' + IntToStr(missingFaceGenBothCount + missingFaceGeomCount + missingFaceTintCount));
  AddMessage('Total Removed Records: ' + IntToStr(removedRecordCount));
  
  AddMessage(#13#10 + 'Records Missing Both FaceGen Files: ' + IntToStr(missingFaceGenBothCount));
  AddMessage(' (with UseTraits Flag): ' + IntToStr(useTraitsCount));
  for i := 0 to missingFaceGenBothRecordID.Count - 1 do
    AddMessage(missingFaceGenBothRecordID[i]);
    
  AddMessage(#13#10 + 'Records Missing FaceGeom File: ' + IntToStr(missingFaceGeomCount));
  for i := 0 to missingFaceGeomRecordID.Count - 1 do
    AddMessage(missingFaceGeomRecordID[i]);
    
  AddMessage(#13#10 + 'Records Missing FaceTint File: ' + IntToStr(missingFaceTintCount));
  for i := 0 to missingFaceTintRecordID.Count - 1 do
    AddMessage(missingFaceTintRecordID[i]);
    
  AddMessage(#13#10 + '------------------------------PreProcessing Summary End------------------------------');
  
  missingFaceGeomRecordID.Free;
  missingFaceTintRecordID.Free;
  missingFaceGenBothRecordID.Free;
end;

function RunPreProcInitialize: integer;
begin
  AddMessage('PreProcessor: Initialize');
  Result := DoInitialize;
end;

function RunPreProcessor(const e: IInterface; var createdRecord: IInterface): integer;
begin
  AddMessage('PreProcessor: Run PreProcess');
  Result := DoProcess(e, createdRecord);
end;

function RunPreProcFinalize: integer;
begin
  AddMessage('PreProcessor: Finalize');
  Result := DoFinalize;
end;


function Initialize: integer;
begin
  Result := DoInitialize;
end;

function Process(e: IInterface): integer;
var convertedRecord: IInterface;
begin
  convertedRecord := nil;
  Result := DoProcess(e, convertedRecord);
  if Assigned(convertedRecord) then
    AddMessage('Converted NPC record name:' + Name(convertedRecord));
end;

function Finalize: integer;
begin
  DoFinalize;
end;

end.
