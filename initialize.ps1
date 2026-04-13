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

																							
function Get-TaskStatus($taskName) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) { return [char]0x2713 } else { return [char]0x2717 }
}

function Add-RepoPicker($labelText, $defaultPath, $top) {
    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Text     = $labelText
    $lbl.Font     = New-Object System.Drawing.Font($MainFont, 9)
    $lbl.Location = New-Object System.Drawing.Point(20, $top)
    $lbl.Size     = New-Object System.Drawing.Size(520, 18)
    $form.Controls.Add($lbl)

    $txt          = New-Object System.Windows.Forms.TextBox
    $txt.Text     = $defaultPath
    $txt.Font     = New-Object System.Drawing.Font($MainFont, 9)
    $txt.Location = New-Object System.Drawing.Point(20, ($top + 20))
    $txt.Size     = New-Object System.Drawing.Size(408, 24)
    $form.Controls.Add($txt)

    $btn          = New-Object System.Windows.Forms.Button
    $btn.Text     = "Browse..."
    $btn.Font     = New-Object System.Drawing.Font($MainFont, 9)
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
$form.AutoSize        = $true
$form.AutoSizeMode    = "GrowAndShrink"
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.Font            = New-Object System.Drawing.Font($MainFont, 9)

# --- Root container (vertical layout like HTML body) ---
$root = New-Object System.Windows.Forms.FlowLayoutPanel
$root.FlowDirection = "TopDown"
$root.WrapContents  = $false
$root.AutoSize      = $true
$root.Dock          = "Fill"
$root.Padding       = New-Object System.Windows.Forms.Padding(15)
$form.Controls.Add($root)

# --- Scheduled task status ---
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Scheduled task status:"
$lblSub.AutoSize = $true
$lblSub.Margin = "0,0,0,5"
$root.Controls.Add($lblSub)

$taskLabels = @{}
foreach ($name in $TaskNames) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Font = New-Object System.Drawing.Font($MainFont, 10)
    $lbl.AutoSize = $true
    $lbl.Margin = "0,0,0,2"

    $status = Get-TaskStatus $name
    $lbl.Text = "  $status   $name"
    $lbl.ForeColor = if ($status -eq [char]0x2713) { "Green" } else { "Red" }

    $root.Controls.Add($lbl)
    $taskLabels[$name] = $lbl
}

# --- Watched folders ---
$lblFolders = New-Object System.Windows.Forms.Label
$lblFolders.Text = "Watched folders. Pick your main work folder(s) that will get automatically backed up."
$lblFolders.AutoSize = $true
$lblFolders.Margin = "0,5,0,5"
$root.Controls.Add($lblFolders)

$lstFolders = New-Object System.Windows.Forms.ListBox
$lstFolders.Height = 100
$lstFolders.Width  = 460
$lstFolders.Items.Add("C:\Users\$env:USERNAME\Desktop\*WORKING*") | Out-Null
$root.Controls.Add($lstFolders)

# --- Buttons row ---
$rowFolders = New-Object System.Windows.Forms.FlowLayoutPanel
$rowFolders.AutoSize = $true
$rowFolders.Margin = "0,5,0,5"

$btnAddFolder = New-Object System.Windows.Forms.Button
$btnAddFolder.AutoSize = $true
$btnAddFolder.Text = "Add Folder..."

$btnModify = New-Object System.Windows.Forms.Button
$btnModify.AutoSize = $true
$btnModify.Text = "Modify"

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.AutoSize = $true
$btnRemove.Text = "Remove"

$rowFolders.Controls.Add($btnAddFolder)
$rowFolders.Controls.Add($btnModify)
$rowFolders.Controls.Add($btnRemove)
$root.Controls.Add($rowFolders)

# --- Keyword filter ---
$lblKeywords = New-Object System.Windows.Forms.Label
$lblKeywords.Text = "File filter keywords (comma separated):"
$lblKeywords.AutoSize = $true
$lblKeywords.Margin = "0,10,0,5"
$root.Controls.Add($lblKeywords)

$rowKeywords = New-Object System.Windows.Forms.FlowLayoutPanel
$rowKeywords.AutoSize = $true

$txtKeywords = New-Object System.Windows.Forms.TextBox
$txtKeywords.Text = "WORKING"
$txtKeywords.Width = 200

$lblKeyHint = New-Object System.Windows.Forms.Label
$lblKeyHint.Text = "Blank = back up all files"
$lblKeyHint.ForeColor = "Gray"
$lblKeyHint.AutoSize = $true
$lblKeyHint.Margin = "10,5,0,0"

$rowKeywords.Controls.Add($txtKeywords)
$rowKeywords.Controls.Add($lblKeyHint)
$root.Controls.Add($rowKeywords)

# --- Repo picker (HTML-like row: label + input + button) ---
function Add-RepoPicker($labelText, $defaultPath) {

    $container = New-Object System.Windows.Forms.FlowLayoutPanel
    $container.FlowDirection = "TopDown"
    $container.AutoSize = $true
    $container.Margin = "0,10,0,0"

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labelText
    $lbl.AutoSize = $true

    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.AutoSize = $true

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Text = $defaultPath
    $txt.Width = 340

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "Browse..."

    $btn.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.SelectedPath = $txt.Text
        if ($dlg.ShowDialog() -eq "OK") { $txt.Text = $dlg.SelectedPath }
    }.GetNewClosure())

    $row.Controls.Add($txt)
    $row.Controls.Add($btn)

    $container.Controls.Add($lbl)
    $container.Controls.Add($row)

    $root.Controls.Add($container)

    return $txt
}

$txtBihourly = Add-RepoPicker "Bihourly repo folder:" "E:\backups\restic_bihourly"
$txtDaily    = Add-RepoPicker "Daily repo folder:"    "E:\backups\restic_daily"

# --- Install button ---
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install backup system into  $InstallPath"
$btnInstall.Height = 40
$btnInstall.Width  = 460
$btnInstall.Margin = "0,15,0,0"

$root.Controls.Add($btnInstall)

# --- KEEP YOUR ORIGINAL EVENT HANDLERS BELOW ---
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

$btnModify.Add_Click({
    if ($lstFolders.SelectedIndex -ge 0) {

        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
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
