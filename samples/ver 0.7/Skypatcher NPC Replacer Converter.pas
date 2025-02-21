unit UserScript;

interface
implementation
uses xEditAPI, SysUtils, StrUtils, Windows;

var
  slExport: TStringList;
  prefix, addSemicolon: string;
  baseFile, replacerMod: string;
  isESL,useFormID: boolean;
  copyCount: Cardinal;

function Initialize: integer;
begin
  slExport       := TStringList.Create;
  Result         := 0;
  isESL          := false;
  baseFile       := '';
  replacerMod    := '';
  addSemicolon   := '';
  copyCount      := 0;

  // 出力ファイルに使うのはFormIDとEditorIDのどちらか確認
  if MessageDlg('Use FormID for output? (Yes: FormID, No: EditorID)', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    useFormID := true
  else
    useFormID := false;

  // 出力ファイルのデフォルト設定をすべて有効にするか確認
  if MessageDlg('Enable output ini file by default? (Yes: Enable, No: Disable)', mtConfirmation, [mbYes, mbNo], 0) = mrNo then
    addSemicolon := ';';

  // プレフィックスを入力
  prefix := InputBox('New Editor ID Prefix Input', 'Enter the prefix. ''_'' will be added:', '');
  AddMessage('Prefix set to: ' + prefix);

end;

function IsMasterSAEPlugin(plugin: IInterface): Boolean;
var
  PluginName  : String;
Begin
  PluginName := GetFileName(plugin);
  Result := (CompareStr(PluginName, 'Skyrim.esm') = 0) or (CompareStr(PluginName, 'Update.esm') = 0) or (CompareStr(PluginName, 'Dawnguard.esm') = 0) or (CompareStr(PluginName, 'HearthFires.esm') = 0) or (CompareStr(PluginName, 'Dragonborn.esm') = 0) or (CompareStr(PluginName, 'ccBGSSSE001-Fish.esm') = 0) or (CompareStr(PluginName, 'ccQDRSSE001-SurvivalMode.esl') = 0) or (CompareStr(PluginName, 'ccBGSSSE037-Curios.esl') = 0) or (CompareStr(PluginName, 'ccBGSSSE025-AdvDSGS.esm') = 0) or (CompareStr(PluginName, '_ResourcePack.esl') = 0);
End;

function GetFaceGenPath(pluginName, formID: string; MeshMode: boolean): string;
begin
  if MeshMode then
    Result := Format('%smeshes\actors\character\FaceGenData\FaceGeom\%s\%s.nif', [DataPath, pluginName, formID]);
  if not MeshMode then
    Result := Format('%stextures\actors\character\FaceGenData\FaceTint\%s\%s.dds', [DataPath, pluginName, formID]);
end;

function CopyFaceGenFile(oldPath, newPath: string; MeshMode: boolean): boolean;
var
  Result : boolean;
begin
  Result := false;
  // 元ファイルが存在するか確認
  if not FileExists(oldPath) then begin
    AddMessage('File not found: ' + oldPath);
    Exit;
  end;

  // 新しいフォルダがなければ作成
  if not DirectoryExists(ExtractFilePath(newPath)) then
    ForceDirectories(ExtractFilePath(newPath));

  // ファイルをコピー
  if CopyFile(PChar(oldPath), PChar(newPath), False) then begin
    AddMessage('Copied: ' + oldPath + ' -> ' + newPath);
    Result := true;
  end else
    AddMessage('Failed to copy: ' + oldPath);

end;

function Process(e: IInterface): integer;
const
  meshMode = true;
  textureMode = false;
var
  ESLCheck: IInterface;
  newRecord: IInterface;
  oldformID, newformID, trimedOldformID, trimedNewformID: String; 
  trimDigits:   Cardinal;
  oldEditorID, newEditorID, slBaseID, slReplacerID: string;
  oldMeshPath, oldTexturePath, newMeshPath, newTexturePath: string;
begin
  //  マスターファイルを編集しようとしていたらスキップ
  if IsMasterSAEPlugin(e) then begin
    AddMessage(GetElementEditValues(e, 'EDID') + ' is a member of ' + GetFileName(e) + '! Do not Edit it!');
    Exit;
  end;

  // TODO:複数のプラグインを選択していたらスキップ

  // TODO:レコード数上限に達していたらスキップ

  // NPCレコードでなければスキップ
  if Signature(e) <> 'NPC_' then begin
    AddMessage(GetElementEditValues(e, 'EDID') + ' is not NPC Record!');
    Exit;
  end;

  // TODO:元レコードがマスターファイルではない場合ユーザに確認

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

  // Mod名を取得（レコードが所属するファイル名）
  replacerMod := GetFileName(GetFile(e));
  baseFile := GetFileName(GetFile(MasterOrSelf(e)));
  
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

  // レコードのコピー回数をカウント
//  Inc(copyCount);
  //  AddMessage('copyCount: ' + IntToStr(copyCount));

  // 新しいEditor IDを設定
  SetElementEditValues(newRecord, 'EDID', newEditorID);
  //AddMessage('Created new record with Editor ID: ' + newEditorID);

  // formID,顔ファイルのパスを取得
  oldformID := IntToHex64(GetElementNativeValues(e, 'Record Header\FormID') and  $FFFFFF, 8);
  newformID := IntToHex64(GetElementNativeValues(newRecord, 'Record Header\FormID') and  $FFFFFF, 8);

  oldMeshPath := GetFaceGenPath(baseFile, oldformID, meshMode);
//    AddMessage('oldMeshPath:' + oldMeshPath);
  newMeshPath := GetFaceGenPath(replacerMod, newformID, meshMode);
//    AddMessage('newMeshPath:' + newMeshPath);
    
  oldTexturePath := GetFaceGenPath(baseFile, oldformID, textureMode);
//    AddMessage('oldTexturePath:' + oldTexturePath);
  newTexturePath := GetFaceGenPath(replacerMod, newformID, textureMode);
//    AddMessage('newTexturePath:' + newTexturePath);

  // 顔ファイルを新しいパスにコピー&リネーム
  if not CopyFaceGenFile(oldMeshPath, newMeshPath, meshMode) then
    AddMessage('failed copy FaceGeom file');

  if not CopyFaceGenFile(oldTexturePath, newTexturePath, textureMode) then
    AddMessage('failed copy FaceTint file');

  // 出力ファイル用の配列操作
  if useFormID then begin
    // TODO;formIDからパディングされた0を取り除く
    trimedOldformID := IntToHex64(GetElementNativeValues(e, 'Record Header\FormID') and  $FFFFFF, 8);
    trimedNewformID := IntToHex64(GetElementNativeValues(newRecord, 'Record Header\FormID') and  $FFFFFF, 8);
    
    slBaseID := baseFile + '|' + trimedOldFormID;
    slReplacerID := replacerMod + '|' + trimedNewFormID;
  end
  else begin
    slBaseID := oldEditorID;
    slReplacerID := newEditorID;
  end;
  
  slExport.Add(';' + GetElementEditValues(e, 'FULL'));
  slExport.Add(addSemicolon + 'filterByNpcs=' + slBaseID + ':copyVisualStyle=' + slReplacerID + ':skin=' + slReplacerID + #13#10);

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

  saveDir := DataPath + 'SKSE\Plugins\Skypatcher\npc\';
  if not DirectoryExists(saveDir) then
    ForceDirectories(saveDir);

  dlgSave := TSaveDialog.Create(nil);
    try
      dlgSave.Options := dlgSave.Options + [ofOverwritePrompt];
      dlgSave.Filter := 'Ini (*.ini)|*.ini';
      dlgSave.InitialDir := saveDir;
      dlgSave.FileName := replacerMod + '.ini';
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
