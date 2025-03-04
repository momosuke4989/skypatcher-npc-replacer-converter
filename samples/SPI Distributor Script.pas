{
  Export spells, perks, items, shouts and leveled items-spells for Spell Perk Item Distributor
}
unit ExportSPI;

var
  slExport: TStringList;
  kname: string;
  actor: string;
  filterid: string;
  minmax: string;
  gender: string;
  itemno: string;
  chance: string;
  
function Initialize: integer;
  begin
    slExport := TStringList.Create;
    InputQuery('Custom Keyword', 'KywdName', kname);
    InputQuery('Keyword Strings or Actorbase Names', 'String', actor);
    InputQuery('Filter FormIDs', 'FormID', filterid);
    InputQuery('Min/Max Actor and Skill Level', 'MinLevel/MaxLevel , Skill(Min/Max)', minmax);
    InputQuery('Gender', 'F or M', gender);
    InputQuery('Item Count', 'Number', itemno);
    InputQuery('Chance', '1-100', chance);
  end;

function Process(e: IInterface): integer;  
  const
    sRecordsToSkip = 'AACT,ACHR,ACTI,ADDN,ANIO,APPA,ARMA,ARTO,ASPC,ASTP,AVIF,BPTD,CAMS,CELL,CLAS,CLFM,CLMT,COBJ,COLL,CONT,CPTH,CSTY,DEBR,DIAL,DLBR,DLVW,DOBJ,DOOR,DUAL,ECZN,EFSH,ENCH,EQUP,EXPL,EYES,FACT,FLOR,FLST,FSTP,FSTS,FURN,GLOB,GMST,GRAS,GRUP,HAZD,HDPT,IDLE,IDLM,IMAD,IMGS,INFO,INGR,IPCT,IPDS,LAND,LCRT,LCTN,LGTM,LIGH,LSCR,LTEX,LVLN,MATO,MATT,MESG,MGEF,MOVT,MSTT,MUSC,MUST,NAVI,NAVM,NPC_,PGRE,PHZD,PROJ,QUST,RACE,REFR,REGN,RELA,REVB,RFCT,SCEN,SMBN,SMEN,SMQN,SNCT,SNDR,SOPM,SOUN,SPGD,STAT,TACT,TES4,TREE,TXST,VTYP,WATR,WOOP,WRLD,WTHR';
    sSpell = 'SPEL';
    sPerk = 'PERK';
    sShout = 'SHOU';
    sLeveleds = 'LVSP';
    sLeveledi = 'LVLI';    
    sItem = 'ALCH,AMMO,ARMO,BOOK,INGR,KEYM,MISC,SCRL,SLGM,WEAP';
    sOutfit = 'OTFT';
    sPackage = 'PACK';
    sKeyword = 'KYWD';
    
begin 
  if Pos(Signature(e), sRecordsToSkip) <> 0 then Exit;

  if actor = '' 	then actor := 'ActorTypeNPC';     	
  if filterid = ''	then filterid := 'NONE';        		
  if minmax = '' 	then minmax := 'NONE';       		
  if gender = '' 	then gender := 'NONE';        		
  if itemno = '' 	then itemno := '1';        			
  if chance = '' 	then chance := 'NONE';

//====================Custom Keyword==========================
  if kname <> '' then    
      begin
      slExport.Add(';Custom Keyword');  
      slExport.Add('Keyword = ' + kname
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax	//Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | NONE'			//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
      kname := '';
      end;
//============================================================
//========================Keyword=============================
  if Pos(Signature(e), sKeyword) <> 0 then
    begin
      slExport.Add(';' + EditorID(e));  
      slExport.Add('Keyword = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8)
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax	//Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | NONE'			//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end else
//============================================================
//=========================Spell==============================
  if Pos(Signature(e), sSpell) <> 0 then
    begin
      slExport.Add(';' + GetElementEditValues(e, 'FULL'));  
      slExport.Add('Spell = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8) + ' - '
        + GetFileName(MasterOrSelf(e))
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax    //Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | NONE'			//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end else
//============================================================
//==========================Perk==============================
  if Pos(Signature(e), sPerk) <> 0 then
    begin
      slExport.Add(';' + GetElementEditValues(e, 'FULL'));  
      slExport.Add('Perk = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8) + ' - '
        + GetFileName(MasterOrSelf(e))
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax	//Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | NONE'			//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end else
//============================================================
//==========================Shout=============================
  if Pos(Signature(e), sShout) <> 0 then
    begin
      slExport.Add(';' + GetElementEditValues(e, 'FULL'));  
      slExport.Add('Shout = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8) + ' - '
        + GetFileName(MasterOrSelf(e))
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax	//Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | NONE'			//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end else
//============================================================
//======================Leveled Spell==========================
  if Pos(Signature(e), sLeveleds) <> 0 then
    begin
      slExport.Add(';' + EditorID(e));  
      slExport.Add('LevSpell = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8) + ' - '
        + GetFileName(MasterOrSelf(e))
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax	//Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | NONE'			//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end else
//============================================================
//======================Leveled Item==========================
  if Pos(Signature(e), sLeveledi) <> 0 then
    begin
      slExport.Add(';' + EditorID(e));  
      slExport.Add('Item = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8) + ' - '
        + GetFileName(MasterOrSelf(e))
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax	//Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | ' + itemno	//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end else
//============================================================
//==========================Item==============================
  if Pos(Signature(e), sItem) <> 0 then
    begin
      slExport.Add(';' + GetElementEditValues(e, 'FULL'));  
      slExport.Add('Item = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8) + ' - '
        + GetFileName(MasterOrSelf(e))
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax	//Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | ' + itemno	//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end else
//============================================================
//=========================Outfit=============================
  if Pos(Signature(e), sOutfit) <> 0 then
    begin
      slExport.Add(';' + EditorID(e));  
      slExport.Add('Outfit = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8) + ' - '
        + GetFileName(MasterOrSelf(e))
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax	//Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | NONE'			//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end else
//============================================================
//=========================Package============================
  if Pos(Signature(e), sPackage) <> 0 then
    begin
      slExport.Add(';' + EditorID(e));  
      slExport.Add('Package = 0x'
        + IntToHex(FormID(e) and $FFFFFF, 8) + ' - '
        + GetFileName(MasterOrSelf(e))
        + ' | ' + actor		//String: keyword strings or actorbase names
        + ' | ' + filterid	//Filter formID: formIDs of factions/classes/combat styles/races
        + ' | ' + minmax    //Level: minimum/maximum level needed
        + ' | ' + gender	//Gender: M/F or 0/1
        + ' | NONE'			//Don't change this
        + ' | ' + chance	//Chance: % of it appearing, 1-100
      );
    end;
//============================================================

end;

function Finalize: integer;
var
  dlgSave: TSaveDialog;
  ExportFileName: string;
begin
  if slExport.Count <> 0 then 
  begin
  dlgSave := TSaveDialog.Create(nil);
    try
      dlgSave.Options := dlgSave.Options + [ofOverwritePrompt];
      dlgSave.Filter := 'Ini (*.ini)|*.ini';
      dlgSave.InitialDir := DataPath;
      dlgSave.FileName := 'Modname_DISTR.ini';
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