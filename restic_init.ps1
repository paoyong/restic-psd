Copy-Item C:\Users\pao\Dropbox\backup_scripts\restic_0.16.3_windows_amd64.exe C:\Windows\System32\restic.exe
restic init --repo E:\backups\restic_bihourly --password-file="C:\Users\pao\Dropbox\backup_scripts\restic_password"                                                   
restic init --repo E:\backups\restic_daily --password-file="C:\Users\pao\Dropbox\backup_scripts\restic_password"                                                   
restic init --repo F:\backups\restic_bihourly --password-file="C:\Users\pao\Dropbox\backup_scripts\restic_password"                                    
restic init --repo F:\backups\restic_daily --password-file="C:\Users\pao\Dropbox\backup_scripts\restic_password"              
restic init --repo C:\Users\pao\Dropbox\backups\restic_dropbox --password-file="C:\Users\pao\Dropbox\backup_scripts\restic_password"

# List of scheduled task names to delete
$scheduledTaskNames = @("ResticBihourly", "ResticDaily", "ResticHourlyDropbox")

# Loop through each task name and attempt to delete the scheduled task
foreach ($taskName in $scheduledTaskNames) {
    try {
        # Unregister the scheduled task
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        Write-Host "Scheduled task '$taskName' deleted successfully."
    } catch {
        Write-Host "Error deleting scheduled task '$taskName': $_.Exception.Message"
    }
}

$action = New-ScheduledTaskAction -Execute 'C:\Users\pao\Dropbox\backup_scripts\restic_bihourly.bat'
$trigger = New-ScheduledTaskTrigger -At 12am -Once -RepetitionInterval ([TimeSpan]::FromMinutes(30))
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $scheduledTaskNames[0] -User 'pao'

$action = New-ScheduledTaskAction -Execute 'C:\Users\pao\Dropbox\backup_scripts\restic_daily.bat'
$trigger = New-ScheduledTaskTrigger -Daily -At '9:00 PM'
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $scheduledTaskNames[1] -User 'pao'

$action = New-ScheduledTaskAction -Execute 'C:\Users\pao\Dropbox\backup_scripts\restic_dropbox.bat'
$trigger = New-ScheduledTaskTrigger -At 12am -Once -RepetitionInterval ([TimeSpan]::FromHours(1))
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $scheduledTaskNames[2] -User 'pao'

# Loop through each task name and start the scheduled task
foreach ($taskName in $scheduledTaskNames) {
    try {
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
        Write-Host "Started scheduled task '$taskName'."
    } catch {
        Write-Host "Error starting scheduled task '$taskName': $_.Exception.Message"
    }
}