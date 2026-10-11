param(
    [ValidateSet('Start','Install','Check','Restore')][string]$Action='Start',
    [string]$ValheimPath='',
    [string]$MinecraftPath='',
    [string]$TLauncherPath=''
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$root=$PSScriptRoot

# Keep machine-specific paths outside the public repository.
$configFile=Join-Path $root 'valcraft.local.json'
if (Test-Path -LiteralPath $configFile) {
    $settings=Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $ValheimPath -and $settings.ValheimPath) { $ValheimPath=$settings.ValheimPath }
    if (-not $MinecraftPath -and $settings.MinecraftPath) { $MinecraftPath=$settings.MinecraftPath }
    if (-not $TLauncherPath -and $settings.TLauncherPath) { $TLauncherPath=$settings.TLauncherPath }
}
$programFilesX86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
if (-not $programFilesX86) { $programFilesX86=$env:ProgramFiles }
if (-not $ValheimPath) { $ValheimPath=Join-Path $programFilesX86 'Steam\steamapps\common\Valheim' }
if (-not $MinecraftPath) { $MinecraftPath=Join-Path $env:APPDATA '.minecraft' }
if (-not $TLauncherPath) { $TLauncherPath=Join-Path $MinecraftPath 'TLauncher.exe' }
$game=$ValheimPath
$minecraft=$MinecraftPath
$launcher=$TLauncherPath
$version='ValCraft-26.3-Fabric'
$versionDir=Join-Path $minecraft "versions\$version"
$runtime=Join-Path $root 'runtime'
$mcDir=Join-Path $runtime 'minecraft'
$backup=Join-Path $root 'backup-before-valcraft'
$manifest=Join-Path $backup 'manifest.json'
$installed=Join-Path $root 'installed-tlauncher.json'
$changedFiles=@('dxgi.dll','ReShade.ini','ReShadePreset.ini','ValCraft.addon64',
    'BepInEx\plugins\ValCraft.dll','BepInEx\config\valcraft.passthrough.cfg',
    'reshade-shaders\Shaders\MCPassthrough.fx','reshade-shaders\Shaders\ReShade.fxh',
    'reshade-shaders\Shaders\ReShadeUI.fxh')
function Test-TLauncherRunning {
    $found=@(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^(TLauncher|java|javaw)\.exe$' -and $_.CommandLine -match '(?i)tlauncher'
    })
    return ($found.Count -gt 0)
}
function Assert-Closed {
    if (Get-Process valheim -ErrorAction SilentlyContinue) { throw 'Close Valheim first.' }
    if (Test-TLauncherRunning) { throw 'Close TLauncher before installation/restoration.' }
    if (Get-BridgeProcess) { throw 'Close the ValCraft Minecraft session first.' }
}
function Get-BridgeProcess {
    $connections=@(Get-NetTCPConnection -LocalPort 25599 -State Listen -ErrorAction SilentlyContinue)
    foreach ($connection in $connections) {
        $process=Get-CimInstance Win32_Process -Filter "ProcessId=$($connection.OwningProcess)"
        if ($process.Name -match '^javaw?\.exe$' -and $process.CommandLine -match '-Dvalcraft.profile=true') {
            return $process.ProcessId
        }
    }
    return $null
}
function Save-OriginalFiles {
    if (Test-Path -LiteralPath $manifest) { return }
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    $entries=foreach ($relative in $changedFiles) {
        $source=Join-Path $game $relative
        $exists=Test-Path -LiteralPath $source -PathType Leaf
        if ($exists) {
            $dest=Join-Path $backup $relative
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item -LiteralPath $source -Destination $dest -Force
        }
        [pscustomobject]@{Path=$relative;Existed=$exists}
    }
    $entries | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8
}
function Download-Checked([string]$Url,[string]$Path,[string]$Hash,[string]$Algorithm='SHA1') {
    if ((Test-Path -LiteralPath $Path) -and ((Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash -eq $Hash)) { return }
    & curl.exe --fail --location --silent --show-error --connect-timeout 20 --max-time 300 --retry 2 --output "$Path.part" $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url (curl $LASTEXITCODE)" }
    if ((Get-FileHash -LiteralPath "$Path.part" -Algorithm $Algorithm).Hash -ne $Hash) { throw "Checksum mismatch: $Path" }
    Move-Item -LiteralPath "$Path.part" -Destination $Path -Force
}
function Install-ValCraft {
    Assert-Closed
    if (-not (Test-Path -LiteralPath "$game\valheim.exe")) { throw 'Valheim executable missing.' }
    if (-not (Test-Path -LiteralPath $launcher)) { throw 'TLauncher executable missing.' }
    if (-not (Test-Path -LiteralPath "$game\BepInEx\core\BepInEx.dll")) { throw 'The existing BepInEx installation is missing.' }
    if ((Test-Path -LiteralPath $versionDir) -and -not (Test-Path -LiteralPath "$versionDir\valcraft-managed.txt")) {
        throw "An unmanaged version already exists: $versionDir"
    }
    New-Item -ItemType Directory -Force -Path "$mcDir\mods",$versionDir,"$runtime\downloads" | Out-Null
    'Created by the local ValCraft TLauncher setup.' | Set-Content -LiteralPath "$versionDir\valcraft-managed.txt"
    Write-Host 'Preparing Minecraft 26.3 + Fabric 0.19.5 for TLauncher...' -ForegroundColor Cyan
    $catalog=Invoke-RestMethod 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
    $entry=$catalog.versions | Where-Object id -eq '26.3' | Select-Object -First 1
    if (-not $entry) { throw 'Minecraft 26.3 is absent from the Mojang manifest.' }
    Download-Checked $entry.url "$runtime\downloads\26.3.json" $entry.sha1
    $vanilla=Get-Content -LiteralPath "$runtime\downloads\26.3.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $fabric=Invoke-RestMethod 'https://meta.fabricmc.net/v2/versions/loader/26.3/0.19.5/profile/json'
    $profile=$vanilla
    $profile.id=$version
    $profile.mainClass=$fabric.mainClass
    $profile.libraries=@($fabric.libraries)+@($vanilla.libraries)
    $profile.arguments.jvm=@($vanilla.arguments.jvm)+@($fabric.arguments.jvm)+@(
        '--enable-native-access=ALL-UNNAMED','-Dpassthrough.startHidden=true',
        '-Dvalcraft.profile=true',"-Dfabric.modsFolder=$mcDir\mods",'-Xmx4096M')
    $profile.arguments.game=@($vanilla.arguments.game | ForEach-Object {
        if ($_ -is [string] -and $_ -eq '${game_directory}') { $mcDir } else { $_ }
    })
    $json=$profile | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText("$versionDir\$version.json",$json,(New-Object Text.UTF8Encoding($false)))
    Download-Checked $vanilla.downloads.client.url "$versionDir\$version.jar" $vanilla.downloads.client.sha1
    $apis=Invoke-RestMethod 'https://api.modrinth.com/v2/project/fabric-api/version?game_versions=%5B%2226.3%22%5D&loaders=%5B%22fabric%22%5D'
    $api=$apis[0].files | Where-Object primary | Select-Object -First 1
    if (-not $api) { throw 'Compatible Fabric API not found.' }
    Download-Checked $api.url "$mcDir\mods\fabric-api-valcraft.jar" $api.hashes.sha512 'SHA512'
    Copy-Item -LiteralPath "$root\upstream\files\valcraft-mc.jar" -Destination "$mcDir\mods\valcraft-mc.jar" -Force
    Save-OriginalFiles
    & "$root\upstream\install-valheim.ps1" -Valheim $game -RuntimeRoot $runtime
    # Minecraft starts first through TLauncher; the plugin finds the existing bridge.
    # AutoStart=true also lets Valheim gracefully close Minecraft when Valheim exits.
    @("[Minecraft]","AutoStart = true","Launcher = $launcher","LauncherArgs = ") |
        Set-Content -LiteralPath "$game\BepInEx\config\valcraft.passthrough.cfg" -Encoding UTF8
    [pscustomobject]@{Version='0.1.0';Root=$root;Minecraft=$version;InstalledAt=(Get-Date -Format o)} |
        ConvertTo-Json | Set-Content -LiteralPath $installed -Encoding UTF8
    [pscustomobject]@{ValheimPath=$game;MinecraftPath=$minecraft;TLauncherPath=$launcher} |
        ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding UTF8
}
function Check-Files {
    $required=@($launcher,"$game\valheim.exe","$game\BepInEx\core\BepInEx.dll",
        "$versionDir\$version.json","$versionDir\$version.jar",
        "$mcDir\mods\valcraft-mc.jar","$mcDir\mods\fabric-api-valcraft.jar")
    $required+=$changedFiles | ForEach-Object { Join-Path $game $_ }
    $missing=@($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count) { throw ("Missing files:`n"+($missing -join "`n")) }
    foreach ($pair in @(@('ValCraft.dll','BepInEx\plugins\ValCraft.dll'),@('ValCraft.addon64','ValCraft.addon64'),
        @('MCPassthrough.fx','reshade-shaders\Shaders\MCPassthrough.fx'))) {
        if ((Get-FileHash -LiteralPath "$root\upstream\files\$($pair[0])").Hash -ne
            (Get-FileHash -LiteralPath "$game\$($pair[1])").Hash) { throw "Modified mod file: $($pair[1])" }
    }
    $profile=Get-Content -LiteralPath "$versionDir\$version.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($profile.mainClass -ne 'net.fabricmc.loader.impl.launch.knot.KnotClient' -or
        $profile.arguments.game -notcontains $mcDir -or $profile.javaVersion.majorVersion -ne 25) {
        throw 'The TLauncher profile has unexpected settings.'
    }
    Write-Host 'ValCraft files and TLauncher profile verified. Gameplay must be checked in-game.' -ForegroundColor Green
}
function Select-TLauncherVersion {
    $properties=Join-Path $env:APPDATA '.tlauncher\tlauncher-2.0.properties'
    if (-not (Test-Path -LiteralPath $properties)) { return }
    $text=[IO.File]::ReadAllText($properties)
    if (-not (Test-Path -LiteralPath "$backup\tlauncher-selection.json")) {
        $line=[regex]::Match($text,'(?m)^login\.version\.game=.*$').Value.TrimEnd("`r")
        [pscustomobject]@{Line=$line} | ConvertTo-Json | Set-Content -LiteralPath "$backup\tlauncher-selection.json" -Encoding UTF8
    }
    if ($text -match '(?m)^login\.version\.game=') {
        $text=[regex]::Replace($text,'(?m)^login\.version\.game=[^\r\n]*',"login.version.game=$version")
    } else { $text+="`r`nlogin.version.game=$version`r`n" }
    [IO.File]::WriteAllText($properties,$text,(New-Object Text.UTF8Encoding($false)))
}
try {
    if ($Action -eq 'Restore') {
        Assert-Closed
        if (-not (Test-Path -LiteralPath $manifest)) { throw 'No backup manifest found.' }
        $entries=@(Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json)
        foreach ($entry in $entries) {
            if ($entry.Path -notin $changedFiles) { throw 'Unexpected backup path.' }
            if ($entry.Existed -and -not (Test-Path -LiteralPath (Join-Path $backup $entry.Path))) { throw 'Backup file missing.' }
        }
        foreach ($entry in $entries) {
            $target=Join-Path $game $entry.Path
            if ($entry.Existed) { Copy-Item -LiteralPath (Join-Path $backup $entry.Path) -Destination $target -Force }
            elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target }
        }
        $properties=Join-Path $env:APPDATA '.tlauncher\tlauncher-2.0.properties'
        if ((Test-Path -LiteralPath "$backup\tlauncher-selection.json") -and (Test-Path -LiteralPath $properties)) {
            $old=Get-Content -LiteralPath "$backup\tlauncher-selection.json" -Raw -Encoding UTF8 | ConvertFrom-Json
            $text=[IO.File]::ReadAllText($properties)
            if ($text -match "(?m)^login\.version\.game=$([regex]::Escape($version))\r?$") {
                $text=[regex]::Replace($text,'(?m)^login\.version\.game=[^\r\n]*',[Text.RegularExpressions.MatchEvaluator]{param($match) $old.Line})
                [IO.File]::WriteAllText($properties,$text,(New-Object Text.UTF8Encoding($false)))
            }
        }
        if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed }
        Write-Host 'Valheim restored. Minecraft profile, downloads and worlds kept.'
        exit 0
    }
    if ($Action -eq 'Check') { Check-Files; exit 0 }
    if ($Action -eq 'Install' -or -not (Test-Path -LiteralPath $installed)) { Install-ValCraft }
    $state=Get-Content -LiteralPath $installed -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.Root -ne $root) { throw 'Folder moved. Run INSTALL.cmd to update paths.' }
    Check-Files
    if ($Action -eq 'Install') { exit 0 }
    if (Get-Process valheim -ErrorAction SilentlyContinue) { throw 'Valheim is already running. Close it first.' }
    if (-not (Get-BridgeProcess)) {
        if (-not (Test-TLauncherRunning)) {
            Select-TLauncherVersion
            Start-Process -FilePath $launcher -WorkingDirectory $minecraft -WindowStyle Normal
        }
        Write-Host "TLauncher: select $version and click ENTER THE GAME." -ForegroundColor Yellow
        Write-Host 'First launch downloads Java 25, libraries and assets. Keep this window open.'
        Write-Host 'Valheim will start when the ValCraft bridge is listening. Ctrl+C cancels waiting.'
        $deadline=(Get-Date).AddMinutes(30)
        while (-not (Get-BridgeProcess)) {
            if ((Get-Date) -gt $deadline) { throw 'Minecraft did not start within 30 minutes. Check the TLauncher error and retry START.cmd.' }
            Start-Sleep -Seconds 2
        }
    }
    Write-Host 'Minecraft bridge found. Starting Valheim with DirectX 11...' -ForegroundColor Green
    Start-Process -FilePath "$game\valheim.exe" -ArgumentList '-force-d3d11' -WorkingDirectory $game -WindowStyle Normal
} catch {
    Write-Host ("ERROR: "+$_.Exception.Message) -ForegroundColor Red
    Write-Host 'If access to Program Files is denied, run INSTALL.cmd as administrator.'
    exit 1
}
