{
  Automatically convert follower plugins to ESPFE.
  Author: MaskedRPGFan https://www.nexusmods.com/users/22822094 maskedrpgfan@gmail.com
  Version: 1.7.1
  Hotkey: Ctrl+Alt+F
}
unit __ESPFEFollower;

interface
implementation
uses xEditAPI, SysUtils, StrUtils, Windows;

const
    iESLMaxRecords      = $fff; // max possible new records in ESL
    iESLMaxFormID       = $fff; // max allowed FormID number in ESL
	iCheckVersion       = 1.7;
    CellFreeVersion     = False;
    QuickCheck          = True;
var
    Verbose             : boolean;
	DeleteReplaced      : boolean;
    NewRecordsNumber    : int;
	ReferencedRecords   : Integer;
	OverridedRecords    : Integer;

// 0 - OK
// 1 - OK, but must compact FormIDs
// 2 - CELL
// 3 - Too many new records
function TestRecords(plugin: IInterface): Integer;
var
    i                           : Integer;
    e                           : IInterface;
    RecCount, RecMaxFormID, fid : Cardinal;
    HasCELL                     : Boolean;
    SkipPlugin                  : Boolean;
Begin
    Result := 0;
    SkipPlugin := False;
    // iterate over all records in plugin
    for i := 0 to Pred(RecordCount(plugin)) do Begin
        e := RecordByIndex(plugin, i);
        
        // override doesn't affect ESL
        If not IsMaster(e) Then
            Continue;
        // Injected records are also not counted for ESL
        If IsInjected(e) Then
            Continue;

        If (Signature(e) = 'CELL') and (not CellFreeVersion) Then Begin
            Result := 2;
            Exit;
        End;
            
        // increase the number of new records found
        Inc(RecCount);
        
        // no need to check for more If we are already above the limit
        If RecCount > iESLMaxRecords Then Begin
            SkipPlugin := True;
        End;

        If SkipPlugin and QuickCheck Then
            break;
            
        // get raw FormID number
        fid := FormID(e) and $FFFFFF;
        
        // determine the max one
        If fid > RecMaxFormID Then
            RecMaxFormID := fid;
    End;

    If SkipPlugin Then Begin
        If QuickCheck Then
            AddMessage('Found at least ' + IntToStr(RecCount+1) + ' new records in ' + GetFileName(plugin) + '. Too many new records, can''t be turned into ESL!');
        If not QuickCheck Then
            AddMessage('Found ' + IntToStr(RecCount+1) + ' new records in ' + GetFileName(plugin) + '. Too many new records, can''t be turned into ESL!');
        Result := 3; // too many new records, can't be ESL
        Exit;
    End;

    AddMessage('Found ' + IntToStr(RecCount) + ' new records in ' + GetFileName(plugin) + '. Can be turned into ESP-FE!');
    NewRecordsNumber := RecCount;

    If RecMaxFormID <= iESLMaxFormID Then
        Exit;            // AddMessage(#9'Can be turned into ESL by adding ESL flag in TES4 header')

    Result := 1;     // AddMessage(#9'Can be turned into ESL by compacting FormIDs first, Then adding ESL flag in TES4 header');
End;



// 0  - OK
// 1  - OK, but must compact FormIDs
// 2  - CELL
// 3  - Too many new records
function TestPlugin(plugin: IInterface): Integer;
Begin
    If (GetElementNativeValues(ElementByIndex(plugin, 0), 'Record Header\Record Flags\ESL') = 0) and not SameText(ExtractFileExt(GetFileName(plugin)), '.esl') Then Begin
        Result := TestRecords(plugin);
    End;
End;

function IsMasterSSEPlugin(plugin: IInterface): Boolean;
var
	PluginName		: String;
Begin
	PluginName := GetFileName(plugin);
	Result := (CompareStr(PluginName, 'Skyrim.esm') = 0) or (CompareStr(PluginName, 'Update.esm') = 0) or (CompareStr(PluginName, 'Dawnguard.esm') = 0) or (CompareStr(PluginName, 'HearthFires.esm') = 0) or (CompareStr(PluginName, 'Dragonborn.esm') = 0);
End;

procedure CreateFaceMesh(MeshOldPath, MeshNewPath, OldFormID, NewFormID : string);
var
    Nif              : TwbNifFile;
    Block            : TwbNifBlock;
    el               : TdfElement;
    Elements         : TList;
    i, j, k          : Integer;
    s, s2            : WideString;
    bChanged         : Boolean;
Begin
    Nif := TwbNifFile.Create;
    Nif.LoadFromFile(MeshOldPath);
    
    Elements := TList.Create;
    
    If Verbose Then AddMessage(Format('Processed face %s --> %s. FormID %s --> %s.', [MeshOldPath, MeshNewPath, OldFormID, NewFormID]));
    
    // Iterate over all blocks in a nif file and locate elements holding textures.
    for i := 0 to Pred(Nif.BlocksCount) do Begin
        Block := Nif.Blocks[i];
        
        If Block.BlockType = 'BSShaderTextureSet' Then Begin
            el := Block.Elements['Textures'];
            for j := 0 to Pred(el.Count) do
                Elements.Add(el[j]);
        End; 
    End;
    
    AddMessage(Format('Found %d elements.', [Elements.Count]));

    // Skip to the next file If nothing was found.
    If Elements.Count = 0 Then Exit;
    
    // Do text replacement in collected elements.
    for k := 0 to Pred(Elements.Count) do Begin
        If not Assigned(Elements[k]) Then Continue
        el := TdfElement(Elements[k]);
        
        // Getting file name stored in element.
        s := el.EditValue;
        // Skip to the next element If empty.
        If s = '' Then Continue;
        
        // Perform replacements, trim whitespaces just in case.
        s2 := Trim(s);
        s2 := StringReplace(s2, OldFormID, NewFormID, [rfIgnoreCase, rfReplaceAll]);
        
        // If element's value has changed.
        If s <> s2 Then Begin
            // Store it.
            el.EditValue := s2;
            
            // Report.
            If Verbose Then AddMessage(#13#10 + MeshOldPath);
            If Verbose Then AddMessage(#9 + el.Path + #13#10#9#9'"' + s + '"'#13#10#9#9'"' + el.EditValue + '"');
        End;
        

		// Create the same folders structure as the source file in the destination folder.
		s := ExtractFilePath(MeshNewPath);
		If not DirectoryExists(s) Then
			If not ForceDirectories(s) Then
				raise Exception.Create('Can not create destination directory ' + s);
	
		// Get the root of the last processed element (the file element itself) and save.
		el.Root.SaveToFile(MeshNewPath);
		If Verbose Then AddMessage(Format('Processed face %s.', [MeshNewPath]));
    End;
    
    // Clear mark and elements list.
    bChanged := False;
    Elements.Clear;    
    Elements.Free;
    Nif.Free;    
End;


function GenerateFacePath(BasePath: string; FormID: Cardinal; TextureMode: bool): string;
Begin
    If TextureMode Then
        Result := Format('%s%s.dds', [BasePath, IntToHex64(FormID and $FFFFFF, 8)]);
    If not TextureMode Then
        Result := Format('%s%s.nif', [BasePath, IntToHex64(FormID and $FFFFFF, 8)]);
End;

procedure SetDes(plugin: IInterface);
var
	des 			: String;
Begin

	If( not ElementExists(ElementByIndex(plugin, 0), 'SNAM - Description')) Then Begin
		Add(ElementByIndex(plugin, 0), 'SNAM', true);
	End;
	des := GetElementNativeValues(ElementByIndex(plugin, 0), 'SNAM - Description') + ' ESPFE+';
	SetElementNativeValues(ElementByIndex(plugin, 0), 'SNAM - Description', des);
End;

function CompactFollowerPluginToESL(plugin: IInterface): Integer;
var
    i, j            : Integer;
    CurrentRecord   : IInterface;
    m, t            : IInterface;
    NewFormID       : Cardinal;
    NewFormID2      : Cardinal;
    OldFormID       : Cardinal;
    LoadOrder       : Cardinal;
    FaceMeshPath    : string;
    FaceTexturePath : string;
    VoicePath       : string;
    TextureOldPath  : string;
    TextureNewPath  : string;
    MeshOldPath     : string;
    MeshNewPath     : string;
    CopyResult      : bool;
    OldInfoFormIDs  : TStringList; 
    NewInfoFormIDs  : TStringList;
    TDirectory      : TDirectory;
    Files           : TWideStringDynArray;
    FilesWav        : TWideStringDynArray;
    FilesLip        : TWideStringDynArray;
    FilesXwm        : TWideStringDynArray;
    f, f2           : WideString;
    exists          : boolean;
	ConvertedVoices : Integer;
	ConvertedFaces  : Integer;
	MissingFaces    : Integer;
	NotConvertedVoices : Integer;
	NotConvertedFaces  : Integer;
	DeletedFiles : Integer;
    FatherPlugin :   IwbMainRecord;
Begin
    Result            := 0;
    NewFormID         := StrToInt64('$' + IntToHex64(1, 6));
    FaceMeshPath      := Format('%smeshes\Actors\Character\FaceGenData\FaceGeom\%s\', [DataPath, GetFileName(plugin)]);
    FaceTexturePath   := Format('%stextures\Actors\Character\FaceGenData\FaceTint\%s\', [DataPath, GetFileName(plugin)]);
    VoicePath         := Format('%ssound\voice\%s\', [DataPath, GetFileName(plugin)]);
    If DirectoryExists(VoicePath) Then Begin
        Files             := TDirectory.GetFiles(VoicePath, '*.fuz*', soAllDirectories);
        FilesWav          := TDirectory.GetFiles(VoicePath, '*.wav*', soAllDirectories);
        FilesLip          := TDirectory.GetFiles(VoicePath, '*.lip*', soAllDirectories);
        FilesXwm          := TDirectory.GetFiles(VoicePath, '*.xwm*', soAllDirectories);
	End;
    OldInfoFormIDs     := TStringList.Create;
    NewInfoFormIDs     := TStringList.Create;
	
	ConvertedVoices := 0;
	ConvertedFaces  := 0;
	MissingFaces	:= 0;
	NotConvertedVoices := 0;
	NotConvertedFaces  := 0;
	DeletedFiles := 0;
    
	LoadOrder			:= StrToInt64('$' + IntToHex64(GetLoadOrder(plugin), 2) + '000000');
    exists := true;
    while exists do Begin
		NewFormID2 := NewFormID or LoadOrder;
        t := RecordByFormID(plugin, NewFormID2, true);
        // This FormID already exists.
        If Assigned(t) Then Begin
            If Verbose Then AddMessage(Format('Record [%s][%s] %d exists.', [IntToHex64(NewFormID, 8), Name(t), Length(Name(t))]));
            // increment formid
            Inc(NewFormID);
        End;
        If not Assigned(t) Then exists := false;
    End;
    
    AddMessage('Plugin ' + GetFileName(plugin) + ' will be processed.');
    
    // Iterate over all records in plugin.
    for i := 0 to Pred(RecordCount(plugin)) do Begin
        CurrentRecord     := RecordByIndex(plugin, i);
        OldFormID         := GetLoadOrderFormID(CurrentRecord);
		NewFormID2        := ((OldFormID and $FF000000) or NewFormID);
        
        // Is in valid range, get next record.
        If (FormID(CurrentRecord) and $FFFFFF) <= iESLMaxFormID Then Begin
            If Verbose Then AddMessage(Format('Record [%s]%s is valid.', [IntToHex64(OldFormID, 8), Name(CurrentRecord)]));
			If Signature(CurrentRecord) = 'NPC_' Then Inc(NotConvertedFaces);
			If Signature(CurrentRecord) = 'INFO' Then Inc(NotConvertedVoices);
            continue;
        End;
        
        // Is identical.
        If (NewFormID and $FFFFFF) = (OldFormID and $FFFFFF) Then Begin
            Inc(NewFormID);
			NewFormID2        := ((OldFormID and $FF000000) or NewFormID);
            continue;
        End;

        // Injected records are also not counted for ESL
        If IsInjected(CurrentRecord) Then
            Continue;
        
        // The record in question might originate from master file.
        m := MasterOrSelf(CurrentRecord);
        // Skip overridden records.
        If not Equals(m, CurrentRecord) Then
            continue;
        
        If Verbose Then AddMessage(Format('[%3.0d] Changing FormID from [%s] to [%s] on %s', [i, IntToHex64(OldFormID, 8), IntToHex64(NewFormID2, 8), Name(CurrentRecord)]));
        
        If Signature(CurrentRecord) = 'NPC_' Then Begin
            TextureOldPath    := GenerateFacePath(FaceTexturePath, OldFormID, true);
            TextureNewPath    := GenerateFacePath(FaceTexturePath, NewFormID, true);
			If FileExists(TextureOldPath) Then
				CopyFile(TextureOldPath, TextureNewPath, CopyResult);
				If DeleteReplaced Then Begin
					DeleteFile(TextureOldPath);
					Inc(DeletedFiles);
					If Verbose Then AddMessage(Format('Deleted: %s', [TextureOldPath]));
				End
			Else
				AddMessage(Format('Face texture %s missing!', [TextureOldPath]));

            
            MeshOldPath    := GenerateFacePath(FaceMeshPath, OldFormID, false);
            MeshNewPath    := GenerateFacePath(FaceMeshPath, NewFormID, false);
			If FileExists(MeshOldPath) Then
			Begin
				CreateFaceMesh(MeshOldPath, MeshNewPath, IntToHex64(OldFormID and $FFFFFF, 8), IntToHex64(NewFormID and $FFFFFF, 8));
				If DeleteReplaced Then Begin
					DeleteFile(MeshOldPath);
					Inc(DeletedFiles);
					If Verbose Then AddMessage(Format('Deleted: %s', [MeshOldPath]));
				End;
				Inc(ConvertedFaces);
			End
			Else
			Begin
				AddMessage(Format('Face mesh %s missing!', [MeshOldPath]));
				Inc(MissingFaces);
			End;
        End;
        
        If Signature(CurrentRecord) = 'INFO' Then Begin
            OldInfoFormIDs.Add(IntToHex64(OldFormID and $FFFFFF, 6));
            NewInfoFormIDs.Add(IntToHex64(NewFormID and $FFFFFF, 6));
        End;
        
        // First change formid of references,
        UpdateAllRecordsAndRefs(CurrentRecord, OldFormID, NewFormID2);

        // Change formid of record.
        SetLoadOrderFormID(CurrentRecord, NewFormID2);

        exists := true;
        while exists do Begin
            // increment formid
            Inc(NewFormID);
			NewFormID2        := LoadOrder or NewFormID;
            t := RecordByFormID(plugin, NewFormID2, true);
            // This FormID already exists.
            If Assigned(t) Then
                If Verbose Then AddMessage(Format('Record [%s][%s] %d exists.', [IntToHex64(NewFormID2, 8), Name(t), Length(Name(t))]));
            If not Assigned(t) Then exists := false;
        End;
    End;

    SetElementNativeValues(ElementByIndex(plugin, 0), 'HEDR - Header\Next Object ID', NewFormID);
        
    // Processing voice files.
    for i := 0 to Pred(Length(Files)) do Begin
        f := Files[i];
        
        // Perform replacements.
        for j := 0 to Pred(OldInfoFormIDs.Count) do Begin
            // replace If text to find is not empty
            f2 := StringReplace(f, OldInfoFormIDs[j], NewInfoFormIDs[j], [rfIgnoreCase, rfReplaceAll]);
            If f <> f2 Then Begin 
                CopyFile(f, f2, CopyResult);
				If DeleteReplaced Then Begin
					DeleteFile(f);
					Inc(DeletedFiles);
					If Verbose Then AddMessage(Format('Deleted: %s', [f]));
				End;
                If Verbose Then AddMessage(Format('%s --> %s', [f, f2]));
				Inc(ConvertedVoices);
                break;
            End;
        End;
    End;
    for i := 0 to Pred(Length(FilesWav)) do Begin
        f := FilesWav[i];
        
        // Perform replacements.
        for j := 0 to Pred(OldInfoFormIDs.Count) do Begin
            // replace If text to find is not empty
            f2 := StringReplace(f, OldInfoFormIDs[j], NewInfoFormIDs[j], [rfIgnoreCase, rfReplaceAll]);
            If f <> f2 Then Begin 
                CopyFile(f, f2, CopyResult);
				If DeleteReplaced Then Begin
					DeleteFile(f);
					Inc(DeletedFiles);
					If Verbose Then AddMessage(Format('Deleted: %s', [f]));
				End;
                If Verbose Then AddMessage(Format('%s --> %s', [f, f2]));
				Inc(ConvertedVoices);
                break;
            End;
        End;
    End;
    for i := 0 to Pred(Length(FilesLip)) do Begin
        f := FilesLip[i];
        
        // Perform replacements.
        for j := 0 to Pred(OldInfoFormIDs.Count) do Begin
            // replace If text to find is not empty
            f2 := StringReplace(f, OldInfoFormIDs[j], NewInfoFormIDs[j], [rfIgnoreCase, rfReplaceAll]);
            If f <> f2 Then Begin 
                CopyFile(f, f2, CopyResult);
				If DeleteReplaced Then Begin
					DeleteFile(f);
					Inc(DeletedFiles);
					If Verbose Then AddMessage(Format('Deleted: %s', [f]));
				End;
                If Verbose Then AddMessage(Format('%s --> %s', [f, f2]));
				Inc(ConvertedVoices);
                break;
            End;
        End;
    End;
    for i := 0 to Pred(Length(FilesXwm)) do Begin
        f := FilesXwm[i];
        
        // Perform replacements.
        for j := 0 to Pred(OldInfoFormIDs.Count) do Begin
            // replace If text to find is not empty
            f2 := StringReplace(f, OldInfoFormIDs[j], NewInfoFormIDs[j], [rfIgnoreCase, rfReplaceAll]);
            If f <> f2 Then Begin 
                CopyFile(f, f2, CopyResult);
				If DeleteReplaced Then Begin
					DeleteFile(f);
					If Verbose Then AddMessage(Format('Deleted: %s', [f]));
				End;
                If Verbose Then AddMessage(Format('%s --> %s', [f, f2]));
				Inc(ConvertedVoices);
                break;
            End;
        End;
    End;
    AddMessage(Format('Converted FaceGenData: %d, not converted: %d, missing: %d.', [ConvertedFaces, NotConvertedFaces, MissingFaces]));
    AddMessage(Format('Converted voice files: %d, not converted: %d.', [ConvertedVoices, NotConvertedVoices]));
    AddMessage(Format('Deleted files: %d.', [DeletedFiles]));
End;

procedure UpdateAllRecordsAndRefs(CurrentRecord: IInterface; OldFormID: Cardinal; NewFormID: Cardinal);
var
    FatherPlugin: IInterface;
Begin
    AddMessage('        ' + 'Referenced by count: ' + IntToStr(ReferencedByCount(CurrentRecord)));
    ReferencedRecords:= ReferencedRecords + ReferencedByCount(CurrentRecord);
    while ReferencedByCount(CurrentRecord) > 0 do Begin
        AddMessage('        ' + Name(ReferencedByIndex(CurrentRecord, 0)) + ' -> ' + IntToHex64(NewFormID, 8));
        CompareExchangeFormID(ReferencedByIndex(CurrentRecord, 0), OldFormID, NewFormID);
    End;
    AddMessage('        ' + 'Override by count: ' + IntToStr(OverrideCount(CurrentRecord)));
    OverridedRecords:= OverridedRecords + OverrideCount(CurrentRecord);
    while OverrideCount(CurrentRecord) > 0 do Begin
        AddMessage('        ' + Name(OverrideByIndex(CurrentRecord, 0)) + ' -> ' + IntToHex64(NewFormID, 8));
        FatherPlugin := GetFile(OverrideByIndex(CurrentRecord, 0));
        If (GetElementNativeValues(ElementByIndex(FatherPlugin, 0), 'HEDR\Version') <= iCheckVersion) Then Begin
            AddMessage('        ' + 'Plugin ' + GetFileName(FatherPlugin) + ' has old format 1.70. Converting to 1.71 to have 4096 records in ESPFE plugin.');
            SetElementNativeValues(ElementByIndex(FatherPlugin, 0), 'HEDR\Version', 1.71);
        End;
        SetLoadOrderFormID(OverrideByIndex(CurrentRecord, 0), NewFormID);
    End;
End;

function Initialize: integer;
var
    Plugin: IInterface;
Begin
    ScriptProcessElements       := [etFile];
    Verbose                     := true;
	DeleteReplaced				:= true;
    ReferencedRecords           := 0;
    OverridedRecords            := 0;
End;

function Process(plugin: IInterface): integer;
var
    State:     Integer;
Begin
	AddMessage(wbAppName() + ': ' + IntToStr(wbVersionNumber()));
	
	// skip the game master
    If IsMasterSSEPlugin(plugin) Then Begin
        Result := -1;
		AddMessage('Do not try to convert Master Plugin: ' + GetFileName(plugin) + '!');
        Exit;
    End;
	
	If (GetElementNativeValues(ElementByIndex(plugin, 0), 'Record Header\Record Flags\ESL') == false) Then Begin
        AddMessage('Plugin ' + GetFileName(plugin) + ' has an ESL flag in the TES4 header. I assume it is already converted to ESPFE.');
        Exit;
	End;

    State := TestPlugin(plugin);

	If ((GetElementNativeValues(ElementByIndex(plugin, 0), 'HEDR\Version') <= iCheckVersion) and (State = 1)) Then Begin
        AddMessage('Plugin ' + GetFileName(plugin) + ' has old format 1.70. Converting to 1.71 to have 4096 records in ESPFE plugin.');
        SetElementNativeValues(ElementByIndex(plugin, 0), 'HEDR\Version', 1.71);
	End;

    If( State = 0 ) Then Begin
        SetElementNativeValues(ElementByIndex(plugin, 0), 'Record Header\Record Flags\ESL', 1);
		SetDes(plugin);
        AddMessage('Plugin ' + GetFileName(plugin) + ' was turned into ESPFE by adding ESL flag in TES4 header.');
        Exit;
    End;
    
    If( State = 1 ) Then Begin
        CompactFollowerPluginToESL(plugin);
        SetElementNativeValues(ElementByIndex(plugin, 0), 'Record Header\Record Flags\ESL', 1);
		SetDes(plugin);
        AddMessage('Plugin ' + GetFileName(plugin) + ' with ' + IntToStr(NewRecordsNumber) + ' new records was turned into ESPFE by compacting FormIDs and adding ESL flag in TES4 header.');
        AddMessage('Referenced records updated: ' + IntToStr(ReferencedRecords) + '. Overrided records updated: ' + IntToStr(OverridedRecords) + '.');
        Exit;
    End;
    
    If( (State = 2) and not CellFreeVersion) Then AddMessage('Plugin ' + GetFileName(plugin) + ' has CELL record and cant be processed due to Skyrim engine bug.');
    If( State = 3 ) Then AddMessage('Plugin ' + GetFileName(plugin) + ' has too many records.');
End;


function Finalize: integer;
Begin
  Result := 0;
End;

End.
