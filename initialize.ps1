# initialize.ps1 - ResticPSD installer

# --- Self-elevate to Administrator ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process PowerShell -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallPath = "C:\Program Files\ResticPSD"
$TaskNames   = @('ResticPSD_bihourly', 'ResticPSD_daily')
$MainFont    = "Segoe UI"

# ---------------------------------------------------------------------------
# ResticPSD_Restore.ps1 template  (__INSTALL_PATH__, __REPO_BIHOURLY__,
# __REPO_DAILY__ are replaced with real paths at install time)
# ---------------------------------------------------------------------------
$RestoreGuiTemplate = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$InstallPath  = '__INSTALL_PATH__'
$RepoBihourly = '__REPO_BIHOURLY__'
$RepoDaily    = '__REPO_DAILY__'
$PwFile       = "$InstallPath\restic_password"
$MainFont     = 'Segoe UI'

function Get-Snapshots($repo) {
    $json = & restic snapshots --json -r $repo --password-file $PwFile 2>$null
    if ($json) { try { $json | ConvertFrom-Json } catch { @() } } else { @() }
}

function Invoke-Restore($repo, $snapId) {
    $target = "$env:USERPROFILE\Desktop\restic_restore_$snapId"
    & restic restore $snapId -r $repo --target $target --password-file $PwFile 2>$null
    if (Test-Path $target) { Start-Process explorer.exe $target }
}

function Add-SnapshotRows($panel, $repo) {
    $snaps = Get-Snapshots $repo
    if ($snaps.Count -eq 0) {
        $lbl          = New-Object System.Windows.Forms.Label
        $lbl.Text     = '  No snapshots found.'
        $lbl.ForeColor = [System.Drawing.Color]::Gray
        $lbl.AutoSize = $true
        $panel.Controls.Add($lbl)
        return
    }
    foreach ($snap in ($snaps | Sort-Object time -Descending)) {
        $row              = New-Object System.Windows.Forms.FlowLayoutPanel
        $row.FlowDirection = 'LeftToRight'
        $row.AutoSize     = $true
        $row.Margin       = '0,0,0,3'

        $lblId           = New-Object System.Windows.Forms.Label
        $lblId.Text      = $snap.short_id
        $lblId.Width     = 80
        $lblId.TextAlign = 'MiddleLeft'

        $dt              = try { [DateTime]::Parse($snap.time).ToLocalTime().ToString('yyyy-MM-dd  HH:mm') } catch { $snap.time }
        $lblDate         = New-Object System.Windows.Forms.Label
        $lblDate.Text    = $dt
        $lblDate.Width   = 160
        $lblDate.TextAlign = 'MiddleLeft'

        $btn         = New-Object System.Windows.Forms.Button
        $btn.Text    = 'Restore Snapshot'
        $btn.AutoSize = $true

        $snapId  = $snap.short_id
        $repoRef = $repo
        $btn.Add_Click({
            $btn.Enabled = $false
            $btn.Text    = 'Restoring...'
            $form.Refresh()
            Invoke-Restore $repoRef $snapId
            $btn.Text = "Restored $([char]0x2713)"
        }.GetNewClosure())

        $row.Controls.Add($lblId)
        $row.Controls.Add($lblDate)
        $row.Controls.Add($btn)
        $panel.Controls.Add($row)
    }
}

$form                  = New-Object System.Windows.Forms.Form
$form.Text             = 'ResticPSD - Restore Snapshots'
$form.AutoSize         = $true
$form.AutoSizeMode     = 'GrowAndShrink'
$form.StartPosition    = 'CenterScreen'
$form.FormBorderStyle  = 'FixedDialog'
$form.MaximizeBox      = $false
$form.Font             = New-Object System.Drawing.Font($MainFont, 9)

$root               = New-Object System.Windows.Forms.FlowLayoutPanel
$root.FlowDirection = 'TopDown'
$root.WrapContents  = $false
$root.AutoSize      = $true
$root.Dock          = 'Fill'
$root.Padding       = New-Object System.Windows.Forms.Padding(15)
$form.Controls.Add($root)

foreach ($section in @(
    @{ Label = 'Bihourly'; Repo = $RepoBihourly; Margin = '0,0,0,5'  },
    @{ Label = 'Daily';    Repo = $RepoDaily;    Margin = '0,12,0,5' }
)) {
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Text      = $section.Label
    $lbl.Font      = New-Object System.Drawing.Font($MainFont, 11, [System.Drawing.FontStyle]::Bold)
    $lbl.AutoSize  = $true
    $lbl.Margin    = $section.Margin
    $root.Controls.Add($lbl)
    Add-SnapshotRows $root $section.Repo
}

$form.ShowDialog() | Out-Null
'@

# ---------------------------------------------------------------------------
# Checklist helper  (reads $form from outer scope for Refresh)
# ---------------------------------------------------------------------------
function Set-CheckStep($labels, $key, $state) {
    $icon  = switch ($state) {
        'pending' { [char]0x25CB }   # ○
        'running' { [char]0x25BA }   # ►
        'done'    { [char]0x2713 }   # ✓
        'error'   { [char]0x2717 }   # ✗
    }
    $color = switch ($state) {
        'pending' { [System.Drawing.Color]::Silver }
        'running' { [System.Drawing.Color]::FromArgb(0, 120, 215) }
        'done'    { [System.Drawing.Color]::Green }
        'error'   { [System.Drawing.Color]::Red }
    }
    $labels[$key].Text      = "  $icon  $($labels[$key].Tag)"
    $labels[$key].ForeColor = $color
    $form.Refresh()
}

# ---------------------------------------------------------------------------
# Uninstall-ResticPSD
# ---------------------------------------------------------------------------
function Uninstall-ResticPSD($installPath) {
    Get-ScheduledTask | Where-Object { $_.TaskName -like 'ResticPSD_*' } |
        ForEach-Object { Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false }

    if (Test-Path $installPath)                     { Remove-Item $installPath -Recurse -Force }
    if (Test-Path 'C:\Windows\System32\restic.exe') { Remove-Item 'C:\Windows\System32\restic.exe' -Force }

    foreach ($lnk in @(
        "C:\Users\$env:USERNAME\Desktop\ResticPSD - Restore to Desktop.lnk",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ResticPSD - Restore to Desktop.lnk"
    )) { if (Test-Path $lnk) { Remove-Item $lnk -Force } }
}

# ---------------------------------------------------------------------------
# Install-ResticPSD
# ---------------------------------------------------------------------------
function Install-ResticPSD($cfg, $stepLabels, $shortcuts) {

    # 1. Uninstall previous
    Set-CheckStep $stepLabels 'uninstall' 'running'
    Uninstall-ResticPSD $cfg.InstallPath
    Set-CheckStep $stepLabels 'uninstall' 'done'

    # 2. Copy files to install location
    Set-CheckStep $stepLabels 'files' 'running'
    New-Item -ItemType Directory -Path $cfg.InstallPath -Force | Out-Null
    Copy-Item "$ScriptDir\restic_0.16.3_windows_amd64.exe" $cfg.InstallPath -Force
    'restic123' | Set-Content "$($cfg.InstallPath)\restic_password"
    @(
        "set INSTALL_PATH=$($cfg.InstallPath)",
        "set REPO_BIHOURLY=$($cfg.RepoBihourly)",
        "set REPO_DAILY=$($cfg.RepoDaily)",
        "set SNAPSHOTS_BIHOURLY=5",
        "set SNAPSHOTS_DAILY=3"
    ) -join "`r`n" | Set-Content "$($cfg.InstallPath)\config.bat"
    $folderEntries = if ($cfg.Keyword) {
        $cfg.Folders | ForEach-Object { "$_\*$($cfg.Keyword)*" }
    } else {
        $cfg.Folders
    }
    $folderEntries | Set-Content "$($cfg.InstallPath)\folders_watched.txt"
    @('*.lnk', 'restic_restore') -join "`r`n" | Set-Content "$($cfg.InstallPath)\restic_exclude.txt"
    Set-CheckStep $stepLabels 'files' 'done'

    # 3. Generate backup scripts
    Set-CheckStep $stepLabels 'scripts' 'running'

    function New-BackupBat($repoVar, $pruneLines) {
        $lines = @(
            '@echo off',
            'call "%~dp0config.bat"',
            '',
            "restic backup --files-from=`"%INSTALL_PATH%\folders_watched.txt`" -r %$repoVar% --exclude-file=`"%INSTALL_PATH%\restic_exclude.txt`" --password-file=`"%INSTALL_PATH%\restic_password`""
        )
        if ($pruneLines) { $lines += $pruneLines }
        $lines -join "`r`n"
    }

    function New-RestoreBat($repoVar, $suffix) {
        @(
            '@echo off',
            'call "%~dp0config.bat"',
            "set TARGET=%USERPROFILE%\Desktop\restic_restore_$suffix",
            "restic restore latest -r %$repoVar% --target `"%TARGET%`" --password-file `"%INSTALL_PATH%\restic_password`"",
            'echo.',
            'echo Restored to %TARGET%',
            'pause'
        ) -join "`r`n"
    }

    New-BackupBat 'REPO_BIHOURLY' |
        Set-Content "$($cfg.InstallPath)\ResticPSD_bihourly.bat"

    New-BackupBat 'REPO_DAILY' @(
        '',
        'restic -r %REPO_DAILY%    forget --keep-last %SNAPSHOTS_DAILY%    --prune --password-file="%INSTALL_PATH%\restic_password"',
        'restic -r %REPO_BIHOURLY% forget --keep-last %SNAPSHOTS_BIHOURLY% --prune --password-file="%INSTALL_PATH%\restic_password"'
    ) | Set-Content "$($cfg.InstallPath)\ResticPSD_daily.bat"

    New-RestoreBat 'REPO_BIHOURLY' 'bihourly' |
        Set-Content "$($cfg.InstallPath)\RestoreToDesktop_bihourly.bat"

    New-RestoreBat 'REPO_DAILY' 'daily' |
        Set-Content "$($cfg.InstallPath)\RestoreToDesktop_daily.bat"

    $RestoreGuiTemplate `
        -replace '__INSTALL_PATH__',  $cfg.InstallPath `
        -replace '__REPO_BIHOURLY__', $cfg.RepoBihourly `
        -replace '__REPO_DAILY__',    $cfg.RepoDaily |
        Set-Content "$($cfg.InstallPath)\ResticPSD_Restore.ps1" -Encoding UTF8

    Copy-Item "$($cfg.InstallPath)\restic_0.16.3_windows_amd64.exe" 'C:\Windows\System32\restic.exe' -Force
    Set-CheckStep $stepLabels 'scripts' 'done'

    # 4. Initialize backup repositories
    Set-CheckStep $stepLabels 'repos' 'running'
    $pw = "--password-file=`"$($cfg.InstallPath)\restic_password`""
    foreach ($repo in @($cfg.RepoBihourly, $cfg.RepoDaily)) {
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        Invoke-Expression "restic init --repo `"$repo`" $pw" 2>$null
    }
    Set-CheckStep $stepLabels 'repos' 'done'

    # 5. Schedule backup tasks
    Set-CheckStep $stepLabels 'tasks' 'running'
    Get-ScheduledTask | Where-Object { $_.TaskName -like 'ResticPSD_*' } |
        ForEach-Object { Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false }
    $action  = New-ScheduledTaskAction -Execute "$($cfg.InstallPath)\ResticPSD_bihourly.bat"
    $trigger = New-ScheduledTaskTrigger -At 12am -Once -RepetitionInterval ([TimeSpan]::FromMinutes(30))
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName 'ResticPSD_bihourly' -User $env:USERNAME | Out-Null
    $action  = New-ScheduledTaskAction -Execute "$($cfg.InstallPath)\ResticPSD_daily.bat"
    $trigger = New-ScheduledTaskTrigger -Daily -At '9:00 PM'
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName 'ResticPSD_daily' -User $env:USERNAME | Out-Null
    Set-CheckStep $stepLabels 'tasks' 'done'

    # 6. Run first backup session (blocking — wait for both to finish)
    Set-CheckStep $stepLabels 'backup' 'running'
    Start-Process -FilePath "$($cfg.InstallPath)\ResticPSD_bihourly.bat" -Wait -NoNewWindow
    Start-Process -FilePath "$($cfg.InstallPath)\ResticPSD_daily.bat"    -Wait -NoNewWindow
    Set-CheckStep $stepLabels 'backup' 'done'

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

# --- Scheduled task status ---V:


$lblTaskStatus          = New-Object System.Windows.Forms.Label
$lblTaskStatus.Text     = 'Scheduled task status:'
$lblTaskStatus.AutoSize = $true
$lblTaskStatus.Margin   = '0,0,0,5'
$root.Controls.Add($lblTaskStatus)

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

# --- Watched folders ---
$lblFolders          = New-Object System.Windows.Forms.Label
$lblFolders.Text     = 'Watched folders:'
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
$rowFolders.Margin     = '0,4,0,0'
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

# --- Keyword filter ---
$chkKeyword          = New-Object System.Windows.Forms.CheckBox
$chkKeyword.Text     = 'Change keyword'
$chkKeyword.AutoSize = $true
$chkKeyword.Checked  = $false
$chkKeyword.Margin   = '0,10,0,3'
$root.Controls.Add($chkKeyword)

$txtKeyword           = New-Object System.Windows.Forms.TextBox
$txtKeyword.Text      = 'WORKING'
$txtKeyword.Width     = 200
$txtKeyword.Enabled   = $false
$txtKeyword.ForeColor = [System.Drawing.Color]::Gray
$root.Controls.Add($txtKeyword)

$chkKeyword.Add_CheckedChanged({
    $txtKeyword.Enabled   = $chkKeyword.Checked
    $txtKeyword.ForeColor = if ($chkKeyword.Checked) {
        [System.Drawing.Color]::Black
    } else {
        [System.Drawing.Color]::Gray
    }
})

# --- Backup folder picker ---
$lblBackupRoot          = New-Object System.Windows.Forms.Label
$lblBackupRoot.Text     = 'Backup folder:'
$lblBackupRoot.AutoSize = $true
$lblBackupRoot.Margin   = '0,10,0,5'
$root.Controls.Add($lblBackupRoot)

$rowBackupRoot         = New-Object System.Windows.Forms.FlowLayoutPanel
$rowBackupRoot.AutoSize = $true

$txtBackupRoot         = New-Object System.Windows.Forms.TextBox
$txtBackupRoot.Text    = 'E:\backups'
$txtBackupRoot.Width   = 340

$btnBackupRoot         = New-Object System.Windows.Forms.Button
$btnBackupRoot.Text    = 'Browse...'
$btnBackupRoot.Add_Click({
    $dlg              = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtBackupRoot.Text
    if ($dlg.ShowDialog() -eq 'OK') { $txtBackupRoot.Text = $dlg.SelectedPath }
})

$lblBackupHint          = New-Object System.Windows.Forms.Label
$lblBackupHint.AutoSize = $true
$lblBackupHint.Margin   = '0,6,0,0'
$lblBackupHint.ForeColor = [System.Drawing.Color]::Gray

$txtBackupRoot.Add_TextChanged({
    $r = $txtBackupRoot.Text.TrimEnd('\')
    $lblBackupHint.Text = "  $r\bihourly_backups    $r\daily_backups"
})
$r = $txtBackupRoot.Text.TrimEnd('\')
$lblBackupHint.Text = "  $r\bihourly_backups    $r\daily_backups"

$rowBackupRoot.Controls.Add($txtBackupRoot)
$rowBackupRoot.Controls.Add($btnBackupRoot)
$root.Controls.Add($rowBackupRoot)
$root.Controls.Add($lblBackupHint)

# --- Shortcut placement checkboxes ---
$lblShortcuts          = New-Object System.Windows.Forms.Label
$lblShortcuts.Text     = 'Place "Restore to Desktop" shortcut in:'
$lblShortcuts.AutoSize = $true
$lblShortcuts.Margin   = '0,12,0,4'
$root.Controls.Add($lblShortcuts)

$rowShortcuts          = New-Object System.Windows.Forms.FlowLayoutPanel
$rowShortcuts.AutoSize = $true
$rowShortcuts.Margin   = '0,0,0,0'

$chkDesktop           = New-Object System.Windows.Forms.CheckBox
$chkDesktop.Text      = 'Desktop'
$chkDesktop.Checked   = $true
$chkDesktop.AutoSize  = $true
$chkDesktop.Margin    = '0,0,14,0'

$chkStartMenu         = New-Object System.Windows.Forms.CheckBox
$chkStartMenu.Text    = 'Start Menu'
$chkStartMenu.Checked = $true
$chkStartMenu.AutoSize = $true
$chkStartMenu.Margin  = '0,0,0,0'

$rowShortcuts.Controls.Add($chkDesktop)
$rowShortcuts.Controls.Add($chkStartMenu)
$root.Controls.Add($rowShortcuts)

# --- Install checklist ---
$lblChecklist          = New-Object System.Windows.Forms.Label
$lblChecklist.Text     = 'Install steps:'
$lblChecklist.AutoSize = $true
$lblChecklist.Margin   = '0,12,0,3'
$root.Controls.Add($lblChecklist)

$stepDefs = @(
    @{ Key = 'uninstall'; Text = 'Uninstall previous installation' }
    @{ Key = 'files';     Text = 'Copy files to install location' }
    @{ Key = 'scripts';   Text = 'Generate backup scripts' }
    @{ Key = 'repos';     Text = 'Initialize backup repositories' }
    @{ Key = 'tasks';     Text = 'Schedule backup tasks' }
    @{ Key = 'backup';    Text = 'Run first backup session' }
    @{ Key = 'shortcuts'; Text = 'Create shortcuts' }
)

$stepLabels = @{}
foreach ($step in $stepDefs) {
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Tag       = $step.Text
    $lbl.Text      = "  $([char]0x25CB)  $($step.Text)"
    $lbl.AutoSize  = $true
    $lbl.ForeColor = [System.Drawing.Color]::Silver
    $lbl.Margin    = '0,0,0,1'
    $root.Controls.Add($lbl)
    $stepLabels[$step.Key] = $lbl
}

# --- Install / Uninstall buttons ---
$rowActions          = New-Object System.Windows.Forms.FlowLayoutPanel
$rowActions.AutoSize = $true
$rowActions.Margin   = '0,10,0,0'

$btnInstall        = New-Object System.Windows.Forms.Button
$btnInstall.Text   = "Install into  $InstallPath"
$btnInstall.Height = 40
$btnInstall.Width  = 340

$btnUninstall        = New-Object System.Windows.Forms.Button
$btnUninstall.Text   = 'Uninstall'
$btnUninstall.Height = 40
$btnUninstall.Width  = 110

$rowActions.Controls.Add($btnInstall)
$rowActions.Controls.Add($btnUninstall)
$root.Controls.Add($rowActions)

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
    # Validate folders before doing anything
    $missing = @()
    foreach ($f in $lstFolders.Items) {
        if (-not (Test-Path $f)) { $missing += "Watched folder:  $f" }
    }
    $backupRoot = $txtBackupRoot.Text.TrimEnd('\')
    if (-not (Test-Path $backupRoot)) { $missing += "Backup folder:   $backupRoot" }

    if ($missing.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "The following folders do not exist:`n`n" + ($missing -join "`n"),
            'Invalid Folders',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    $btnInstall.Enabled   = $false
    $btnUninstall.Enabled = $false
    $btnInstall.Text      = 'Installing...'

    # Reset checklist to pending
    foreach ($step in $stepDefs) { Set-CheckStep $stepLabels $step.Key 'pending' }

    $cfg = @{
        InstallPath  = $InstallPath
        RepoBihourly = "$backupRoot\bihourly_backups"
        RepoDaily    = "$backupRoot\daily_backups"
        Folders      = @($lstFolders.Items)
        Keyword      = $txtKeyword.Text.Trim()
    }
    $shortcuts = @{
        Desktop   = $chkDesktop.Checked
        StartMenu = $chkStartMenu.Checked
    }

    Install-ResticPSD $cfg $stepLabels $shortcuts

    foreach ($name in $TaskNames) {
        $status = Get-TaskStatus $name
        $taskLabels[$name].Text      = "  $status   $name"
        $taskLabels[$name].ForeColor = if ($status -eq [char]0x2713) { 'Green' } else { 'Red' }
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Your files should now be automatically backed up.`nYou don't need to do anything more.",
        'Setup Complete',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $btnInstall.Text      = "Installed  $([char]0x2713)"
    $btnInstall.Enabled   = $true
    $btnUninstall.Enabled = $true
})

$btnUninstall.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will remove all ResticPSD scheduled tasks and delete`n$InstallPath`n`nYour backup repos will NOT be deleted.`n`nContinue?",
        'Uninstall ResticPSD',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $btnInstall.Enabled   = $false
    $btnUninstall.Enabled = $false
    $btnUninstall.Text    = 'Uninstalling...'
    $form.Refresh()

    Uninstall-ResticPSD $InstallPath

    foreach ($name in $TaskNames) {
        $status = Get-TaskStatus $name
        $taskLabels[$name].Text      = "  $status   $name"
        $taskLabels[$name].ForeColor = if ($status -eq [char]0x2713) { 'Green' } else { 'Red' }
    }

    [System.Windows.Forms.MessageBox]::Show(
        'ResticPSD has been uninstalled.',
        'Uninstall Complete',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $btnUninstall.Text    = 'Uninstall'
    $btnInstall.Enabled   = $true
    $btnUninstall.Enabled = $true
})

$form.ShowDialog() | Out-Null
