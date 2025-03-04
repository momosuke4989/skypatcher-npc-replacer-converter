{
  New script template, only shows processed records
  Assigning any nonzero value to Result will terminate script
}
unit userscript;

interface
implementation
uses xEditAPI, SysUtils, StrUtils, Windows;

function Initialize: integer;
var
  i: integer;
  e: IwbElement;
  f: IwbFile;
begin
  f := FileByIndex(2); // 最初のプラグインを取得（適宜変更）
  for i := 1 to 4095 do begin
    e := Add(f, 'NPC_', True);
    if Assigned(e) then begin
      SetElementEditValues(e, 'EDID', 'DummyNPC_' + IntToStr(i));
      AddMessage('Created NPC Record: DummyNPC_' + IntToStr(i));
    end;
  end;
  Result := 0;
end;

function Process(e: IInterface): integer;
begin
  Result := 0;

  if IsMaster(e) then
    AddMessage('Thes recoad is not overwriting.')
   else
    AddMessage('Thes recoad is overwriting.');

end;


function Finalize: integer;
begin
  Result := 0;
end;

end.