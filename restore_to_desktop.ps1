# restore_to_desktop.ps1 - Restores the latest bihourly backup to a folder on the Desktop

$InstallPath = "C:\Users\$env:USERNAME\Program Files (x64)\ResticBackup"
$Target      = "C:\Users\$env:USERNAME\Desktop\restic_restore"

Write-Host "Restoring latest snapshot to: $Target"
restic restore latest --repo "E:\backups\restic_bihourly" --target "$Target" --password-file "$InstallPath\restic_password"
Write-Host ""
Write-Host "Done. Your files are in: $Target"
Pause
