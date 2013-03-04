unit pLuaUtils;

{$mode objfpc}{$H+}

interface
uses Classes, SysUtils,
     Lua, pLua;

//fs namespace support
procedure plua_fs_register(L:Plua_State);

implementation

const
  Package_fs = 'fs';

procedure FindFilesToList(const Dir, WildCard:string; Recursive:boolean; L:TStrings);
var AllMask:string;

procedure ProcessDir(const Dir:string);
var SR:TSearchRec;
    Found:Integer;
begin
  //first pass - directories
  if Recursive then
    begin
      Found:=FindFirst(Dir + DirectorySeparator + AllMask, faDirectory, SR);
      try
        while Found = 0 do
        with SR do
        begin
          if (Name <> '.') and (Name <> '..') then
            if Attr and faDirectory > 0 then
              begin
                if Recursive then
                   ProcessDir(Dir + DirectorySeparator + Name);
              end;
          Found:=FindNext(SR);
        end;
      finally
        FindClose(SR);
      end;
    end;

  //second pass - files
  Found:=FindFirst(Dir + DirectorySeparator + WildCard, faAnyFile, SR);
  try
    while Found = 0 do
    with SR do
    begin
      if (Name <> '.') and (Name <> '..') then
         begin
           if Attr and faDirectory = 0 then
             begin
               L.Add(Dir + DirectorySeparator + Name);
             end;
         end;

      Found:=FindNext(SR);
    end;
  finally
    FindClose(SR);
  end;
end;

begin
  L.Clear;
  AllMask:={$IFDEF WINDOWS}'*.*'{$ELSE}'*'{$ENDIF};
  ProcessDir(Dir);
end;

function plua_findfiles(l : PLua_State; paramcount: Integer) : integer;
var S:TStringList;
    Recursive:boolean;
    Dir, Mask:string;
begin
  Result:=0;
  if not (paramcount in [2,3]) then
     lua_reporterror(l, 'Dir, Recursive, [Mask] are expected.');

  S:=TStringList.Create;
  try
    if paramcount = 3 then
       begin
         Mask:=plua_tostring(l, -1);
         lua_pop(l, 1);
       end;
    Recursive:=lua_toboolean(l, -1);
    lua_pop(l, 1);

    Dir:=plua_tostring(l, -1);
    lua_pop(l, 1);

    FindFilesToList(Dir, Mask, Recursive, S);

    plua_pushstrings(l, S);
    Result:=1;
  finally
    S.Free;
  end;
end;

function plua_iterfiles(l : PLua_State; paramcount: Integer) : integer;
begin

end;

procedure plua_fs_register(L: Plua_State);
begin
  plua_RegisterMethod(l, Package_fs, 'findfiles', @plua_findfiles);
  plua_RegisterMethod(l, Package_fs, 'iterfiles', @plua_iterfiles);
end;

end.

