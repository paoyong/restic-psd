# initialize.ps1 - ResticPSD one-click installer

# --- Self-elevate to Administrator ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process PowerShell -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallPath = "C:\Program Files\ResticPSD"
$TaskNames   = @("ResticBihourly", "ResticDaily")

function Get-TaskStatus($taskName) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) { return [char]0x2713 } else { return [char]0x2717 }
}

function Add-RepoPicker($labelText, $defaultPath, $top) {
    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Text     = $labelText
    $lbl.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
    $lbl.Location = New-Object System.Drawing.Point(20, $top)
    $lbl.Size     = New-Object System.Drawing.Size(520, 18)
    $form.Controls.Add($lbl)

    $txt          = New-Object System.Windows.Forms.TextBox
    $txt.Text     = $defaultPath
    $txt.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
    $txt.Location = New-Object System.Drawing.Point(20, ($top + 20))
    $txt.Size     = New-Object System.Drawing.Size(408, 24)
    $form.Controls.Add($txt)

    $btn          = New-Object System.Windows.Forms.Button
    $btn.Text     = "Browse..."
    $btn.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
    $btn.Location = New-Object System.Drawing.Point(436, ($top + 19))
    $btn.Size     = New-Object System.Drawing.Size(102, 26)
    $form.Controls.Add($btn)

    $btn.Add_Click({
        $dlg              = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description  = "Select repo folder"
        $dlg.SelectedPath = $txt.Text
        if ($dlg.ShowDialog() -eq "OK") { $txt.Text = $dlg.SelectedPath }
    }.GetNewClosure())

    return $txt
}

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text            = "ResticPSD Setup"
$form.Size            = New-Object System.Drawing.Size(560, 490)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text     = "ResticPSD Setup"
$lblTitle.Font     = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblTitle.Size     = New-Object System.Drawing.Size(520, 30)
$form.Controls.Add($lblTitle)

# --- Scheduled task status ---
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text     = "Scheduled task status:"
$lblSub.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSub.Location = New-Object System.Drawing.Point(20, 52)
$lblSub.Size     = New-Object System.Drawing.Size(520, 18)
$form.Controls.Add($lblSub)

$taskLabels = @{}
$y = 72
foreach ($name in $TaskNames) {
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $lbl.Location  = New-Object System.Drawing.Point(20, $y)
    $lbl.Size      = New-Object System.Drawing.Size(520, 24)
    $status        = Get-TaskStatus $name
    $lbl.Text      = "  $status   $name"
    $lbl.ForeColor = if ($status -eq [char]0x2713) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Red }
    $form.Controls.Add($lbl)
    $taskLabels[$name] = $lbl
    $y += 26
}

# --- Watched folders ---
$lblFolders = New-Object System.Windows.Forms.Label
$lblFolders.Text     = "Watched folders (backed up by both bihourly and daily):"
$lblFolders.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$lblFolders.Location = New-Object System.Drawing.Point(20, 134)
$lblFolders.Size     = New-Object System.Drawing.Size(360, 18)
$form.Controls.Add($lblFolders)

$btnAddFolder          = New-Object System.Windows.Forms.Button
$btnAddFolder.Text     = "Add Folder..."
$btnAddFolder.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$btnAddFolder.Location = New-Object System.Drawing.Point(432, 131)
$btnAddFolder.Size     = New-Object System.Drawing.Size(106, 26)
$form.Controls.Add($btnAddFolder)

$lstFolders          = New-Object System.Windows.Forms.ListBox
$lstFolders.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$lstFolders.Location = New-Object System.Drawing.Point(20, 154)
$lstFolders.Size     = New-Object System.Drawing.Size(518, 66)
$lstFolders.Items.Add("C:\Users\$env:USERNAME\Desktop") | Out-Null
$form.Controls.Add($lstFolders)

$btnRemove          = New-Object System.Windows.Forms.Button
$btnRemove.Text     = "Remove"
$btnRemove.Font     = New-Object System.Drawing.Font("Segoe UI", 8)
$btnRemove.Location = New-Object System.Drawing.Point(432, 222)
$btnRemove.Size     = New-Object System.Drawing.Size(106, 22)
$form.Controls.Add($btnRemove)

$btnAddFolder.Add_Click({
    $dlg              = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description  = "Select a folder to watch"
    $dlg.SelectedPath = "C:\Users\$env:USERNAME\Desktop"
    if ($dlg.ShowDialog() -eq "OK") {
        if (-not $lstFolders.Items.Contains($dlg.SelectedPath)) {
            $lstFolders.Items.Add($dlg.SelectedPath) | Out-Null
        }
    }
})
$btnRemove.Add_Click({
    if ($lstFolders.SelectedIndex -ge 0) { $lstFolders.Items.RemoveAt($lstFolders.SelectedIndex) }
})

# --- Keyword filter ---
$lblKeywords = New-Object System.Windows.Forms.Label
$lblKeywords.Text     = "File filter keywords (comma separated):"
$lblKeywords.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$lblKeywords.Location = New-Object System.Drawing.Point(20, 256)
$lblKeywords.Size     = New-Object System.Drawing.Size(280, 18)
$form.Controls.Add($lblKeywords)

$txtKeywords          = New-Object System.Windows.Forms.TextBox
$txtKeywords.Text     = "WORKING"
$txtKeywords.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$txtKeywords.Location = New-Object System.Drawing.Point(20, 276)
$txtKeywords.Size     = New-Object System.Drawing.Size(200, 24)
$form.Controls.Add($txtKeywords)

$lblKeyHint           = New-Object System.Windows.Forms.Label
$lblKeyHint.Text      = "(blank = back up all files)"
$lblKeyHint.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$lblKeyHint.ForeColor = [System.Drawing.Color]::Gray
$lblKeyHint.Location  = New-Object System.Drawing.Point(228, 279)
$lblKeyHint.Size      = New-Object System.Drawing.Size(200, 18)
$form.Controls.Add($lblKeyHint)

# --- Repo folder pickers ---
$txtBihourly = Add-RepoPicker "Bihourly repo folder:"  "E:\backups\restic_bihourly" 312
$txtDaily    = Add-RepoPicker "Daily repo folder:"     "E:\backups\restic_daily"    358

# --- Install button ---
$btnInstall          = New-Object System.Windows.Forms.Button
$btnInstall.Text     = "Install backup system into  $InstallPath"
$btnInstall.Location = New-Object System.Drawing.Point(20, 410)
$btnInstall.Size     = New-Object System.Drawing.Size(510, 42)
$btnInstall.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($btnInstall)

$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $btnInstall.Text    = "Installing..."
    $form.Refresh()

    $repoBihourly = $txtBihourly.Text
    $repoDaily    = $txtDaily.Text

    # 1. Copy all scripts and restic binary to install dir
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Copy-Item "$ScriptDir\*" $InstallPath -Recurse -Force

    # 2. Write folders_watched.txt from the listbox
    $lstFolders.Items | Set-Content "$InstallPath\folders_watched.txt"

    # 3. Write chosen paths and keywords into config.bat
    (Get-Content "$InstallPath\config.bat") `
        -replace 'set REPO_BIHOURLY=.*', "set REPO_BIHOURLY=$repoBihourly" `
        -replace 'set REPO_DAILY=.*',    "set REPO_DAILY=$repoDaily" `
        -replace 'set KEYWORDS=.*',      "set KEYWORDS=$($txtKeywords.Text)" `
    | Set-Content "$InstallPath\config.bat"

    # 4. Put restic.exe on PATH via System32
    Copy-Item "$InstallPath\restic_0.16.3_windows_amd64.exe" "C:\Windows\System32\restic.exe" -Force

    # 5. Init repos (safe to run even if already initialised)
    $pw = "--password-file=`"$InstallPath\restic_password`""
    foreach ($repo in @($repoBihourly, $repoDaily)) {
        Invoke-Expression "restic init --repo `"$repo`" $pw" 2>$null
    }

    # 6. Recreate scheduled tasks
    foreach ($name in $TaskNames) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }

    $action  = New-ScheduledTaskAction -Execute "$InstallPath\restic_bihourly.bat"
    $trigger = New-ScheduledTaskTrigger -At 12am -Once -RepetitionInterval ([TimeSpan]::FromMinutes(30))
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskNames[0] -User $env:USERNAME | Out-Null

    $action  = New-ScheduledTaskAction -Execute "$InstallPath\restic_daily.bat"
    $trigger = New-ScheduledTaskTrigger -Daily -At '9:00 PM'
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskNames[1] -User $env:USERNAME | Out-Null

    foreach ($name in $TaskNames) {
        Start-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    }

    # 7. Create desktop shortcut to restore script
    $WshShell             = New-Object -ComObject WScript.Shell
    $shortcut             = $WshShell.CreateShortcut("C:\Users\$env:USERNAME\Desktop\Restore Files to Desktop.lnk")
    $shortcut.TargetPath  = "powershell.exe"
    $shortcut.Arguments   = "-ExecutionPolicy Bypass -File `"$InstallPath\restore_to_desktop.ps1`""
    $shortcut.Description = "Restore latest backup to Desktop"
    $shortcut.Save()

    # 8. Refresh task status in the UI
    foreach ($name in $TaskNames) {
        $status = Get-TaskStatus $name
        $taskLabels[$name].Text     = "  $status   $name"
        $taskLabels[$name].ForeColor = if ($status -eq [char]0x2713) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Red }
    }

    # 9. Done
    [System.Windows.Forms.MessageBox]::Show(
        "Your files should now be automatically backed up.`nYou don't need to do anything more.",
        "Setup Complete",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $btnInstall.Text = "Installed  $([char]0x2713)"
})

$form.ShowDialog() | Out-Null
