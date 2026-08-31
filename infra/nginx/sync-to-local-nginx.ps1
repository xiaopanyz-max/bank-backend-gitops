$ErrorActionPreference = "Stop"

$repoNginxConf = Join-Path $PSScriptRoot "nginx.conf"
$localNginxHome = "C:\Users\94756\AppData\Local\Microsoft\WinGet\Packages\nginxinc.nginx_Microsoft.Winget.Source_8wekyb3d8bbwe\nginx-1.31.4"
$localNginxConf = Join-Path $localNginxHome "conf\nginx.conf"
$localNginxExe = Join-Path $localNginxHome "nginx.exe"

if (-not (Test-Path -LiteralPath $repoNginxConf)) {
    throw "Source nginx.conf not found: $repoNginxConf"
}

if (-not (Test-Path -LiteralPath $localNginxExe)) {
    throw "nginx.exe not found: $localNginxExe"
}

if (-not (Test-Path -LiteralPath $localNginxConf)) {
    throw "Local nginx.conf not found: $localNginxConf"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = "$localNginxConf.bak-$timestamp"

Copy-Item -LiteralPath $localNginxConf -Destination $backupPath
Copy-Item -LiteralPath $repoNginxConf -Destination $localNginxConf -Force

Push-Location $localNginxHome
try {
    & $localNginxExe -t

    $nginxProcess = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($nginxProcess) {
        & $localNginxExe -s reload
        Write-Host "nginx reloaded. Backup: $backupPath"
    } else {
        Start-Process -FilePath $localNginxExe -WorkingDirectory $localNginxHome -WindowStyle Hidden
        Write-Host "nginx started. Backup: $backupPath"
    }
}
finally {
    Pop-Location
}
