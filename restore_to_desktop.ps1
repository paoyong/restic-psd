# restore_to_desktop.ps1 - Restores the latest bihourly backup to a folder on the Desktop

$InstallPath = "C:\Program Files\ResticPSD"

# Read repo path from config.bat
$repoBihourly = (Get-Content "$InstallPath\config.bat" |
    Where-Object { $_ -match '^set REPO_BIHOURLY=' }) -replace '^set REPO_BIHOURLY=', ''

$Target = "C:\Users\$env:USERNAME\Desktop\restic_restore"

Write-Host "Restoring latest snapshot to: $Target"
restic restore latest --repo "$repoBihourly" --target "$Target" --password-file "$InstallPath\restic_password"
Write-Host ""
Write-Host "Done. Your files are in: $Target"
Pause
