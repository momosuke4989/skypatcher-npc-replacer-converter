unit UserScript;

interface
implementation
uses xEditAPI, SysUtils, StrUtils, Windows;
const
  MeshMode = true;
  TextureMode = false;
var
  slExport: TStringList;
  prefix, addSemicolon: string;
  baseFile, replacerFile: string;
  isESL, useFormID, isInputProvided: boolean;
  removeFacegen, missingFacegeom, missingFacetint : boolean;

function Initialize: integer;
begin
  slExport       := TStringList.Create;
  isESL          := false;
  isInputProvided:= false;
  removeFacegen  := false;
  baseFile       := '';
  replacerFile   := '';
  addSemicolon   := '';
  Result         := 0;

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
  // TODO:入力チェック処理（必要？）
  repeat
    isInputProvided := InputQuery('New Editor ID Prefix Input', 'Enter the prefix. Only letters (a-z, A-Z), digits (0-9), and the underscore (_) are allowed.' + #13#10 + 'Underscore (_) will be added to the prefix you enter:', prefix);
    if not isInputProvided then
    begin
      MessageDlg('Cancel was pressed, aborting the script.', mtInformation, [mbOK], 0);
      Result := -1;
      Exit;
    end
    else if prefix = '' then
    begin
      MessageDlg('Input is empty. Please reenter prefix.', mtInformation, [mbOK], 0);
    end;
  until (isInputProvided) and (prefix <> '');

  AddMessage('Prefix set to: ' + prefix);

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
var
  Result : boolean;
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

function Process(e: IInterface): integer;

var
  ESLCheck: IInterface;
  newRecord: IInterface;
  oldformID, newformID, trimedOldformID, trimedNewformID: String; 
  trimDigits:   Cardinal;
  oldEditorID, newEditorID, slBaseID, slReplacerID, wnamID, slSkinID: string;
  oldMeshPath, oldTexturePath, newMeshPath, newTexturePath: string;
begin
  //  マスターファイルを編集しようとしていたら中止
  if IsMasterAEPlugin(e) then begin
    AddMessage(GetElementEditValues(e, 'EDID') + ' is a member of ' + GetFileName(e) + '! Do not Edit it!');
    Exit;
  end;

  // TODO:複数のプラグインを選択していたら中止

{
  // ESLフラグを取得
  ESLCheck := GetFile(e);
  if (GetElementNativeValues(ElementByIndex(ESLCheck, 0), 'Record Header\Record Flags\ESL') == false) then
    isESL := true;
  
  If isESL Then
    AddMessage('This plugin has ESL Flag!')
  Else
    AddMessage('This plugin has not ESL Flag!');
}

  // TODO:レコード数上限に達していたらスクリプトを中止する
  // TODO:ESLレコードのバージョンを確認する。1.7.1以降なら最大数は4096 それ以下は2048
  
  // TODO:元レコードがマスターファイルではない場合ユーザに確認。Mod用リプレイサーの編集ならOK、他の普通のModならNG

  // NPCレコードでなければスキップ
  if Signature(e) <> 'NPC_' then begin
    AddMessage(GetElementEditValues(e, 'EDID') + ' is not NPC Record!');
    Exit;
  end;

  // Facegenファイルのフラグを初期化
  missingFacegeom := false;
  missingFacetint := false;

  // Mod名を取得（レコードが所属するファイル名）
  replacerFile := GetFileName(GetFile(e));
  baseFile := GetFileName(GetFile(MasterOrSelf(e)));
  
  // コピー元のEditor IDを取得
  oldEditorID := GetElementEditValues(e, 'EDID');

  // 新しいEditor IDを作成
  newEditorID := prefix + '_' + oldEditorID;

  // レコードを複製
  // TODO:ESLフラグ持ちの場合、FormIDが不正になる可能性があるのでチェック処理を追加（必要？）
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

  oldMeshPath := GetFaceGenPath(baseFile, oldformID, false, MeshMode);
//    AddMessage('oldMeshPath:' + oldMeshPath);
  newMeshPath := GetFaceGenPath(replacerFile, newformID, true, MeshMode);
//    AddMessage('newMeshPath:' + newMeshPath);
    
  oldTexturePath := GetFaceGenPath(baseFile, oldformID, false, TextureMode);
//    AddMessage('oldTexturePath:' + oldTexturePath);
  newTexturePath := GetFaceGenPath(replacerFile, newformID, true, TextureMode);
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
      // TODO:formIDからパディングされた0を取り除く
      trimedOldformID := IntToHex64(GetElementNativeValues(e, 'Record Header\FormID') and  $FFFFFF, 8);
      trimedNewformID := IntToHex64(GetElementNativeValues(newRecord, 'Record Header\FormID') and  $FFFFFF, 8);
      
      slBaseID := baseFile + '|' + trimedOldFormID;
      slReplacerID := replacerFile + '|' + trimedNewFormID;
    end
    else begin
      slBaseID := oldEditorID;
      slReplacerID := newEditorID;
    end;

    // NPCレコードのWNAMフィールドが設定されていたらWNAMのスキンを反映
    wnamID := IntToHex64(GetElementNativeValues(e, 'WNAM') and  $FFFFFF, 8);
//      AddMessage('wnamID is:' + wnamID);
    if wnamID = '00000000' then
      slSkinID := slReplacerID
    else
      slSkinID := replacerFile + '|' + wnamID;

    slExport.Add(';' + GetElementEditValues(e, 'FULL'));
    slExport.Add(addSemicolon + 'filterByNpcs=' + slBaseID + ':copyVisualStyle=' + slReplacerID + ':skin=' + slSkinID + #13#10);
  end else begin
    AddMessage('Facegen files copy was failed. Skip adding to this record line into Skypatcher ini file.');
    // テンプレートを利用しているNPCだった場合は正常処理なのでその旨を表示
    if not (GetElementEditValues(e, 'TPLT') = '') then
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
      dlgSave.FileName := replacerFile + '.ini';
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
