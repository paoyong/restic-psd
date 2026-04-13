# setup.ps1 - ResticBackup one-click installer

# --- Self-elevate to Administrator ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process PowerShell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallPath = "C:\Users\$env:USERNAME\Program Files (x64)\ResticBackup"
$TaskNames   = @("ResticBihourly", "ResticDaily", "ResticHourlyDropbox")

function Get-TaskStatus($taskName) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) { return [char]0x2713 } else { return [char]0x2717 }  # ✓ or ✗
}

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text            = "ResticBackup Setup"
$form.Size            = New-Object System.Drawing.Size(530, 295)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text     = "ResticBackup Setup"
$lblTitle.Font     = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblTitle.Size     = New-Object System.Drawing.Size(490, 30)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text     = "Scheduled task status:"
$lblSub.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSub.Location = New-Object System.Drawing.Point(20, 52)
$lblSub.Size     = New-Object System.Drawing.Size(490, 20)
$form.Controls.Add($lblSub)

$taskLabels = @{}
$y = 74
foreach ($name in $TaskNames) {
    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Font     = New-Object System.Drawing.Font("Segoe UI", 10)
    $lbl.Location = New-Object System.Drawing.Point(20, $y)
    $lbl.Size     = New-Object System.Drawing.Size(490, 24)
    $status       = Get-TaskStatus $name
    $lbl.Text     = "  $status   $name"
    $lbl.ForeColor = if ($status -eq [char]0x2713) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Red }
    $form.Controls.Add($lbl)
    $taskLabels[$name] = $lbl
    $y += 26
}

$btnInstall          = New-Object System.Windows.Forms.Button
$btnInstall.Text     = "Install backup system into  $InstallPath"
$btnInstall.Location = New-Object System.Drawing.Point(20, 165)
$btnInstall.Size     = New-Object System.Drawing.Size(480, 42)
$btnInstall.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($btnInstall)

$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $btnInstall.Text    = "Installing..."
    $form.Refresh()

    # 1. Copy all scripts and restic binary to install dir
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Copy-Item "$ScriptDir\*" $InstallPath -Recurse -Force

    # 2. Rewrite hardcoded paths in bat files to point to the new install location
    foreach ($bat in @("restic_bihourly.bat", "restic_daily.bat", "restic_dropbox.bat")) {
        $f = "$InstallPath\$bat"
        (Get-Content $f) `
            -replace 'set USER=.*',    "set USER=C:\Users\$env:USERNAME" `
            -replace 'set SCRIPTS=.*', "set SCRIPTS=$InstallPath" `
        | Set-Content $f
    }

    # 3. Put restic.exe on PATH via System32
    Copy-Item "$InstallPath\restic_0.16.3_windows_amd64.exe" "C:\Windows\System32\restic.exe" -Force

    # 4. Init repos (safe to run even if already initialised)
    $pw = "--password-file=`"$InstallPath\restic_password`""
    foreach ($repo in @(
        "E:\backups\restic_bihourly",
        "E:\backups\restic_daily",
        "F:\backups\restic_bihourly",
        "F:\backups\restic_daily",
        "C:\Users\$env:USERNAME\Dropbox\backups\restic_dropbox"
    )) {
        Invoke-Expression "restic init --repo `"$repo`" $pw" 2>$null
    }

    # 5. Recreate scheduled tasks pointing to InstallPath
    foreach ($name in $TaskNames) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }

    $action  = New-ScheduledTaskAction -Execute "$InstallPath\restic_bihourly.bat"
    $trigger = New-ScheduledTaskTrigger -At 12am -Once -RepetitionInterval ([TimeSpan]::FromMinutes(30))
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskNames[0] -User $env:USERNAME | Out-Null

    $action  = New-ScheduledTaskAction -Execute "$InstallPath\restic_daily.bat"
    $trigger = New-ScheduledTaskTrigger -Daily -At '9:00 PM'
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskNames[1] -User $env:USERNAME | Out-Null

    $action  = New-ScheduledTaskAction -Execute "$InstallPath\restic_dropbox.bat"
    $trigger = New-ScheduledTaskTrigger -At 12am -Once -RepetitionInterval ([TimeSpan]::FromHours(1))
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskNames[2] -User $env:USERNAME | Out-Null

    foreach ($name in $TaskNames) {
        Start-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    }

    # 6. Create desktop shortcut to restore script
    $WshShell            = New-Object -ComObject WScript.Shell
    $shortcut            = $WshShell.CreateShortcut("C:\Users\$env:USERNAME\Desktop\Restore Files to Desktop.lnk")
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments  = "-ExecutionPolicy Bypass -File `"$InstallPath\restore_to_desktop.ps1`""
    $shortcut.Description = "Restore latest backup to Desktop"
    $shortcut.Save()

    # 7. Refresh task status in the UI
    foreach ($name in $TaskNames) {
        $status = Get-TaskStatus $name
        $taskLabels[$name].Text     = "  $status   $name"
        $taskLabels[$name].ForeColor = if ($status -eq [char]0x2713) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Red }
    }

    # 8. Done
    [System.Windows.Forms.MessageBox]::Show(
        "Your files should now be automatically backed up.`nYou don't need to do anything more.",
        "Setup Complete",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $btnInstall.Text = "Installed  $([char]0x2713)"
})

$form.ShowDialog() | Out-Null
