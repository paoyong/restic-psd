$USER="C:\Users\pao"
$RepoDaily="backups\restic_daily"
$RepoBiHourly="backups\restic_bihourly"
$ScriptsFolder="C:\Users\pao\Dropbox\backup_scripts"
$SnapshotsDailyCount=30
$SnapshotsBihourlyCount=16
$FILE="$ScriptsFolder\restic_files_to_backup_daily.txt"



# Check if Photoshop is running or was active within the past 15 minutes. If so, run these backup commands.
# Repeat this every 30 minutes.
# This will be a background job that runs in parallel with the rest of the script.
Start-Job -ScriptBlock {
    $true = $true
    while($true)
    {
        $photoshop = Get-Process | Where-Object {$_.Name -eq "Photoshop" -and $_.StartTime -gt (Get-Date).AddMinutes(-15)}
        if($photoshop -or (Get-Process | Where-Object {$_.Name -eq "Photoshop"}))
        {
            echo "Photoshop is running or was recently active. Running backup."
            restic backup --files-from="%FILE%" -r E:\$RepoDaily --exclude-file="$ScriptsFolder\restic_exclude.txt" --password-file="$ScriptsFolder\restic_password"
            restic backup --files-from="%FILE%" -r F:\$RepoDaily --exclude-file="$ScriptsFolder\restic_exclude.txt" --password-file="$ScriptsFolder\restic_password"
            restic backup %USER%\Desktop -r C:\Users\pao\Dropbox\backups\restic_daily --exclude-file="$ScriptsFolder\restic_exclude.txt" --password-file="$ScriptsFolder\restic_password"
            Start-Sleep -Seconds 1800
            exit
        }
        else
        {
            echo "Photoshop is not running. Sleeping for 30 minutes."
            Start-Sleep -Seconds 1800
        }
    }
}          


# Every single day without fail at 9PM, run the following backup script.
# If it was past 9PM, run it anyway regardless of the time.
