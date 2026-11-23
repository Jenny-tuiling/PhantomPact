# ==============================================================================
# 本仓库（小朋友快乐玩mod · 本地 2–4 人）请不要运行这个脚本。
#
# 它属于上游 Phantom Pact，只把 mod/ 里的 Lua/INI 拷进 UE4SS，不带 4 人设备设置页、
# BaseVersions 两套底座、payload 依赖和卸载器。照它装出来会是一个缺零件的 1.7.3 骨架。
#
# 正确安装：下载 Release 附件 PBZ-KidsCoop-4P-2026.11.22-r1.zip，
# 校验 SHA256 = 60def7bf35a2c53baeb3009db37bf0d47628d80d9ed05c6731f286a02879b3e6，
# 解压后双击 Install.cmd 选游戏根目录。
# 本仓库只有分支 cn/four-player-local 与 tag v1.7.3；上游 main 与 v1.7.4/v1.7.5 tag
# 已删除，因此这里不存在“装上 1.7.5”的路径。
# ==============================================================================
<#
.SYNOPSIS
    Copies the PBZCoop mod into a game's UE4SS Mods folder.

.PARAMETER GameWin64
    The folder of the real game exe, where UE4SS's dwmapi.dll lives (for PBZ: ...\PBZ\platform\steam).
    Found through Steam when left out.

.EXAMPLE
    .\tools\install-mod.ps1
    .\tools\install-mod.ps1 -GameWin64 'D:\SteamLibrary\steamapps\common\PBZ\platform\steam'
#>
param(
    [string]$GameWin64
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find-game.ps1')
if (-not $GameWin64) {
    $GameWin64 = Find-PbzGame
    if (-not $GameWin64) { throw "Phantom Blade Zero wasn't found in your Steam libraries. Run again with -GameWin64 '<Steam library>\steamapps\common\PBZ\platform\steam'." }
}

if (-not (Test-Path $GameWin64)) {
    throw "Folder not found: $GameWin64"
}

# UE4SS 3.x keeps mods in ue4ss\Mods; older releases put Mods next to the DLL.
$modsDir = @('ue4ss\Mods', 'Mods') |
    ForEach-Object { Join-Path $GameWin64 $_ } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $modsDir) {
    throw "No UE4SS Mods folder in $GameWin64. Install UE4SS for Phantom Blade Zero (Nexus Mods) there first."
}

$source = Join-Path $PSScriptRoot '..\mod\PBZCoop'
$target = Join-Path $modsDir 'PBZCoop'

# Copy over the top rather than deleting first, so runtime folders (inst2\ for the self-test, net files) survive.
New-Item -ItemType Directory -Force $target | Out-Null
Copy-Item (Join-Path $source '*') $target -Recurse -Force
# The relay, once tools\build-native.ps1 has been run: online co-op needs it.
$nativeDll = Join-Path $PSScriptRoot '..\native\build\main.dll'
if (Test-Path $nativeDll) {
    New-Item -ItemType Directory -Force (Join-Path $target 'dlls') | Out-Null
    Copy-Item $nativeDll (Join-Path $target 'dlls') -Force
} elseif (-not (Test-Path (Join-Path $target 'dlls\main.dll'))) {
    Write-Warning "native\build\main.dll isn't built, and this install has none: online co-op won't start. Run tools\build-native.ps1 first."
}
# This is the developer install (the tests send "eval" through cmd.txt): turn eval on. The release zip has no dev.txt.
Set-Content (Join-Path $target 'dev.txt') 'eval enabled for development (tools\install-mod.ps1)' -Encoding ascii

# This UE4SS build loads the mods listed in mods.txt; without an entry PBZCoop silently doesn't run.
$modsTxt = Join-Path $modsDir 'mods.txt'
if (Test-Path $modsTxt) {
    $text = [IO.File]::ReadAllText($modsTxt)
    if ($text -notmatch '(?m)^\s*PBZCoop\s*:') {
        # Above the built-in Keybinds entry, which UE4SS wants last.
        if ($text -match '(?m)^; Built-in keybinds') {
            $text = $text -replace '(?m)^(; Built-in keybinds)', "PBZCoop : 1`r`n`r`n`$1"
        } else {
            $text = $text.TrimEnd() + "`r`nPBZCoop : 1`r`n"
        }
        [IO.File]::WriteAllText($modsTxt, $text)
        Write-Output "Enabled PBZCoop in $modsTxt"
    } elseif ($text -match '(?m)^\s*PBZCoop\s*:\s*0') {
        [IO.File]::WriteAllText($modsTxt, ($text -replace '(?m)^(\s*PBZCoop\s*:\s*)0', '${1}1'))
        Write-Output "Re-enabled PBZCoop in $modsTxt"
    }
}

Write-Output "Installed PBZCoop to $target"
Write-Output "Start the game: the UE4SS console should show '[PBZCoop] Loaded (instance 1, ...)'. Then see INSTALL.md, 'Play'."
