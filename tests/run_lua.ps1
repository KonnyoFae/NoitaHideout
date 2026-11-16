# Runs a mock test or checks Lua syntax with the 32-bit LuaJIT shipped with Noita.
# From the repository root: .\tests\run_lua.ps1 -CheckOnly
# Run tests in one Lua state: .\tests\run_lua.ps1 tests/test_store.lua
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [string]$LuaDll = "${env:ProgramFiles(x86)}\Steam\steamapps\common\Noita\lua51.dll",
    [Parameter(Position=0,ValueFromRemainingArguments=$true)]
    [string[]]$Files
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $LuaDll -PathType Leaf)) {
    throw "Cannot find lua51.dll. Supply -LuaDll with its full path."
}
if ([Environment]::Is64BitProcess) {
    $shell = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    $childArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','RemoteSigned','-File',$PSCommandPath,'-LuaDll',$LuaDll)
    if ($CheckOnly) { $childArgs += '-CheckOnly' }
    & $shell @childArgs @Files
    exit $LASTEXITCODE
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NoitaLuaTest {
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibrary(string path);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr luaL_newstate();
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void luaL_openlibs(IntPtr state);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern int luaL_loadbuffer(IntPtr state, byte[] bytes, UIntPtr len, string name);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern int lua_pcall(IntPtr state, int nargs, int nresults, int errfunc);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern IntPtr lua_tolstring(IntPtr state, int index, out UIntPtr len);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void lua_settop(IntPtr state, int index);
    [DllImport("lua51.dll", CallingConvention=CallingConvention.Cdecl)]
    public static extern void lua_close(IntPtr state);
}
'@

if (-not $Files) {
    if (-not $CheckOnly) { throw 'Supply a test file or specify -CheckOnly.' }
    $Files = @(Get-ChildItem -LiteralPath 'mods/noita_hideout' -Recurse -File -Filter '*.lua' | ForEach-Object FullName)
    if (-not $Files) { throw 'No mod Lua sources found.' }
}
$module = [NoitaLuaTest]::LoadLibrary((Resolve-Path -LiteralPath $LuaDll).Path)
if ($module -eq [IntPtr]::Zero) { throw "Loading the x86 Lua DLL failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
$state = [NoitaLuaTest]::luaL_newstate()
if ($state -eq [IntPtr]::Zero) { throw 'Cannot create Lua state' }
try {
    [NoitaLuaTest]::luaL_openlibs($state)
    foreach ($file in $Files) {
        $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $file).Path)
        $rc = [NoitaLuaTest]::luaL_loadbuffer($state, $bytes, [UIntPtr]::new([uint32]$bytes.Length), "@$file")
        if ($rc -eq 0 -and -not $CheckOnly) { $rc = [NoitaLuaTest]::lua_pcall($state, 0, 0, 0) }
        if ($rc -ne 0) {
            $size = [UIntPtr]::Zero
            $ptr = [NoitaLuaTest]::lua_tolstring($state, -1, [ref]$size)
            if ($ptr -eq [IntPtr]::Zero) { throw "$file returned Lua error $rc" }
            $errorBytes = New-Object byte[] ($size.ToUInt32())
            [Runtime.InteropServices.Marshal]::Copy($ptr, $errorBytes, 0, $errorBytes.Length)
            throw [Text.Encoding]::UTF8.GetString($errorBytes)
        }
        [NoitaLuaTest]::lua_settop($state, 0)
        Write-Output "PASS $file"
    }
} finally { [NoitaLuaTest]::lua_close($state) }
