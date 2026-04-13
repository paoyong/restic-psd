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
$MainFont    = "Segoe UI"

# ---------------------------------------------------------------------------
# Read-Config: parse config.txt into the same $cfg shape as the UI produces.
# Usage: $cfg = Read-Config "C:\path\to\config.txt" ; Install-ResticPSD $cfg
# ---------------------------------------------------------------------------
function Read-Config($path) {
    $cfg = @{
        InstallPath       = $InstallPath
        RepoBihourly      = 'E:\backups\restic_bihourly'
        RepoDaily         = 'E:\backups\restic_daily'
        Keywords          = 'WORKING'
        Folders           = @()
        SnapshotsBihourly = 5
        SnapshotsDaily    = 3
        IntervalMinutes   = 30
        IntervalHours     = 24
        Exclude           = @()
    }
    $section = ''
    foreach ($line in (Get-Content $path)) {
        $line = $line.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
        switch ($section) {
            'settings' {
                if ($line -match '^(\w+)=(.*)$') {
                    switch ($Matches[1]) {
                        'REPO_BIHOURLY'      { $cfg.RepoBihourly      = $Matches[2] }
                        'REPO_DAILY'         { $cfg.RepoDaily         = $Matches[2] }
                        'KEYWORDS'           { $cfg.Keywords          = $Matches[2] }
                        'SNAPSHOTS_BIHOURLY' { $cfg.SnapshotsBihourly = [int]$Matches[2] }
                        'SNAPSHOTS_DAILY'    { $cfg.SnapshotsDaily    = [int]$Matches[2] }
                        'INTERVAL_MINUTES'   { $cfg.IntervalMinutes   = [int]$Matches[2] }
                        'INTERVAL_HOURS'     { $cfg.IntervalHours     = [int]$Matches[2] }
                    }
                }
            }
            'folders_watched' { $cfg.Folders += $line }
            'exclude'         { $cfg.Exclude += $line }
        }
    }
    return $cfg
}

# ---------------------------------------------------------------------------
# Install-ResticPSD: pure install logic — no UI references.
# Generates all files at the install location from $cfg.
# ---------------------------------------------------------------------------
function Install-ResticPSD($cfg) {
    $fastScript  = "restic_$($cfg.IntervalMinutes)min.bat"
    $dailyScript = "restic_$($cfg.IntervalHours)hr.bat"

    # 1. Create install dir and copy static files
    New-Item -ItemType Directory -Path $cfg.InstallPath -Force | Out-Null
    foreach ($f in @('restic_0.16.3_windows_amd64.exe', 'restic_password', 'restore_to_desktop.ps1')) {
        Copy-Item "$ScriptDir\$f" $cfg.InstallPath -Force
    }

    # 2. Generate config.bat
    @(
        "set INSTALL_PATH=$($cfg.InstallPath)",
        "set REPO_BIHOURLY=$($cfg.RepoBihourly)",
        "set REPO_DAILY=$($cfg.RepoDaily)",
        "set SNAPSHOTS_BIHOURLY=$($cfg.SnapshotsBihourly)",
        "set SNAPSHOTS_DAILY=$($cfg.SnapshotsDaily)",
        "set KEYWORDS=$($cfg.Keywords)"
    ) -join "`r`n" | Set-Content "$($cfg.InstallPath)\config.bat"

    # 3. Generate folders_watched.txt
    $cfg.Folders | Set-Content "$($cfg.InstallPath)\folders_watched.txt"

    # 4. Generate restic_exclude.txt
    if ($cfg.Exclude.Count -gt 0) {
        $cfg.Exclude | Set-Content "$($cfg.InstallPath)\restic_exclude.txt"
    } else {
        '' | Set-Content "$($cfg.InstallPath)\restic_exclude.txt"
    }

    # 5. Generate restic_Xmin.bat  (fast interval backup)
    @(
        '@echo off',
        'setlocal enabledelayedexpansion',
        'call "%~dp0config.bat"',
        '',
        'set INCLUDES=',
        'if not "%KEYWORDS%"=="" (',
        '    for %%K in (%KEYWORDS%) do set INCLUDES=!INCLUDES! --include=*%%K*',
        ')',
        '',
        'restic backup --files-from="%INSTALL_PATH%\folders_watched.txt" -r %REPO_BIHOURLY% %INCLUDES% --exclude-file="%INSTALL_PATH%\restic_exclude.txt" --password-file="%INSTALL_PATH%\restic_password"',
        'endlocal'
    ) -join "`r`n" | Set-Content "$($cfg.InstallPath)\$fastScript"

    # 6. Generate restic_Xhr.bat  (daily backup + prune)
    @(
        '@echo off',
        'setlocal enabledelayedexpansion',
        'call "%~dp0config.bat"',
        '',
        'set INCLUDES=',
        'if not "%KEYWORDS%"=="" (',
        '    for %%K in (%KEYWORDS%) do set INCLUDES=!INCLUDES! --include=*%%K*',
        ')',
        '',
        'restic backup --files-from="%INSTALL_PATH%\folders_watched.txt" -r %REPO_DAILY% %INCLUDES% --exclude-file="%INSTALL_PATH%\restic_exclude.txt" --password-file="%INSTALL_PATH%\restic_password"',
        '',
        'restic -r %REPO_DAILY%    forget --keep-last %SNAPSHOTS_DAILY%    --prune --password-file="%INSTALL_PATH%\restic_password"',
        'restic -r %REPO_BIHOURLY% forget --keep-last %SNAPSHOTS_BIHOURLY% --prune --password-file="%INSTALL_PATH%\restic_password"',
        'endlocal'
    ) -join "`r`n" | Set-Content "$($cfg.InstallPath)\$dailyScript"

    # 7. Put restic.exe on PATH via System32
    Copy-Item "$($cfg.InstallPath)\restic_0.16.3_windows_amd64.exe" 'C:\Windows\System32\restic.exe' -Force

    # 8. Init repos (safe if already initialised)
    $pw = "--password-file=`"$($cfg.InstallPath)\restic_password`""
    foreach ($repo in @($cfg.RepoBihourly, $cfg.RepoDaily)) {
        Invoke-Expression "restic init --repo `"$repo`" $pw" 2>$null
    }

    # 9. Recreate scheduled tasks
    foreach ($name in $TaskNames) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
    $action  = New-ScheduledTaskAction -Execute "$($cfg.InstallPath)\$fastScript"
    $trigger = New-ScheduledTaskTrigger -At 12am -Once -RepetitionInterval ([TimeSpan]::FromMinutes($cfg.IntervalMinutes))
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskNames[0] -User $env:USERNAME | Out-Null

    $action  = New-ScheduledTaskAction -Execute "$($cfg.InstallPath)\$dailyScript"
    $trigger = New-ScheduledTaskTrigger -Daily -At '9:00 PM'
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskNames[1] -User $env:USERNAME | Out-Null

    foreach ($name in $TaskNames) {
        Start-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    }

    # 10. Create desktop shortcut to restore script
    $shell            = New-Object -ComObject WScript.Shell
    $shortcut         = $shell.CreateShortcut("C:\Users\$env:USERNAME\Desktop\Restore Files to Desktop.lnk")
    $shortcut.TargetPath  = 'powershell.exe'
    $shortcut.Arguments   = "-ExecutionPolicy Bypass -File `"$($cfg.InstallPath)\restore_to_desktop.ps1`""
    $shortcut.Description = 'Restore latest backup to Desktop'
    $shortcut.Save()
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-TaskStatus($taskName) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) { return [char]0x2713 } else { return [char]0x2717 }
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'ResticPSD Setup'
$form.AutoSize        = $true
$form.AutoSizeMode    = 'GrowAndShrink'
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.Font            = New-Object System.Drawing.Font($MainFont, 9)

$root = New-Object System.Windows.Forms.FlowLayoutPanel
$root.FlowDirection = 'TopDown'
$root.WrapContents  = $false
$root.AutoSize      = $true
$root.Dock          = 'Fill'
$root.Padding       = New-Object System.Windows.Forms.Padding(15)
$form.Controls.Add($root)

# Task status
$lblSub          = New-Object System.Windows.Forms.Label
$lblSub.Text     = 'Scheduled task status:'
$lblSub.AutoSize = $true
$lblSub.Margin   = '0,0,0,5'
$root.Controls.Add($lblSub)

$taskLabels = @{}
foreach ($name in $TaskNames) {
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Font      = New-Object System.Drawing.Font($MainFont, 10)
    $lbl.AutoSize  = $true
    $lbl.Margin    = '0,0,0,2'
    $status        = Get-TaskStatus $name
    $lbl.Text      = "  $status   $name"
    $lbl.ForeColor = if ($status -eq [char]0x2713) { 'Green' } else { 'Red' }
    $root.Controls.Add($lbl)
    $taskLabels[$name] = $lbl
}

# Watched folders
$lblFolders          = New-Object System.Windows.Forms.Label
$lblFolders.Text     = 'Watched folders. Pick your main work folder(s) that will get automatically backed up.'
$lblFolders.AutoSize = $true
$lblFolders.Margin   = '0,10,0,5'
$root.Controls.Add($lblFolders)

$lstFolders        = New-Object System.Windows.Forms.ListBox
$lstFolders.Height = 100
$lstFolders.Width  = 460
$lstFolders.Items.Add("C:\Users\$env:USERNAME\Desktop") | Out-Null
$root.Controls.Add($lstFolders)

$rowFolders            = New-Object System.Windows.Forms.FlowLayoutPanel
$rowFolders.AutoSize   = $true
$rowFolders.Margin     = '0,5,0,5'
$btnAddFolder          = New-Object System.Windows.Forms.Button
$btnAddFolder.AutoSize = $true
$btnAddFolder.Text     = 'Add Folder...'
$btnModify             = New-Object System.Windows.Forms.Button
$btnModify.AutoSize    = $true
$btnModify.Text        = 'Modify'
$btnRemove             = New-Object System.Windows.Forms.Button
$btnRemove.AutoSize    = $true
$btnRemove.Text        = 'Remove'
$rowFolders.Controls.Add($btnAddFolder)
$rowFolders.Controls.Add($btnModify)
$rowFolders.Controls.Add($btnRemove)
$root.Controls.Add($rowFolders)

# Keyword filter
$lblKeywords          = New-Object System.Windows.Forms.Label
$lblKeywords.Text     = 'File filter keywords (comma separated):'
$lblKeywords.AutoSize = $true
$lblKeywords.Margin   = '0,10,0,5'
$root.Controls.Add($lblKeywords)

$rowKeywords         = New-Object System.Windows.Forms.FlowLayoutPanel
$rowKeywords.AutoSize = $true
$txtKeywords         = New-Object System.Windows.Forms.TextBox
$txtKeywords.Text    = 'WORKING'
$txtKeywords.Width   = 200
$lblKeyHint           = New-Object System.Windows.Forms.Label
$lblKeyHint.Text      = 'Blank = back up all files'
$lblKeyHint.ForeColor = 'Gray'
$lblKeyHint.AutoSize  = $true
$lblKeyHint.Margin    = '10,5,0,0'
$rowKeywords.Controls.Add($txtKeywords)
$rowKeywords.Controls.Add($lblKeyHint)
$root.Controls.Add($rowKeywords)

# Repo pickers
function Add-RepoPicker($labelText, $defaultPath) {
    $container                = New-Object System.Windows.Forms.FlowLayoutPanel
    $container.FlowDirection  = 'TopDown'
    $container.AutoSize       = $true
    $container.Margin         = '0,10,0,0'
    $lbl                      = New-Object System.Windows.Forms.Label
    $lbl.Text                 = $labelText
    $lbl.AutoSize             = $true
    $row                      = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.AutoSize             = $true
    $txt                      = New-Object System.Windows.Forms.TextBox
    $txt.Text                 = $defaultPath
    $txt.Width                = 340
    $btn                      = New-Object System.Windows.Forms.Button
    $btn.Text                 = 'Browse...'
    $btn.Add_Click({
        $dlg              = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.SelectedPath = $txt.Text
        if ($dlg.ShowDialog() -eq 'OK') { $txt.Text = $dlg.SelectedPath }
    }.GetNewClosure())
    $row.Controls.Add($txt)
    $row.Controls.Add($btn)
    $container.Controls.Add($lbl)
    $container.Controls.Add($row)
    $root.Controls.Add($container)
    return $txt
}

$txtBihourly = Add-RepoPicker 'Bihourly repo folder:' 'E:\backups\restic_bihourly'
$txtDaily    = Add-RepoPicker 'Daily repo folder:'    'E:\backups\restic_daily'

# Install button
$btnInstall        = New-Object System.Windows.Forms.Button
$btnInstall.Text   = "Install backup system into  $InstallPath"
$btnInstall.Height = 40
$btnInstall.Width  = 460
$btnInstall.Margin = '0,15,0,0'
$root.Controls.Add($btnInstall)

# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------
$btnAddFolder.Add_Click({
    $dlg              = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description  = 'Select a folder to watch'
    $dlg.SelectedPath = "C:\Users\$env:USERNAME\Desktop"
    if ($dlg.ShowDialog() -eq 'OK') {
        if (-not $lstFolders.Items.Contains($dlg.SelectedPath)) {
            $lstFolders.Items.Add($dlg.SelectedPath) | Out-Null
        }
    }
})

$btnModify.Add_Click({
    if ($lstFolders.SelectedIndex -ge 0) {
        $dlg              = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.SelectedPath = $lstFolders.SelectedItem.ToString()
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $lstFolders.Items[$lstFolders.SelectedIndex] = $dlg.SelectedPath
        }
    }
}.GetNewClosure())

$btnRemove.Add_Click({
    if ($lstFolders.SelectedIndex -ge 0) { $lstFolders.Items.RemoveAt($lstFolders.SelectedIndex) }
})

$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $btnInstall.Text    = 'Installing...'
    $form.Refresh()

    $cfg = @{
        InstallPath       = $InstallPath
        RepoBihourly      = $txtBihourly.Text
        RepoDaily         = $txtDaily.Text
        Keywords          = $txtKeywords.Text
        Folders           = @($lstFolders.Items)
        SnapshotsBihourly = 5
        SnapshotsDaily    = 3
        IntervalMinutes   = 30
        IntervalHours     = 24
        Exclude           = @()
    }

    Install-ResticPSD $cfg

    foreach ($name in $TaskNames) {
        $status = Get-TaskStatus $name
        $taskLabels[$name].Text     = "  $status   $name"
        $taskLabels[$name].ForeColor = if ($status -eq [char]0x2713) { 'Green' } else { 'Red' }
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Your files should now be automatically backed up.`nYou don't need to do anything more.",
        'Setup Complete',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $btnInstall.Text = "Installed  $([char]0x2713)"
})

$form.ShowDialog() | Out-Null
