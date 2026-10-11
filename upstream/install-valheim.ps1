# Adapted from strangemap/valcraft v0.1.0 (MIT). Installs only the Valheim half.
param([Parameter(Mandatory=$true)][string]$Valheim,[Parameter(Mandatory=$true)][string]$RuntimeRoot)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$files=Join-Path $PSScriptRoot 'files'
$tmp=Join-Path $RuntimeRoot 'downloads'
$reshadeVersion='6.8.0'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
function Say($message) { Write-Host $message -ForegroundColor Cyan }
function Get-File($url,$destination) {
    & curl.exe --fail --location --silent --show-error --connect-timeout 20 --max-time 300 --retry 2 --user-agent 'Mozilla/5.0' --referer 'https://reshade.me/' --output $destination $url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $url" }
}
# --- ReShade (add-on build) as dxgi.dll ----------------------------------------------------------------------------------
$dxgi = Join-Path $Valheim 'dxgi.dll'
if (-not (Test-Path $dxgi)) {
	Say "Downloading ReShade $reshadeVersion (add-on build)"
	Get-File "https://reshade.me/downloads/ReShade_Setup_${reshadeVersion}_Addon.exe" "$tmp\reshade.exe"
	# the setup exe carries its DLLs as an appended zip
	Add-Type -AssemblyName System.IO.Compression.FileSystem
    # ReShade is a signed self-extracting EXE. Its ZIP offsets are relative to
    # the appended archive; .NET Framework must receive the archive slice.
    $bytes = [IO.File]::ReadAllBytes("$tmp\reshade.exe")
    $eocd = -1
    for ($i=$bytes.Length-22; $i -ge [Math]::Max(0,$bytes.Length-65557); $i--) {
        if ($bytes[$i] -eq 80 -and $bytes[$i+1] -eq 75 -and $bytes[$i+2] -eq 5 -and $bytes[$i+3] -eq 6) {
            if ([BitConverter]::ToUInt16($bytes,$i+10) -gt 0) { $eocd=$i; break }
        }
    }
    if ($eocd -lt 0) { throw 'Embedded ReShade archive not found.' }
    $zipStart=$eocd-[BitConverter]::ToUInt32($bytes,$eocd+12)-[BitConverter]::ToUInt32($bytes,$eocd+16)
    if ($zipStart -lt 0 -or $bytes[$zipStart] -ne 80 -or $bytes[$zipStart+1] -ne 75) {
        throw 'Invalid embedded ReShade archive offset.'
    }
    $stream=[IO.File]::Create("$tmp\reshade.zip")
    try { $stream.Write($bytes,$zipStart,$eocd+22-$zipStart) } finally { $stream.Dispose() }
    $zip=[IO.Compression.ZipFile]::OpenRead("$tmp\reshade.zip")
    try {
        $entry=$zip.Entries | Where-Object Name -eq 'ReShade64.dll' | Select-Object -First 1
        if (-not $entry) { throw 'ReShade64.dll is absent from the archive.' }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$dxgi,$true)
    } finally { $zip.Dispose() }
}
New-Item -ItemType Directory -Force "$Valheim\reshade-shaders\Shaders", "$Valheim\BepInEx\plugins" | Out-Null
foreach ($f in 'ReShade.fxh', 'ReShadeUI.fxh') {
	$dst = "$Valheim\reshade-shaders\Shaders\$f"
	if (-not (Test-Path $dst)) { Get-File "https://raw.githubusercontent.com/crosire/reshade-shaders/slim/Shaders/$f" $dst }
}
Copy-Item "$files\ValCraft.addon64" $Valheim -Force
Copy-Item "$files\MCPassthrough.fx" "$Valheim\reshade-shaders\Shaders\" -Force
Copy-Item "$files\ValCraft.dll" "$Valheim\BepInEx\plugins\" -Force
if (-not (Test-Path "$Valheim\ReShade.ini")) {
	@"
[GENERAL]
EffectSearchPaths=.\reshade-shaders\Shaders\
TextureSearchPaths=.\reshade-shaders\Textures\
PresetPath=.\ReShadePreset.ini
PreprocessorDefinitions=RESHADE_DEPTH_INPUT_IS_REVERSED=1,RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN=0,RESHADE_DEPTH_INPUT_IS_LOGARITHMIC=0,RESHADE_DEPTH_LINEARIZATION_FAR_PLANE=1000

[ADDON]
AddonPath=.\

[OVERLAY]
TutorialProgress=4
ShowClock=0
ShowFPS=0
"@ | Set-Content -Encoding ascii "$Valheim\ReShade.ini"
}
"Techniques=MCPassthrough@MCPassthrough.fx`r`nTechniqueSorting=MCPassthrough@MCPassthrough.fx" | Set-Content -Encoding ascii "$Valheim\ReShadePreset.ini"

