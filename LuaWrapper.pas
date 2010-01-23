unit LuaWrapper;

interface

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

{$DEFINE TLuaAsComponent}
{$DEFINE TLuaHandlersAsIsObjectType}

uses
  Classes,
  lua,
  pLua,
  pLuaObject;

type
  TLua = class;

  TObjArray = array of TObject;

  TLuaOnException = procedure( Title: ansistring; Line: Integer; Msg: ansistring;
                               var handled : Boolean) {$IFDEF TLuaHandlersAsIsObjectType}of object{$ENDIF};
  TLuaOnLoadLibs  = procedure( LuaWrapper : TLua ) {$IFDEF TLuaHandlersAsIsObjectType}of object{$ENDIF};
  
  { TLUA }
  TLUA=class{$IFDEF TLuaAsComponent}(TComponent){$ENDIF}
  private
    FOnException: TLuaOnException;
    FOnLoadLibs: TLuaOnLoadLibs;
    FUseDebug: Boolean;
    L : Plua_State;
    FScript,
    FLibFile,
    FLibName: AnsiString;
    FMethods : TStringList;
    function  GetLuaCPath: AnsiString;
    function  GetLuaPath: AnsiString;
    function  GetValue(valName : AnsiString): Variant;
    procedure SetLibName(const Value: AnsiString);
    procedure SetLuaCPath(const AValue: AnsiString);
    procedure SetLuaPath(const AValue: AnsiString);
    procedure OpenLibs;
    procedure SetOnException(const AValue: TLuaOnException);
    procedure SetOnLoadLibs(const AValue: TLuaOnLoadLibs);
    procedure SetUseDebug(const AValue: Boolean);
    procedure ErrorTest(errCode : Integer);
    procedure HandleException(E : LuaException);
    procedure SetValue(valName : AnsiString; const AValue: Variant);
    procedure ExecuteScript(NResults:integer);
  public
    constructor Create{$IFDEF TLuaAsComponent}(anOwner : TComponent); override;{$ENDIF}
    {$IFDEF TLuaAsComponent}constructor Create;{$ENDIF}
    destructor Destroy; override;

    procedure Close;
    procedure Open;

    //mark given object as being ready for garbage collection
    procedure ObjMarkFree(Obj:TObject);overload;
    procedure ObjMarkFree(const Obj:TObjArray);overload;

    procedure GarbageCollect;

    procedure LoadScript(const Script : AnsiString);
    procedure LoadFile(const FileName:AnsiString);

    //Loads function and saves it in lua state under given name.
    //It's purpose is to run it multiple times without reloading.
    procedure LoadFunctionFromFile(const FileName:string; const FunctionSaveAs:string);
    procedure LoadFunctionFromScript(const Script:string; const FunctionSaveAs:string);

    procedure Execute;

    function  ExecuteAsFunctionObj(const FunctionName:string):TObject;

    procedure ExecuteCmd(Script:AnsiString);
    procedure ExecuteFile(FileName : AnsiString);
    procedure RegisterLuaMethod(aMethodName: AnsiString; Func: lua_CFunction);
    procedure RegisterLuaTable(PropName: AnsiString; reader: lua_CFunction; writer : lua_CFunction = nil);
    function  FunctionExists(aMethodName:AnsiString) : Boolean;
    function  CallFunction( FunctionName :AnsiString; const Args: array of Variant;
                            Results : PVariantArray = nil):Integer;
    function  TableFunctionExists(TableName, FunctionName : AnsiString; out tblidx : Integer) : Boolean; overload;
    function  TableFunctionExists(TableName, FunctionName : AnsiString) : Boolean; overload;
    function  CallTableFunction( TableName, FunctionName :AnsiString;
                               const Args: array of Variant;
                               Results : PVariantArray = nil):Integer;

    procedure ObjArraySet(const varName:String; const A:TObjArray; C: PLuaClassInfo; FreeGC:boolean = False);
    function  ObjGet(const varName:string):TObject;

    procedure GlobalObjClear;
    procedure GlobalVarClear(const varName:string);

    property ScriptText: AnsiString read FScript write FScript;
    property ScriptFile: AnsiString read FLibFile write FLibFile;
    property LibName  : AnsiString read FLibName write SetLibName;
    property LuaState : Plua_State read L;
    property LuaPath  : AnsiString read GetLuaPath write SetLuaPath;
    property LuaCPath : AnsiString read GetLuaCPath write SetLuaCPath;
    property UseDebug : Boolean read FUseDebug write SetUseDebug;
    property Value[valName : AnsiString] : Variant read GetValue write SetValue; default;
    property OnException : TLuaOnException read FOnException write SetOnException;
    property OnLoadLibs : TLuaOnLoadLibs read FOnLoadLibs write SetOnLoadLibs;
  end;

  { TLUAThread }
  TLUAThread=class
  private
    FMaster : TLUA;
    FMethodName: AnsiString;
    FTableName: AnsiString;
    L : PLua_State;
    FThreadName : AnsiString;
    function GetIsValid: Boolean;
  public
    constructor Create(LUAInstance: TLUA; ThreadName : AnsiString);
    destructor Destroy; override;

    function Start(TableName : AnsiString; AMethodName : AnsiString; const ArgNames: array of AnsiString; var ErrorString : AnsiString) : Boolean;
    function Resume(EllapsedTime : lua_Number; Args : array of Variant; var ErrorString : AnsiString) : Boolean;

    property LuaState : Plua_State read L;
  published
    property IsValid : Boolean read GetIsValid;
    property ThreadName : AnsiString read FThreadName;
    property MethodName : AnsiString read FMethodName;
    property TableName  : AnsiString read FTableName;
  end;

  { TLUAThreadList }
  TLUAThreadList=class
  private
    FThreads : TList;
    FLUAInstance : TLUA;
    function GetCount: Integer;
    function GetThread(index: integer): TLUAThread;
  public
    constructor Create(LUAInstance: TLUA);
    destructor Destroy; override;

    procedure Process(EllapsedTime : lua_Number; Args : array of Variant; var ErrorString : AnsiString);

    function SpinUp(TableName, AMethodName, ThreadName : AnsiString; var ErrorString : AnsiString) : Boolean;
    function IndexOf(ThreadName : AnsiString): Integer;
    procedure Release(ThreadIndex : Integer);

    property Thread[index:integer]: TLUAThread read GetThread;
  published
    property Count : Integer read GetCount;
  end;

implementation

uses
  Variants,
  SysUtils,
  pLuaRecord;

constructor TLUA.Create{$IFDEF TLuaAsComponent}(anOwner: TComponent){$ENDIF};
begin
  {$IFDEF TLuaAsComponent}inherited;{$ENDIF}
  FUseDebug := false;
  FMethods := TStringList.Create;
  Open;
end;

{$IFDEF TLuaAsComponent}
constructor TLUA.Create;
begin
  Create(nil);
end;
{$ENDIF}

destructor TLUA.Destroy;
begin
  Close;
  FMethods.Free;
  inherited;
end;

procedure TLUA.ExecuteScript(NResults: integer);
begin
  if L = nil then
    Open;

  if (lua_gettop(l) <= 0) or
     (lua_type(L,-1) <> LUA_TFUNCTION) then
     raise Exception.Create('No script is loaded at stack');

  ErrorTest(lua_pcall(L, 0, NResults, 0));
end;

procedure TLUA.Execute;
begin
  ExecuteScript(0);
end;

function TLUA.ExecuteAsFunctionObj(const FunctionName:string): TObject;
var tix:Integer;
    StartTop:integer;
begin
  Result:=nil;
  StartTop:=lua_gettop(l);

  //load function with name FunctionName on stack
  lua_getglobal(l, PChar(FunctionName));

  ExecuteScript(LUA_MULTRET);
  tix:=lua_gettop(l);
  if tix > 0 then
    begin
      if lua_type(L,-1) = LUA_TUSERDATA then
        Result:=plua_getObject(l, tix)
        else
        lua_pop(l, 1);
    end;

  plua_CheckStackBalance(l, StartTop);
end;

procedure TLUA.ExecuteCmd(Script: AnsiString);
begin
  if L= nil then
    Open;
  ErrorTest(luaL_loadbuffer(L, PChar(Script), Length(Script), PChar(LibName)));
  ExecuteScript(0);
end;

procedure TLUA.ExecuteFile(FileName: AnsiString);
var
  Script : AnsiString;
  sl     : TStringList;
begin
  if L = nil then
    Open;

  ErrorTest(luaL_loadfile(L, PChar(FileName)));
  ExecuteScript(0);
end;

procedure TLUA.SetLuaPath(const AValue: AnsiString);
begin
  lua_pushstring(L, 'package');
  lua_gettable(L, LUA_GLOBALSINDEX);
  lua_pushstring(L, 'path');
  lua_pushstring(L, PChar(AValue));
  lua_settable(L, -3);
end;

procedure TLUA.LoadFile(const FileName: AnsiString);
var StartTop:integer;
begin
  if L = nil then
    Open;

  StartTop:=lua_gettop(l);

  FLibFile := FileName;
  FScript := '';
  ErrorTest( luaL_loadfile(L, PChar(FileName)) );

  plua_CheckStackBalance(l, StartTop+1);
end;

procedure TLUA.LoadFunctionFromFile(const FileName: string; const FunctionSaveAs:string);
var StartTop:integer;
begin
  StartTop:=lua_gettop(l);

  LoadFile(FileName);
  lua_setglobal(L, PChar(FunctionSaveAs));

  plua_CheckStackBalance(l, StartTop);
end;

procedure TLUA.LoadFunctionFromScript(const Script: string;
  const FunctionSaveAs: string);
var StartTop:integer;
begin
  StartTop:=lua_gettop(l);

  LoadScript(Script);
  lua_setglobal(L, PChar(FunctionSaveAs));

  plua_CheckStackBalance(l, StartTop);
end;

procedure TLUA.LoadScript(const Script: AnsiString);
var StartTop:integer;
begin
  if FScript <> Script then
    Close;

  if L = nil then
    Open;

  StartTop:=lua_gettop(l);

  FScript := Trim(Script);
  FLibFile := '';
  if FScript <> '' then
    luaL_loadbuffer(L, PChar(Script), length(Script), PChar(LibName));

  plua_CheckStackBalance(l, StartTop);
end;

function TLUA.FunctionExists(aMethodName: AnsiString): Boolean;
begin
  lua_pushstring(L, PChar(aMethodName));
  lua_rawget(L, LUA_GLOBALSINDEX);
  result := (not lua_isnil(L, -1)) and lua_isfunction(L, -1);
  lua_pop(L, 1);
end;

procedure TLUA.RegisterLUAMethod(aMethodName: AnsiString; Func: lua_CFunction);
begin
  if L = nil then
    Open;
  lua_register(L, PChar(aMethodName), Func);
  if FMethods.IndexOf(aMethodName) = -1 then
    FMethods.AddObject(aMethodName, TObject(@Func))
  else
    FMethods.Objects[FMethods.IndexOf(aMethodName)] := TObject(@Func);
end;

procedure TLUA.RegisterLuaTable(PropName: AnsiString; reader: lua_CFunction;
  writer: lua_CFunction);
begin
  plua_RegisterLuaTable(l, PropName, reader, writer);
end;

procedure TLUA.SetLibName(const Value: AnsiString);
begin
  FLibName := Value;
end;

procedure TLUA.SetLuaCPath(const AValue: AnsiString);
begin
  lua_pushstring(L, 'package');
  lua_gettable(L, LUA_GLOBALSINDEX);
  lua_pushstring(L, 'cpath');
  lua_pushstring(L, PChar(AValue));
  lua_settable(L, -3);
end;

function TLUA.GetLuaPath: AnsiString;
begin
  lua_pushstring(L, 'package');
  lua_gettable(L, LUA_GLOBALSINDEX);
  lua_pushstring(L, 'path');
  lua_rawget(L, -2);
  result := AnsiString(lua_tostring(L, -1));
end;

function TLUA.GetValue(valName : AnsiString): Variant;
var StartTop:Integer;
begin
  StartTop:=lua_gettop(l);

  result := NULL;
  lua_pushstring(l, PChar(valName));
  lua_rawget(l, LUA_GLOBALSINDEX);
  try
    result := plua_tovariant(l, -1);
  finally
    lua_pop(l, 1);
  end;

  plua_CheckStackBalance(l, StartTop);
end;

function TLUA.GetLuaCPath: AnsiString;
begin
  lua_pushstring(L, 'package');
  lua_gettable(L, LUA_GLOBALSINDEX);
  lua_pushstring(L, 'cpath');
  lua_rawget(L, -2);
  result := AnsiString(lua_tostring(L, -1));
end;

function TLUA.CallFunction(FunctionName: AnsiString;
  const Args: array of Variant; Results: PVariantArray = nil): Integer;
begin
  try
    if FunctionExists(FunctionName) then
      result := plua_callfunction(L, FunctionName, Args, Results)
    else
      result := -1;
  except
    on E:LuaException do
      HandleException(E);
  end;
end;

procedure TLUA.Close;
begin
  if L <> nil then
    begin
      plua_ClearObjects(L, True);
      plua_ClearRecords(L);
      lua_close(L);
    end;
  L := nil;

  FLibFile:='';
  FScript:='';
end;

procedure TLUA.Open;
begin
  if L <> nil then
    Close;
  L := lua_open;
  OpenLibs;
end;

procedure TLUA.ObjMarkFree(Obj: TObject);
begin
  if l <> nil then
    plua_ObjectMarkFree(l, Obj);
end;

procedure TLUA.ObjMarkFree(const Obj: TObjArray);
var n:integer;
begin
  if l <> nil then
    for n:=0 to High(Obj) do
      plua_ObjectMarkFree(l, Obj[n]);
end;

procedure TLUA.GarbageCollect;
begin
  if l <> nil then
    lua_gc(l, LUA_GCCOLLECT, 0);
end;

procedure TLUA.OpenLibs;
var
  I : Integer;
begin
  luaL_openlibs(L);
  if UseDebug then
    luaopen_debug(L);
  lua_settop(L, 0);

  for I := 0 to FMethods.Count -1 do
    RegisterLUAMethod(FMethods[I], lua_CFunction(Pointer(FMethods.Objects[I])));

  RecordTypesList.RegisterTo(L);
  ClassTypesList.RegisterTo(L);

  if assigned(FOnLoadLibs) then
    FOnLoadLibs(self);
end;

procedure TLUA.SetOnException(const AValue: TLuaOnException);
begin
  if FOnException=AValue then exit;
  FOnException:=AValue;
end;

procedure TLUA.SetOnLoadLibs(const AValue: TLuaOnLoadLibs);
begin
  if FOnLoadLibs=AValue then exit;
  FOnLoadLibs:=AValue;
  if (L <> nil) and (FOnLoadLibs <> nil) then
    FOnLoadLibs(self);
end;

procedure TLUA.SetUseDebug(const AValue: Boolean);
begin
  if FUseDebug=AValue then exit;
  FUseDebug:=AValue;
end;

procedure TLUA.ErrorTest(errCode: Integer);
var
  msg : AnsiString;
begin
  if errCode <> 0 then
    begin
      msg := plua_tostring(l, -1);
      lua_pop(l, 1);
      HandleException(LuaException.Create(msg));
    end;
end;

procedure TLUA.HandleException(E: LuaException);
var
  title, msg : AnsiString;
  line       : Integer;
  handled    : Boolean;
begin
  handled := false;
  if assigned(FOnException) then
    begin
      plua_spliterrormessage(e.Message, title, line, msg);
      FOnException(title, line, msg, handled);
    end;
  if not handled then
    raise E;
end;

procedure TLUA.SetValue(valName : AnsiString; const AValue: Variant);
var StartTop:Integer;
begin
  StartTop:=lua_gettop(l);

  if VarIsType(AValue, varString) then
    begin
      lua_pushliteral(l, PChar(valName));
      lua_pushstring(l, PChar(AnsiString(AValue)));
      lua_settable(L, LUA_GLOBALSINDEX);
    end
  else
    begin
      lua_pushliteral(l, PChar(valName));
      plua_pushvariant(l, AValue);
      lua_settable(L, LUA_GLOBALSINDEX);
    end;

  plua_CheckStackBalance(l, StartTop);
end;

function TLUA.CallTableFunction(TableName, FunctionName: AnsiString;
  const Args: array of Variant; Results: PVariantArray): Integer;
var
  tblidx : integer;
begin
  try
    if TableFunctionExists(TableName, FunctionName, tblidx) then
      begin
        lua_pushvalue(l, tblidx);
        tblidx := lua_gettop(l);
        result := plua_callfunction(l, FunctionName, args, results, tblidx)
      end
    else
      result := -1;
  except
    on E: LuaException do
      HandleException(E);
  end;
end;

procedure TLUA.ObjArraySet(const varName: String; const A: TObjArray; C: PLuaClassInfo; FreeGC:boolean);
var n, tix:integer;
    StartTop:integer;
begin
  StartTop:=lua_gettop(l);

  {
  //if global var already exists ...
  lua_getglobal(L, PChar(varName) );
  if not lua_isnil(L, -1) then
    begin
      // ... remove it
      lua_pushnil( L );
      lua_setglobal( L, PChar(varName) );
    end;
  lua_pop(L, -1); //balance stack
  }
  lua_newtable(L); // table
  for n:=0 to High(A) do
    begin
      lua_pushinteger(L, n+1); // table,key
      pLuaObject.plua_pushexisting(l, A[n], C, FreeGC);
      lua_settable(L,-3); // table
    end;
  lua_setglobal( L, PChar(varName) );

  plua_CheckStackBalance(l, StartTop);
end;

function TLUA.ObjGet(const varName: string): TObject;
var tblidx:integer;
begin
  Result:=nil;
  try
    lua_pushstring(L, PChar(varName));
    lua_rawget(L, LUA_GLOBALSINDEX);
    if lua_istable(L, -1) then
      begin
        tblidx:=lua_gettop(L);
        Result:=plua_getObject(l, tblidx);
      end;
  finally
    lua_pop(L, 1);
  end;
end;

procedure TLUA.GlobalObjClear;
begin
  plua_ClearObjects(l, False);
end;

procedure TLUA.GlobalVarClear(const varName: string);
begin
  lua_pushstring(l, PChar(varName));
  lua_pushnil(l);
  lua_settable(L, LUA_GLOBALSINDEX);
end;

function TLUA.TableFunctionExists(TableName,
  FunctionName: AnsiString; out tblidx : Integer): Boolean;
begin
  lua_pushstring(L, PChar(TableName));
  lua_rawget(L, LUA_GLOBALSINDEX);
  result := lua_istable(L, -1);
  if result then
    begin
      tblidx := lua_gettop(L);
      lua_pushstring(L, PChar(FunctionName));
      lua_rawget(L, -2);
      result := lua_isfunction(L, -1);
      lua_pop(L, 1);
    end
  else
    begin
      tblidx := -1;
      lua_pop(L, 1);
    end;
end;

function TLUA.TableFunctionExists(TableName, FunctionName: AnsiString
  ): Boolean;
var
  tblidx : Integer;
begin
  result := TableFunctionExists(TableName, FunctionName, tblidx);
  if result then
    lua_pop(L, 1);
end;

{ TLUAThread }

function TLUAThread.GetIsValid: Boolean;
begin
  lua_getglobal(L, PChar(FThreadName));
  result := not lua_isnil(L, 1);
  lua_pop(L, 1);
end;

constructor TLUAThread.Create(LUAInstance: TLUA; ThreadName: AnsiString);
begin
  L := lua_newthread(LUAInstance.LuaState);
  FThreadName := ThreadName;
  lua_setglobal(LUAInstance.LuaState, PChar(ThreadName));
  FMaster := LUAInstance;
end;

destructor TLUAThread.Destroy;
begin
  lua_pushnil(FMaster.LuaState);
  lua_setglobal(FMaster.LuaState, PChar(FThreadName));
  inherited;
end;

function luaResume(L : PLua_State; NArgs:Integer; out Res : Integer) : Boolean;
begin
  Res := lua_resume(L, NArgs);
  result := Res <> 0;
end;

function TLUAThread.Start(TableName : AnsiString; AMethodName : AnsiString; const ArgNames: array of AnsiString; var ErrorString : AnsiString) : Boolean;
var
  i,
  rres : Integer;
begin
  FTableName := TableName;
  FMethodName := AMethodName;
  if TableName <> '' then
    begin
      lua_pushstring(L, PChar(TableName));
      lua_gettable(L, LUA_GLOBALSINDEX);
      plua_pushstring(L, PChar(AMethodName));
      lua_rawget(L, -2);
    end
  else
    lua_getglobal(L, PChar(AMethodName));

  for i := 0 to Length(ArgNames)-1 do
    lua_getglobal(L, PChar(ArgNames[i]));

  if luaResume(L, Length(ArgNames), rres) then
    begin
      ErrorString := lua_tostring(L, -1);
      result := false;
      exit;
    end
  else
    result := true;
end;

function TLUAThread.Resume(EllapsedTime : lua_Number; Args : array of Variant; var ErrorString : AnsiString) : Boolean;
var
  rres,
  i : Integer;
  msg : AnsiString;
begin
  lua_pushnumber(L, EllapsedTime);
  for i := 0 to Length(Args)-1 do
    plua_pushvariant(L, Args[i]);
  if luaResume(L, Length(Args)+1, rres) then
    begin
      ErrorString := lua_tostring(L, -1);
      msg := 'Error ('+IntToStr(rres)+'): '+ErrorString;
      result := false;
      raise exception.Create(msg);
    end
  else
    result := true;
end;

{ TLUAThreadList }

function TLUAThreadList.GetCount: Integer;
begin
  result := FThreads.Count;
end;

function TLUAThreadList.GetThread(index: integer): TLUAThread;
begin
  result := TLUAThread(FThreads[index]);
end;

constructor TLUAThreadList.Create(LUAInstance: TLUA);
begin
  FLUAInstance := LUAInstance;
  FThreads := TList.Create;
end;

destructor TLUAThreadList.Destroy;
var
  T : TLUAThread;
begin
  while FThreads.Count > 0 do
    begin
      T := TLUAThread(FThreads[FThreads.Count-1]);
      FThreads.Remove(T);
      T.Free;
    end;
  FThreads.Free;
  inherited;
end;

procedure TLUAThreadList.Process(EllapsedTime: lua_Number; Args : array of Variant;
  var ErrorString: AnsiString);
var
  i : Integer;
begin
  i := 0;
  while i < Count do
    begin
      if not TLUAThread(FThreads[I]).Resume(EllapsedTime, Args, ErrorString) then
        Release(i)
      else
        inc(i);
    end;
end;

function TLUAThreadList.SpinUp(TableName, AMethodName, ThreadName: AnsiString; var ErrorString : AnsiString) : Boolean;
var
  T : TLUAThread;
begin
  T := TLUAThread.Create(FLUAInstance, ThreadName);
  FThreads.Add(T);
  result := T.Start(TableName, AMethodName, [], ErrorString);
end;

function TLUAThreadList.IndexOf(ThreadName: AnsiString): Integer;
var
  i : Integer;
begin
  result := -1;
  i := 0;
  while (result = -1) and (i<FThreads.Count) do
    begin
      if CompareText(ThreadName, TLUAThread(FThreads[i]).ThreadName) = 0 then
        result := i;
      inc(i);
    end;
end;

procedure TLUAThreadList.Release(ThreadIndex: Integer);
var
  T : TLUAThread;
begin
  if (ThreadIndex < Count) and (ThreadIndex > -1) then
    begin
      T := TLUAThread(FThreads[ThreadIndex]);
      FThreads.Delete(ThreadIndex);
      T.Free;
    end;
end;

initialization

finalization

end.
