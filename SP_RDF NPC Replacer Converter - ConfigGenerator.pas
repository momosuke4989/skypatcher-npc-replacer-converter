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
   Version: 2.3.0
   Last Updated: [2026-05-03]

   Changelog:
     - Changed Force Replace XXX option behavior:
       When OFF: Do not output the setting line
       When ON: Output the setting line with comparison logic (same as before)
     - Added Outfit setting output option
  ==============================================================================
}

unit SP_RDF_NPCReplacerConverter_ConfigGenerator;

uses 'SP_RDF NPC Replacer Converter - PreProcessor';
uses 'NPC Replacer Converter - Shared\NPCRC_CommonUtils';

const
  USE_EDITOR_ID = false;

var
  // 設定ファイル出力用変数
  slExport, slCommentOut: TStringList;
  coChar, targetFileName, replacerFileName: string;

  // イニシャル処理で設定・使用する変数
  callPreProcessor, useSkyPatcher, useFormID, disableAll, replaceVS, replaceSkin: boolean;

  // Output setting フラグ - ONの場合のみ該当の設定行を出力する
  outputRace, outputGender, outputName, outputVoiceType, outputOutfit: boolean;

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
  opts, disableOpts: TStringList;
  checkBoxCaption: string;
  i: Integer;
begin
  slExport            := TStringList.Create;
  slCommentOut        := TStringList.Create;
  coChar              := '';

  callPreProcessor    := false;
  useSkyPatcher       := false;
  useFormID           := false;

  disableAll          := false;
  replaceVS           := false;
  replaceSkin         := false;

  // Output setting オプションのデフォルト値を設定
  outputRace          := false;
  outputGender        := false;
  outputName          := false;
  outputVoiceType     := false;
  outputOutfit        := false;
  opts                := TStringList.Create;
  disableOpts         := TStringList.Create;

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

  // SkyPatcherかRDFの利用に応じてコメントアウト文字を切り替え
  if useSkyPatcher then
    coChar := ';'
  else
    coChar := '#';

  //コメントアウト文字列リストの初期化
  slCommentOut.Values['CopyVS']    := '';
  slCommentOut.Values['Skin']      := '';
  slCommentOut.Values['Race']      := '';
  slCommentOut.Values['Gender']    := '';
  slCommentOut.Values['Name']      := '';
  slCommentOut.Values['VoiceType'] := '';
  slCommentOut.Values['Outfit']    := '';

  if useSkyPatcher then
    checkBoxCaption := 'Choose SkyPatcher Option'
  else
    checkBoxCaption := 'Choose RDF Option';

  if callPreProcessor then
    Result := RunPreProcInitialize;

  // 各オプションの設定
  try
    opts.Values['Use Form ID for config file output'] := 'False';
    opts.Values['Disable the config file by default'] := 'False';
    opts.Values['Replace Visual Style']               := 'False';
    opts.Values['Replace Skin']                       := 'False';
    opts.Values['Output Race setting']                := 'False';
    opts.Values['Output Gender setting']              := 'False';
    opts.Values['Output Name setting']                := 'False';
    opts.Values['Output VoiceType setting']           := 'False';
    opts.Values['Output Outfit setting']              := 'False';
    if useSkyPatcher then begin
      opts.Values['Replace Visual Style'] := 'True';
      opts.Values['Replace Skin']         := 'True';
    end
    else begin
      disableOpts.Add('Replace Visual Style');
      disableOpts.Add('Replace Skin');
      disableOpts.Add('Output Race setting');
      disableOpts.Add('Output Gender setting');
      disableOpts.Add('Output Name setting');
      disableOpts.Add('Output VoiceType setting');
      disableOpts.Add('Output Outfit setting');
    end;

    if ShowCheckboxForm(opts, disableOpts, checkBoxCaption) then
    begin
      AddMessage('You selected:');
      for i := 0 to opts.Count - 1 do
        AddMessage(opts.Names[i] + ' - ' + opts.ValueFromIndex[i]);
    end
    else begin
      AddMessage('Selection was canceled.');
      Result := -1;
      Exit;
    end;

    // 出力ファイルに使うのはFormIDとEditorIDのどちらか
    useFormID := GetBoolSLValue(opts.Values['Use Form ID for config file output']);

    // 出力ファイルの記述をすべてコメントアウトするか
    disableAll := GetBoolSLValue(opts.Values['Disable the config file by default']);

    // SkyPatcher利用時のオプション設定
    replaceVS       := GetBoolSLValue(opts.Values['Replace Visual Style']);    // 見た目を変更するか
    replaceSkin     := GetBoolSLValue(opts.Values['Replace Skin']);            // 肌を変更するか

    // 各設定行を出力するかどうか（ONの場合のみ出力）
    outputRace      := GetBoolSLValue(opts.Values['Output Race setting']);
    outputGender    := GetBoolSLValue(opts.Values['Output Gender setting']);
    outputName      := GetBoolSLValue(opts.Values['Output Name setting']);
    outputVoiceType := GetBoolSLValue(opts.Values['Output VoiceType setting']);
    outputOutfit    := GetBoolSLValue(opts.Values['Output Outfit setting']);
    // オプションの選択に応じて、設定行をコメントアウトする
    if disableAll then begin
      slCommentOut.Values['CopyVS']    := coChar;
      slCommentOut.Values['Skin']      := coChar;
      slCommentOut.Values['Race']      := coChar;
      slCommentOut.Values['Gender']    := coChar;
      slCommentOut.Values['Name']      := coChar;
      slCommentOut.Values['VoiceType'] := coChar;
      slCommentOut.Values['Outfit']    := coChar;
    end
    else begin
      if useSkyPatcher and not replaceVS then
        slCommentOut.Values['CopyVS'] := coChar;

      if not replaceSkin then
        slCommentOut.Values['Skin'] := coChar;

      // outputXXXがOFFの項目は、Processで比較判定を行わないため、
      // ここで初期化する必要はない（Processで出力自体がスキップされる）
    end;

  finally
    opts.Free;
    disableOpts.Free;
  end;
  AddMessage('Config Generator Initialize Finish!');
end;

function Process(e: IInterface): integer;

var
  replacerFlags, templateFlags, replacerRaceElement, replacerVoiceTypeElement, replacerOutfitElement, targetFlags, targetRaceElement, targetVoiceTypeElement, targetOutfitElement: IInterface;
  replacerRecord, targetRecord, replacerRaceRecord, replacerVoiceTypeRecord, replacerOutfitRecord, targetRaceRecord, targetVoiceTypeRecord, targetOutfitRecord: IwbMainRecord;
  replacerName, targetName: string;
  replacerFormID, underscorePos: Cardinal;
  originalTargetID, recordSignature, targetFormID, targetEditorID, replacerEditorID: string; // レコードID関連
  trimedTargetFormID, trimedReplacerFormID, exportTargetID, exportReplacerID, wnamID, exportSkinID, exportRace, exportGender, exportName, exportVoiceType, exportOutfit: string; // SkyPatcher iniファイルの記入用
  useTraits: boolean;
begin
  targetFormID    := '';
  targetEditorID  := '';

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
  AddMessage('Found record: ' + Name(targetRecord));
  targetFileName := GetFileName(targetRecord);
  AddMessage('Target file name set to: ' + targetFileName);

  // ターゲットNPCのFormID,EditorIDを取得
  targetFormID := IntToHex64(GetElementNativeValues(targetRecord, 'Record Header\FormID') and  $FFFFFF, 8);
    //AddMessage('Target Record Form ID: ' + targetFormID);
  targetEditorID := GetElementEditValues(targetRecord, 'EDID');
    //AddMessage('Target Record Editor ID: ' + targetEditorID);

  // リプレイサーNPCのフラグ、種族、名前、音声タイプを取得
  replacerFlags            := ElementByPath(replacerRecord, 'ACBS - Configuration');
  replacerRaceElement      := ElementByPath(replacerRecord, 'RNAM');
  replacerRaceRecord       := MasterOrSelf(LinksTo(replacerRaceElement));
  replacerName             := GetElementEditValues(replacerRecord, 'FULL');
  replacerVoiceTypeElement := ElementByPath(replacerRecord, 'VTCK');
  replacerVoiceTypeRecord  := MasterOrSelf(LinksTo(replacerVoiceTypeElement));
  replacerOutfitElement    := ElementByPath(replacerRecord, 'DOFT');
  replacerOutfitRecord     := MasterOrSelf(LinksTo(replacerOutfitElement));

  // レコードがuse traitsフラグを持っているか確認し、持っていた場合はスキップ
  templateFlags := ElementByPath(replacerFlags, 'Template Flags');
  useTraits := GetElementNativeValues(templateFlags, 'Use Traits') <> 0;

  if useTraits then begin
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    AddMessage('This NPC Record has Use Traits Template Flag. Config generation will be skipped.');
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    Exit;
  end;

  // ターゲットNPCのフラグ、種族、名前、音声タイプを取得
  targetFlags            := ElementByPath(targetRecord, 'ACBS - Configuration');
  targetRaceElement      := ElementByPath(targetRecord, 'RNAM');
  targetRaceRecord       := MasterOrSelf(LinksTo(targetRaceElement));
  targetName             := GetElementEditValues(targetRecord, 'FULL');
  targetVoiceTypeElement := ElementByPath(targetRecord, 'VTCK');
  targetVoiceTypeRecord  := MasterOrSelf(LinksTo(targetVoiceTypeElement));
  targetOutfitElement    := ElementByPath(targetRecord, 'DOFT');
  targetOutfitRecord     := MasterOrSelf(LinksTo(targetOutfitElement));

  // 各設定行の出力が有効かつdisableAllがOFFの場合のみ、比較判定を行う
  // disableAllがONの場合は、Initializeで既に全てコメントアウトに設定済みなので何もしない
  if not disableAll then begin
    // 出力が有効な項目のみコメントアウト判定を行う
    if outputRace then begin
      slCommentOut.Values['Race'] := '';
      // 種族が同じ場合はコメントアウト
      if GetElementNativeValues(replacerRaceRecord, 'Record Header\FormID') = GetElementNativeValues(targetRaceRecord, 'Record Header\FormID') then
        slCommentOut.Values['Race'] := coChar;
    end;

    if outputGender then begin
      slCommentOut.Values['Gender'] := '';
      // 性別が同じ場合はコメントアウト
      if GetElementEditValues(targetFlags, 'Flags\Female') = GetElementEditValues(replacerFlags, 'Flags\Female') then
        slCommentOut.Values['Gender'] := coChar;
    end;

    if outputName then begin
      slCommentOut.Values['Name'] := '';
      // 名前が同じ場合はコメントアウト
      if replacerName = targetName then
        slCommentOut.Values['Name'] := coChar;
    end;

    if outputVoiceType then begin
      slCommentOut.Values['VoiceType'] := '';
      // 音声タイプが同じ場合はコメントアウト
      if GetElementNativeValues(replacerVoiceTypeRecord, 'Record Header\FormID') = GetElementNativeValues(targetVoiceTypeRecord, 'Record Header\FormID') then
        slCommentOut.Values['VoiceType'] := coChar;
    end;

    if outputOutfit then begin
      slCommentOut.Values['Outfit'] := '';
      // 出力が同じ場合はコメントアウト
      if GetElementNativeValues(replacerOutfitRecord, 'Record Header\FormID') = GetElementNativeValues(targetOutfitRecord, 'Record Header\FormID') then
        slCommentOut.Values['Outfit'] := coChar;
    end;
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
      exportTargetID := targetFileName + '|' + trimedTargetFormID;
      exportReplacerID := replacerFileName + '|' + trimedReplacerFormID;
    end
    else begin
      exportTargetID := trimedTargetFormID + '~' + targetFileName;
      exportReplacerID := trimedReplacerFormID + '~' + replacerFileName;
    end;

    exportRace  := GetFileName(replacerRaceRecord) + '|' + IntToHex(FormID(replacerRaceRecord) and  $FFFFFF, 1);
    exportVoiceType := GetFileName(replacerVoiceTypeRecord) + '|' + IntToHex(FormID(replacerVoiceTypeRecord) and  $FFFFFF, 1);
    exportOutfit := GetFileName(replacerOutfitRecord) + '|' + IntToHex(FormID(replacerOutfitRecord) and  $FFFFFF, 1);
  end
  else begin
    exportTargetID := targetEditorID;
    exportReplacerID := replacerEditorID;
    exportRace  := EditorID(replacerRaceRecord);
    exportVoiceType := EditorID(replacerVoiceTypeRecord);
    exportOutfit := EditorID(replacerOutfitRecord);
  end;

  // NPCレコードのWNAMフィールドが設定されていたらWNAMのスキンを反映。
  // 設定されていない場合はnullでデフォルトボディを指定。
  wnamID := IntToHex(GetElementNativeValues(replacerRecord, 'WNAM') and  $FFFFFF, 1);
  //  AddMessage('wnamID is:' + wnamID);
  if wnamID = '0' then
    exportSkinID := 'null'
  else
    exportSkinID := replacerFileName + '|' + wnamID;

  // 性別フラグを反映する文字列を入力
  if GetElementEditValues(replacerFlags, 'Flags\Female') = 1 then
    exportGender := ':setFlags=female'
  else
    exportGender := ':removeFlags=female';

  // 名前を入力
  exportName := replacerName;

  slExport.Add(coChar + GetElementEditValues(targetRecord, 'FULL'));
  slExport.Add(slCommentOut.Values['CopyVS'] + GenerateVisualStyleString(exportTargetID, exportReplacerID, useSkyPatcher));

  // SkyPatcher利用時のみ出力する
  if useSkyPatcher then begin
    slExport.Add(slCommentOut.Values['Skin'] + 'filterByNpcs=' + exportTargetID + ':skin=' + exportSkinID);

    // 各設定行は対応するoutputフラグがONの場合のみ出力
    if outputRace then
      slExport.Add(slCommentOut.Values['Race'] + 'filterByNpcs=' + exportTargetID + ':race=' + exportRace);

    if outputGender then
      slExport.Add(slCommentOut.Values['Gender'] + 'filterByNpcs=' + exportTargetID + exportGender);

    if outputName then
      slExport.Add(slCommentOut.Values['Name'] + 'filterByNpcs=' + exportTargetID + ':fullName=~' + exportName + '~');

    if outputVoiceType then
      slExport.Add(slCommentOut.Values['VoiceType'] + 'filterByNpcs=' + exportTargetID + ':voiceType=' + exportVoiceType);

    if outputOutfit then
      slExport.Add(slCommentOut.Values['Outfit'] + 'filterByNpcs=' + exportTargetID + ':outfitDefault=' + exportOutfit);
  end;

  slExport.Add(#13#10);
end;

function Finalize: integer;
var
  dlgSave: TSaveDialog;
  ExportFileName, saveDir, filterString, fileExtension: string;
  existingContent: TStringList;
  userChoice: Integer;
  savedFile:  boolean;
begin
  savedFile := false;

  if callPreProcessor then
    RunPreProcFinalize;

  // データがない場合はスキップ
  if slExport.Count = 0 then begin
    slExport.Free;
    Exit;
  end;

  // 出力設定の決定
  if useSkyPatcher then begin
    saveDir := DataPath + 'SkyPatcher RDF NPC Replacer Converter\SKSE\Plugins\SkyPatcher\npc\SkyPatcher NPC Replacer Converter\';
    filterString := 'Ini (*.ini)|*.ini';
    fileExtension := '.ini';
  end
  else begin
    saveDir := DataPath + 'SkyPatcher RDF NPC Replacer Converter\SKSE\Plugins\RaceSwap\';
    filterString := 'Txt (*.txt)|*.txt';
    fileExtension := '.txt';
  end;

  // ディレクトリ作成
  if not DirectoryExists(saveDir) then
    ForceDirectories(saveDir);

  // ファイル保存
  dlgSave := TSaveDialog.Create(nil);
  try
    dlgSave.Options := dlgSave.Options - [ofOverwritePrompt];
    dlgSave.Filter := filterString;
    dlgSave.InitialDir := saveDir;
    dlgSave.FileName := replacerFileName + fileExtension;
    repeat
      savedFile := false;

      if not dlgSave.Execute then begin
        // ダイアログを閉じたらループ終了
        AddMessage('Save cancelled by user');
        break;
      end
      else begin
        ExportFileName := dlgSave.FileName;

        // ファイルが既に存在するかチェック
        if FileExists(ExportFileName) then begin
          // ユーザーに選択させる
          userChoice := MessageDlg(
            'File already exists: ' + ExtractFileName(ExportFileName) + #13#10 +
            #13#10 +
            'What do you want to do?' + #13#10 +
            #13#10 +
            'Yes: Append to existing file' + #13#10 +
            'No: Overwrite the file' + #13#10 +
            'Cancel: Do not save',
            mtConfirmation,
            [mbYes, mbNo, mbCancel],
            0
          );

          case userChoice of
            mrYes: begin
              // 追記モード
              AddMessage('Appending to ' + ExportFileName);
              existingContent := TStringList.Create;
              try
                existingContent.LoadFromFile(ExportFileName);
                existingContent.AddStrings(slExport);
                existingContent.SaveToFile(ExportFileName);
                AddMessage('Content appended successfully');
              finally
                existingContent.Free;
              end;
              savedFile := true;  // ループを抜ける
            end;

            mrNo: begin
              // 上書きモード
              AddMessage('Overwriting ' + ExportFileName);
              slExport.SaveToFile(ExportFileName);
              AddMessage('File overwritten successfully');
              savedFile := true;  // ループを抜ける
            end;

            mrCancel: begin
              // キャンセル
              AddMessage('Save cancelled');
              savedFile := false;  // ループの開始に戻る
            end;
          end;
        end
        else begin
          // ファイルが存在しない場合は通常通り保存
          AddMessage('Saving ' + ExportFileName);
          slExport.SaveToFile(ExportFileName);
          AddMessage('File saved successfully');
          savedFile := true;  // ループを抜ける
        end;
      end;
    until savedFile;
  finally
    dlgSave.Free;
    slExport.Free;
    slCommentOut.Free;
  end;
end;

end.
