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
# ResticPSD_ControlPanel.ps1 template
# ---------------------------------------------------------------------------
$ControlPanelTemplate = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$InstallPath  = '__INSTALL_PATH__'
$RepoBihourly = '__REPO_BIHOURLY__'
$RepoDaily    = '__REPO_DAILY__'
$PwFile       = "$InstallPath\restic_password"
$MainFont     = 'Segoe UI'

# --- Shared helpers ---
function Get-Snapshots($repo) {
    if (-not (Test-Path $repo)) { return @() }
    $json = & restic snapshots --json -r $repo --password-file $PwFile 2>$null
    if ($json) { try { $json | ConvertFrom-Json } catch { @() } } else { @() }
}

function Get-LastSnapshotTime($repo) {
    $snaps = Get-Snapshots $repo
    if ($snaps.Count -gt 0) { try { [DateTime]::Parse(($snaps | Select-Object -Last 1).time) } catch { $null } }
    else { $null }
}

function Format-TimeAgo($dt) {
    if ($null -eq $dt) { return 'no snapshots' }
    $ago = [DateTime]::UtcNow - $dt.ToUniversalTime()
    if ($ago.TotalMinutes -lt 60) { return "$([int]$ago.TotalMinutes)m ago" }
    if ($ago.TotalHours   -lt 24) { return "$([int]$ago.TotalHours)h ago"   }
    "$([int]$ago.TotalDays)d ago"
}

function New-TrayIcon($ok) {
    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.FillEllipse(
        $(if ($ok) { [System.Drawing.Brushes]::ForestGreen } else { [System.Drawing.Brushes]::Crimson }),
        1, 1, 13, 13)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
    if ($ok) {
        $g.DrawLines($pen, [System.Drawing.Point[]]@(
            [System.Drawing.Point]::new(3,  8),
            [System.Drawing.Point]::new(6, 11),
            [System.Drawing.Point]::new(12, 4)))
    } else {
        $g.DrawLine($pen,  4,  4, 11, 11)
        $g.DrawLine($pen, 11,  4,  4, 11)
    }
    $pen.Dispose(); $g.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $bmp.Dispose(); $icon
}

function Invoke-Restore($repo, $snapId) {
    $target = "$env:USERPROFILE\Desktop\restic_restore_$snapId"
    & restic restore $snapId -r $repo --target $target --password-file $PwFile 2>$null
    if (Test-Path $target) { Start-Process explorer.exe $target }
}

# --- Main form (hidden until tray click) ---
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'ResticPSD'
$form.AutoSize        = $true
$form.AutoSizeMode    = 'GrowAndShrink'
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.ShowInTaskbar   = $false
$form.Font            = New-Object System.Drawing.Font($MainFont, 9)
$form.Add_FormClosing({ $_.Cancel = $true; $form.Hide() })

$root               = New-Object System.Windows.Forms.FlowLayoutPanel
$root.FlowDirection = 'TopDown'
$root.WrapContents  = $false
$root.AutoSize      = $true
$root.Dock          = 'Fill'
$root.Padding       = New-Object System.Windows.Forms.Padding(15)
$form.Controls.Add($root)

# Status section
$lblStatusHeader          = New-Object System.Windows.Forms.Label
$lblStatusHeader.Text     = 'BACKUP STATUS'
$lblStatusHeader.Font     = New-Object System.Drawing.Font($MainFont, 9, [System.Drawing.FontStyle]::Bold)
$lblStatusHeader.AutoSize = $true
$lblStatusHeader.Margin   = '0,0,0,4'
$root.Controls.Add($lblStatusHeader)

$statusLabels = @{}
foreach ($s in @('bihourly', 'daily')) {
    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $true
    $lbl.Margin   = '0,0,0,2'
    $root.Controls.Add($lbl)
    $statusLabels[$s] = $lbl
}

$btnRefresh          = New-Object System.Windows.Forms.Button
$btnRefresh.Text     = 'Refresh'
$btnRefresh.AutoSize = $true
$btnRefresh.Margin   = '0,8,0,12'
$root.Controls.Add($btnRefresh)

# Snapshot sections
$snapshotPanels = @{}
foreach ($s in @(
    @{ Key = 'bihourly'; Label = 'SNAPSHOTS - BIHOURLY'; Repo = $RepoBihourly },
    @{ Key = 'daily';    Label = 'SNAPSHOTS - DAILY';    Repo = $RepoDaily    }
)) {
    $hdr          = New-Object System.Windows.Forms.Label
    $hdr.Text     = $s.Label
    $hdr.Font     = New-Object System.Drawing.Font($MainFont, 9, [System.Drawing.FontStyle]::Bold)
    $hdr.AutoSize = $true
    $hdr.Margin   = '0,4,0,4'
    $root.Controls.Add($hdr)

    $panel               = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.FlowDirection = 'TopDown'
    $panel.WrapContents  = $false
    $panel.AutoSize      = $true
    $root.Controls.Add($panel)
    $snapshotPanels[$s.Key] = @{ Panel = $panel; Repo = $s.Repo }
}

function Refresh-All {
    # Status labels + tray icon
    $tB   = Get-LastSnapshotTime $RepoBihourly
    $tD   = Get-LastSnapshotTime $RepoDaily
    $okB  = $tB -and ([DateTime]::UtcNow - $tB.ToUniversalTime()).TotalMinutes -lt 30
    $okD  = $tD -and ([DateTime]::UtcNow - $tD.ToUniversalTime()).TotalHours   -lt 24

    foreach ($s in @(
        @{ Key = 'bihourly'; Ok = $okB; Time = $tB; Label = 'Bihourly' },
        @{ Key = 'daily';    Ok = $okD; Time = $tD; Label = 'Daily'    }
    )) {
        $lbl           = $statusLabels[$s.Key]
        $lbl.Text      = "  $(if ($s.Ok) { 'OK' } else { 'FAIL' })  $($s.Label)  -  $(Format-TimeAgo $s.Time)"
        $lbl.ForeColor = if ($s.Ok) { [System.Drawing.Color]::Green } else { [System.Drawing.Color]::Crimson }
    }

    $old = $notifyIcon.Icon
    $notifyIcon.Icon = New-TrayIcon ($okB -and $okD)
    if ($old) { $old.Dispose() }
    $notifyIcon.Text = "Bihourly: $(Format-TimeAgo $tB)  |  Daily: $(Format-TimeAgo $tD)"

    # Snapshot rows
    foreach ($key in $snapshotPanels.Keys) {
        $entry = $snapshotPanels[$key]
        $entry.Panel.Controls.Clear()
        $snaps = Get-Snapshots $entry.Repo
        if ($snaps.Count -eq 0) {
            $lbl           = New-Object System.Windows.Forms.Label
            $lbl.Text      = '  No snapshots found.'
            $lbl.ForeColor = [System.Drawing.Color]::Gray
            $lbl.AutoSize  = $true
            $entry.Panel.Controls.Add($lbl)
        } else {
            foreach ($snap in ($snaps | Sort-Object time -Descending)) {
                $row               = New-Object System.Windows.Forms.FlowLayoutPanel
                $row.FlowDirection = 'LeftToRight'
                $row.AutoSize      = $true
                $row.Margin        = '0,0,0,3'

                $lblId             = New-Object System.Windows.Forms.Label
                $lblId.Text        = $snap.short_id
                $lblId.Width       = 80
                $lblId.TextAlign   = 'MiddleLeft'

                $dt                = try { [DateTime]::Parse($snap.time).ToLocalTime().ToString('yyyy-MM-dd  HH:mm') } catch { $snap.time }
                $lblDate           = New-Object System.Windows.Forms.Label
                $lblDate.Text      = $dt
                $lblDate.Width     = 160
                $lblDate.TextAlign = 'MiddleLeft'

                $btn          = New-Object System.Windows.Forms.Button
                $btn.Text     = 'Restore Snapshot'
                $btn.AutoSize = $true

                $snapId  = $snap.short_id
                $repoRef = $entry.Repo
                $btn.Add_Click({
                    Invoke-Restore $repoRef $snapId
                }.GetNewClosure())

                $row.Controls.Add($lblId)
                $row.Controls.Add($lblDate)
                $row.Controls.Add($btn)
                $entry.Panel.Controls.Add($row)
            }
        }
    }
    $form.Refresh()
}

$btnRefresh.Add_Click({ Refresh-All })

# --- Tray ---
$notifyIcon         = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon    = New-TrayIcon $false
$notifyIcon.Text    = 'ResticPSD'
$notifyIcon.Visible = $true
$notifyIcon.Add_MouseClick({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($form.Visible) { $form.Hide() } else { $form.Show(); $form.BringToFront() }
    }
})

$ctx        = New-Object System.Windows.Forms.ContextMenuStrip
$mnuOpen    = New-Object System.Windows.Forms.ToolStripMenuItem 'Open Control Panel'
$mnuOpen.Add_Click({ $form.Show(); $form.BringToFront() })
$mnuExit    = New-Object System.Windows.Forms.ToolStripMenuItem 'Exit'
$mnuExit.Add_Click({
    $timer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$ctx.Items.Add($mnuOpen) | Out-Null
$ctx.Items.Add($mnuExit) | Out-Null
$notifyIcon.ContextMenuStrip = $ctx

# --- Timer: refresh every 5 minutes ---
$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = 300000
$timer.Add_Tick({ Refresh-All })
$timer.Start()

Refresh-All
[System.Windows.Forms.Application]::Run()
'@

# ---------------------------------------------------------------------------
# ResticPSD_CheckIntegrity.ps1 template - standalone integrity check
# ---------------------------------------------------------------------------
$IntegrityCheckTemplate = @'
$InstallPath  = '__INSTALL_PATH__'
$RepoBihourly = '__REPO_BIHOURLY__'
$RepoDaily    = '__REPO_DAILY__'
$PwFile       = "$InstallPath\restic_password"

function Check-Repo($name, $repo, $thresholdMinutes) {
    Write-Host "`n=== $name ===" -ForegroundColor Cyan

    if (-not (Test-Path $repo)) {
        Write-Host '  FAIL  Repo not found.' -ForegroundColor Red
        return
    }

    # Last snapshot time
    $json = & restic snapshots --json -r $repo --password-file $PwFile 2>$null
    $lastTime = $null
    try {
        $snaps = $json | ConvertFrom-Json
        if ($snaps -and $snaps.Count -gt 0) {
            $lastTime = [DateTime]::Parse(($snaps | Select-Object -Last 1).time)
        }
    } catch {}

    if ($null -eq $lastTime) {
        Write-Host '  FAIL  No snapshots found.' -ForegroundColor Red
    } else {
        $ago    = [DateTime]::UtcNow - $lastTime.ToUniversalTime()
        $agoStr = if ($ago.TotalMinutes -lt 60)  { "$([int]$ago.TotalMinutes)m ago" }
                  elseif ($ago.TotalHours -lt 24) { "$([int]$ago.TotalHours)h ago"  }
                  else                            { "$([int]$ago.TotalDays)d ago"   }
        $local  = $lastTime.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        if ($ago.TotalMinutes -lt $thresholdMinutes) {
            Write-Host "  OK    Last snapshot: $agoStr  ($local)" -ForegroundColor Green
        } else {
            Write-Host "  WARN  Last snapshot: $agoStr - overdue!  ($local)" -ForegroundColor Yellow
        }
    }

    # Structural integrity
    Write-Host '  Checking repo structure...' -ForegroundColor Gray
    & restic check -r $repo --password-file $PwFile 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  OK    Repository structure intact.' -ForegroundColor Green
    } else {
        Write-Host '  FAIL  Repository errors detected. Run restic check manually for details.' -ForegroundColor Red
    }
}

Check-Repo 'Bihourly' $RepoBihourly 30
Check-Repo 'Daily'    $RepoDaily    1440

Write-Host ''
Pause
'@

# ---------------------------------------------------------------------------
# Checklist helper  (reads $form from outer scope for Refresh)
# ---------------------------------------------------------------------------
function Set-CheckStep($labels, $key, $state) {
    $icon  = switch ($state) {
        'pending' { '[ ]' }
        'running' { '[>]' }
        'done'    { '[OK]' }
        'error'   { '[X]' }
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
    # 1. Kill ControlPanel tray process first so file handles are released
    foreach ($proc in (Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue)) {
        if ($proc.CommandLine -like '*ResticPSD_ControlPanel*') {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 600

    # 2. Unregister all ResticPSD scheduled tasks
    Get-ScheduledTask | Where-Object { $_.TaskName -like 'ResticPSD_*' } |
        ForEach-Object { Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue }

    # 3. Remove install directory
    if (Test-Path $installPath) { Remove-Item $installPath -Recurse -Force }

    # 4. Remove restic from System32
    if (Test-Path 'C:\Windows\System32\restic.exe') { Remove-Item 'C:\Windows\System32\restic.exe' -Force }

    # 5. Remove shortcuts from Desktop and Start Menu
    foreach ($dir in @(
        "$env:USERPROFILE\Desktop",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )) {
        Get-ChildItem -Path $dir -Filter 'ResticPSD*.lnk' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Install-ResticPSD
# ---------------------------------------------------------------------------
function Install-ResticPSD($cfg, $stepLabels) {

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

    foreach ($tmpl in @(
        @{ Template = $ControlPanelTemplate;   File = 'ResticPSD_ControlPanel.ps1'    },
        @{ Template = $IntegrityCheckTemplate; File = 'ResticPSD_CheckIntegrity.ps1'  }
    )) {
        $tmpl.Template `
            -replace '__INSTALL_PATH__',  $cfg.InstallPath `
            -replace '__REPO_BIHOURLY__', $cfg.RepoBihourly `
            -replace '__REPO_DAILY__',    $cfg.RepoDaily |
            Set-Content "$($cfg.InstallPath)\$($tmpl.File)" -Encoding UTF8
    }

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
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -Command `"& '$($cfg.InstallPath)\ResticPSD_bihourly.bat'`""
    $trigger = New-ScheduledTaskTrigger -At 12am -Once -RepetitionInterval ([TimeSpan]::FromMinutes(30))
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName 'ResticPSD_bihourly' -User $env:USERNAME | Out-Null
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -Command `"& '$($cfg.InstallPath)\ResticPSD_daily.bat'`""
    $trigger = New-ScheduledTaskTrigger -Daily -At '9:00 PM'
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName 'ResticPSD_daily' -User $env:USERNAME | Out-Null

    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($cfg.InstallPath)\ResticPSD_ControlPanel.ps1`""
    $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName 'ResticPSD_integrity' `
        -Settings $settings -User $env:USERNAME -RunLevel Highest | Out-Null
    Start-ScheduledTask -TaskName 'ResticPSD_integrity' -ErrorAction SilentlyContinue
    Set-CheckStep $stepLabels 'tasks' 'done'

    # 6. Run first backup session (blocking - wait for both to finish)
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
    if ($task) { return 'OK' } else { return 'X' }
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
    $lbl.ForeColor = if ($status -eq 'OK') { 'Green' } else { 'Red' }
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
)

$stepLabels = @{}
foreach ($step in $stepDefs) {
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Tag       = $step.Text
    $lbl.Text      = "  [ ]  $($step.Text)"
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
    # Validate watched folders
    $missing = @()
    foreach ($f in $lstFolders.Items) {
        if (-not (Test-Path $f)) { $missing += "Watched folder:  $f" }
    }
    if ($missing.Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "The following folders do not exist:`n`n" + ($missing -join "`n"),
            'Invalid Folders',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    # Validate backup root folder
    $backupRoot = $txtBackupRoot.Text.TrimEnd('\')
    $drive      = [System.IO.Path]::GetPathRoot($backupRoot)
    if (-not (Test-Path $drive)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Drive $drive does not exist.`nPlease choose a valid backup location.",
            'Drive Not Found',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }
    if (-not (Test-Path $backupRoot)) {
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "Backup folder does not exist:`n$backupRoot`n`nCreate it now?",
            'Create Folder?',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
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
    Install-ResticPSD $cfg $stepLabels

    foreach ($name in $TaskNames) {
        $status = Get-TaskStatus $name
        $taskLabels[$name].Text      = "  $status   $name"
        $taskLabels[$name].ForeColor = if ($status -eq 'OK') { 'Green' } else { 'Red' }
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Your files are now being backed up automatically.`nClick the taskbar icon to restore snapshots.",
        'Setup Complete',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $btnInstall.Text      = "Installed"
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
        $taskLabels[$name].ForeColor = if ($status -eq 'OK') { 'Green' } else { 'Red' }
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
