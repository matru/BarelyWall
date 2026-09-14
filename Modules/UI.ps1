function Set-BWConsoleTitle {
    try { $Host.UI.RawUI.WindowTitle = "BarelyWall v$(Get-BWVersion)" } catch { }
}

function Write-BWMessage {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')][string]$Type = 'Info'
    )

    $color = switch ($Type) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Cyan' }
    }
    $marker = switch ($Type) {
        'Success' { '+' }
        'Warning' { '!' }
        'Error'   { 'x' }
        default   { 'i' }
    }
    Write-Host "`n [$marker] $Text" -ForegroundColor $color
}

function Show-BWHeader {
    $version = Get-BWVersion
    Write-Host ''
    Write-Host '  ===========================================================' -ForegroundColor DarkCyan
    Write-Host '                         BarelyWall' -ForegroundColor Cyan
    Write-Host '                    Windows Firewall Manager' -ForegroundColor DarkGray
    Write-Host "                           v$version" -ForegroundColor DarkGray
    Write-Host '  ===========================================================' -ForegroundColor DarkCyan
}

function Show-BWMenuSection {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host "`n  $Title" -ForegroundColor Yellow
    Write-Host '  -----------------------------------------------------------' -ForegroundColor DarkGray
}

function Show-BWMenu {
    Clear-Host
    Show-BWHeader

    Show-BWMenuSection -Title 'BLOCKING'
    Write-Host '  [1]  Block EXE (Inbound + Outbound)' -ForegroundColor White
    Write-Host '  [2]  Block Inbound Only' -ForegroundColor White
    Write-Host '  [3]  Block Outbound Only' -ForegroundColor White
    Write-Host '  [4]  Block Folder (All EXEs)' -ForegroundColor White

    Show-BWMenuSection -Title 'RULE MANAGEMENT'
    Write-Host '  [5]  Remove Rules for EXE' -ForegroundColor White
    Write-Host '  [6]  Remove Rules for Folder' -ForegroundColor White
    Write-Host '  [7]  Remove Orphaned Rules' -ForegroundColor White
    Write-Host '  [8]  Enable Rules' -ForegroundColor White
    Write-Host '  [9]  Disable Rules' -ForegroundColor White

    Show-BWMenuSection -Title 'VIEW'
    Write-Host '  [10] Check Application Status' -ForegroundColor White
    Write-Host '  [11] Search Rules' -ForegroundColor White
    Write-Host '  [12] List All BarelyWall Rules' -ForegroundColor White

    Show-BWMenuSection -Title 'BACKUP'
    Write-Host '  [13] Export BarelyWall Rules' -ForegroundColor White
    Write-Host '  [14] Import BarelyWall Rules' -ForegroundColor White

    Show-BWMenuSection -Title 'OTHER'
    Write-Host '  [15] Exit' -ForegroundColor White
    Write-Host ''
}

function Read-BWConfirmation {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $false
    )

    $hint = if ($Default) { 'Y/n' } else { 'y/N' }
    $answer = Read-Host "$Prompt [$hint]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim() -match '^(y|yes)$'
}

function Pause-BW {
    Write-Host ''
    $null = Read-Host 'Press Enter to return to the menu'
}

function Get-BWPathCompletions {
    param([AllowNull()][AllowEmptyString()][string]$Path)

    $expandedPath = Expand-BWPathVariables -Path $Path
    if ([string]::IsNullOrWhiteSpace($expandedPath)) {
        $expandedPath = (Get-Location).Path + [IO.Path]::DirectorySeparatorChar
    }

    $hasTrailingSeparator = $expandedPath.EndsWith('\') -or $expandedPath.EndsWith('/')
    $parent = if ($hasTrailingSeparator) { $expandedPath } else { Split-Path -Path $expandedPath -Parent }
    $fragment = if ($hasTrailingSeparator) { '' } else { Split-Path -Path $expandedPath -Leaf }
    if ([string]::IsNullOrWhiteSpace($parent)) { $parent = (Get-Location).Path }

    try {
        return @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop |
            Where-Object { $_.Name.StartsWith($fragment, [StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object Name |
            ForEach-Object { $_.FullName })
    }
    catch {
        return @()
    }
}

function Update-BWPathInputLine {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][int]$PreviousLength
    )

    $line = "${Prompt}: $Value"
    $padding = ' ' * [Math]::Max(0, $PreviousLength - $line.Length)
    Write-Host ("`r$line$padding") -NoNewline
    Write-Host ("`r$line") -NoNewline
    return $line.Length
}

function Read-BWManualPath {
    param([Parameter(Mandatory)][string]$Prompt)

    try {
        $displayPrompt = "$Prompt (Tab completes)"
        Write-Host "${displayPrompt}: " -NoNewline
        $value = ''
        $previousLength = $displayPrompt.Length + 2
        $matches = @()
        $matchIndex = -1

        while ($true) {
            # RawUI reads individual keys in ConsoleHost, Windows Terminal,
            # and other PowerShell hosts without relying on Console.ReadKey.
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            $virtualKey = [int]$key.VirtualKeyCode
            if ($virtualKey -eq 13) {
                Write-Host ''
                return $value.Trim('"')
            }
            if ($virtualKey -eq 27) {
                Write-Host ''
                return $null
            }
            if ($virtualKey -eq 8) {
                if ($value.Length -gt 0) {
                    $value = $value.Substring(0, $value.Length - 1)
                    $previousLength = Update-BWPathInputLine -Prompt $displayPrompt -Value $value -PreviousLength $previousLength
                }
                $matches = @()
                $matchIndex = -1
                continue
            }
            if ($virtualKey -eq 9) {
                if ($matches.Count -gt 0 -and $matchIndex -ge 0 -and $value -eq $matches[$matchIndex]) {
                    $matchIndex = ($matchIndex + 1) % $matches.Count
                }
                else {
                    $matches = @(Get-BWPathCompletions -Path $value)
                    $matchIndex = 0
                }
                if ($matches.Count -gt 0) {
                    $value = [string]$matches[$matchIndex]
                    $previousLength = Update-BWPathInputLine -Prompt $displayPrompt -Value $value -PreviousLength $previousLength
                }
                continue
            }
            $character = [char]$key.Character
            if (-not [char]::IsControl($character)) {
                $value += $character
                Write-Host $character -NoNewline
                $previousLength++
                $matches = @()
                $matchIndex = -1
            }
        }
    }
    catch {
        # Some embedded hosts do not expose RawUI key input; use a plain prompt.
        return (Read-Host "$Prompt (Tab completion is unavailable in this host)")
    }
}

function Select-BWExecutablePath {
    Write-Host ''
    Write-Host '  [1] Browse for an executable' -ForegroundColor White
    Write-Host '  [2] Enter a path manually' -ForegroundColor White
    Write-Host '  [3] Choose a recent application' -ForegroundColor White
    Write-Host '  [0] Cancel' -ForegroundColor DarkGray
    $choice = Read-Host 'Select a source'
    switch ($choice) {
        '1' { return (Select-BWExecutableFileDialog) }
        '2' {
            $path = Read-BWManualPath -Prompt 'Executable path'
            if ([string]::IsNullOrWhiteSpace($path)) { return $null }
            return $path
        }
        '3' { return (Select-BWRecentApplication) }
        default { return $null }
    }
}

function Select-BWFolderPath {
    Write-Host ''
    Write-Host '  [1] Browse for a folder' -ForegroundColor White
    Write-Host '  [2] Enter a path manually' -ForegroundColor White
    Write-Host '  [0] Cancel' -ForegroundColor DarkGray
    $choice = Read-Host 'Select a source'
    switch ($choice) {
        '1' { return (Select-BWFolderDialog) }
        '2' {
            $path = Read-BWManualPath -Prompt 'Folder path'
            if ([string]::IsNullOrWhiteSpace($path)) { return $null }
            return $path
        }
        default { return $null }
    }
}

function Select-BWExecutableFileDialog {
    $dialog = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Choose an executable to manage with BarelyWall'
        $dialog.Filter = 'Executable files (*.exe)|*.exe|All files (*.*)|*.*'
        $dialog.Multiselect = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
    }
    catch {
        Write-BWMessage -Text 'The file picker is unavailable in this session. Enter the path manually.' -Type Warning
    }
    finally {
        if ($dialog) { $dialog.Dispose() }
    }
    return $null
}

function Select-BWFolderDialog {
    $dialog = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Choose a folder whose executables BarelyWall should block'
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    }
    catch {
        Write-BWMessage -Text 'The folder picker is unavailable in this session. Enter the path manually.' -Type Warning
    }
    finally {
        if ($dialog) { $dialog.Dispose() }
    }
    return $null
}

function Select-BWImportFile {
    Write-Host ''
    Write-Host '  [1] Browse for a BarelyWall export' -ForegroundColor White
    Write-Host '  [2] Enter an export path manually' -ForegroundColor White
    Write-Host '  [0] Cancel' -ForegroundColor DarkGray
    $choice = Read-Host 'Select a source'
    if ($choice -eq '1') {
        $dialog = $null
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            $dialog.Title = 'Choose a BarelyWall rule export'
            $dialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.FileName }
        }
        catch {
            Write-BWMessage -Text 'The file picker is unavailable in this session. Enter the path manually.' -Type Warning
        }
        finally {
            if ($dialog) { $dialog.Dispose() }
        }
        return $null
    }
    if ($choice -eq '2') {
        $path = Read-BWManualPath -Prompt 'Export file path'
        if (-not [string]::IsNullOrWhiteSpace($path)) { return $path.Trim('"') }
    }
    return $null
}

function Show-BWRuleTable {
    param(
        [object[]]$Records,
        [string]$EmptyMessage = 'No rules found.'
    )

    if (@($Records).Count -eq 0) {
        Write-BWMessage -Text $EmptyMessage -Type Warning
        return
    }

    $table = $Records | Select-Object @{ Name = 'Rule'; Expression = { $_.DisplayName } },
        @{ Name = 'Direction'; Expression = { $_.Direction } },
        @{ Name = 'Enabled'; Expression = { $_.Enabled } },
        @{ Name = 'Program'; Expression = { $_.Program } } |
        Format-Table -AutoSize | Out-String -Width 220
    Write-Host $table -ForegroundColor Gray
    Write-Host ("  {0} rule(s)" -f @($Records).Count) -ForegroundColor DarkGray
}

function Show-BWBlockSummary {
    param([Parameter(Mandatory)][object]$Summary)

    Write-BWMessage -Text "Completed: $($Summary.Created) created, $($Summary.Skipped) duplicate(s) skipped, $($Summary.Failed) failed." -Type $(if ($Summary.Failed) { 'Warning' } else { 'Success' })
    foreach ($result in $Summary.Results | Where-Object Status -eq 'Failed') {
        Write-Host "  $($result.Direction): $($result.Message)" -ForegroundColor Red
    }
}

function Show-BWFolderBlockSummary {
    param([Parameter(Mandatory)][object]$Summary)

    $type = if ($Summary.Failed) { 'Warning' } else { 'Success' }
    Write-BWMessage -Text "Processed $($Summary.Executables) executable(s): $($Summary.Created) rules created, $($Summary.Skipped) duplicates skipped, $($Summary.Failed) failed." -Type $type
}

function Show-BWRemovalSummary {
    param([Parameter(Mandatory)][object]$Summary)

    $type = if ($Summary.Failed -gt 0) { 'Warning' } else { 'Success' }
    Write-BWMessage -Text "Removed $($Summary.Removed) rule(s); $($Summary.Failed) failed." -Type $type
    foreach ($errorRecord in @($Summary.Errors)) {
        Write-Host "  $($errorRecord.DisplayName): $($errorRecord.ErrorMessage)" -ForegroundColor Red
    }
}

function Show-BWRuleStateSummary {
    param(
        [Parameter(Mandatory)][object]$Summary,
        [Parameter(Mandatory)][string]$Verb
    )

    $type = if ($Summary.Failed -gt 0) { 'Warning' } else { 'Success' }
    Write-BWMessage -Text "$($Summary.Changed) rule(s) $($Verb)d; $($Summary.Failed) failed." -Type $type
    foreach ($errorRecord in @($Summary.Errors)) {
        Write-Host "  $($errorRecord.DisplayName): $($errorRecord.ErrorMessage)" -ForegroundColor Red
    }
}

function Show-BWApplicationStatus {
    param([Parameter(Mandatory)][object]$Status)

    Write-Host ''
    Write-Host '  APPLICATION STATUS' -ForegroundColor Yellow
    Write-Host '  -----------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host "  Path:     $($Status.Program)" -ForegroundColor Gray
    Write-Host "  Exists:   $($Status.Exists)" -ForegroundColor Gray
    Write-Host "  Inbound:  $($Status.InboundRules) rule(s)" -ForegroundColor Gray
    Write-Host "  Outbound: $($Status.OutboundRules) rule(s)" -ForegroundColor Gray
    Write-Host "  Enabled:  $($Status.EnabledRules)    Disabled: $($Status.DisabledRules)" -ForegroundColor Gray
    $state = if ($Status.IsFullyBlocked) { 'Inbound and outbound block rules are present.' } else { 'This application is not fully blocked by BarelyWall.' }
    Write-BWMessage -Text $state -Type $(if ($Status.IsFullyBlocked) { 'Success' } else { 'Warning' })
    if ($Status.Records.Count -gt 0) { Show-BWRuleTable -Records $Status.Records }
}

function Show-BWImportSummary {
    param([Parameter(Mandatory)][object]$Summary)

    $type = if ($Summary.Failed) { 'Warning' } else { 'Success' }
    Write-BWMessage -Text "Import complete: $($Summary.Created) created, $($Summary.Skipped) duplicate(s) skipped, $($Summary.Failed) invalid or missing executable(s)." -Type $type
}

function Show-BWAdministratorRequired {
    Clear-Host
    Show-BWHeader
    Write-BWMessage -Text 'Administrator permission is required to manage Windows Firewall rules.' -Type Error
    Write-Host "`n  Close this window, then right-click BarelyWall.ps1 and choose 'Run with PowerShell' from an elevated terminal." -ForegroundColor Gray
}
