#requires -Version 5.1
<#
.SYNOPSIS
    BarelyWall is a focused manager for program-specific Windows Firewall rules.
.DESCRIPTION
    Run from an elevated Windows PowerShell or PowerShell 7 session. BarelyWall
    creates and manages only rules whose display name starts with "BW -".
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$rootPath = $PSScriptRoot

. (Join-Path $rootPath 'Modules/Helpers.ps1')
. (Join-Path $rootPath 'Modules/Logging.ps1')
. (Join-Path $rootPath 'Modules/RecentApps.ps1')
. (Join-Path $rootPath 'Modules/RuleManager.ps1')
. (Join-Path $rootPath 'Modules/FolderManager.ps1')
. (Join-Path $rootPath 'Modules/ImportExport.ps1')
. (Join-Path $rootPath 'Modules/UI.ps1')

function Invoke-BWBlockExecutableFlow {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Inbound', 'Outbound', 'Both')]
        [string]$Mode
    )

    $path = Select-BWExecutablePath
    if (-not $path) { return }

    if (-not (Test-BWExecutablePath -Path $path)) {
        Write-BWMessage -Text 'Please select an existing .exe file.' -Type Error
        Pause-BW
        return
    }

    $directions = if ($Mode -eq 'Both') { @('Inbound', 'Outbound') } else { @($Mode) }
    $directionLabel = $directions -join ' and '
    if (-not (Read-BWConfirmation -Prompt "Create $directionLabel block rule(s) for `"$path`"?" -Default $true)) { return }

    try {
        $summary = Block-BWExecutable -Path $path -Directions $directions
        Show-BWBlockSummary -Summary $summary
    }
    catch {
        Write-BWMessage -Text $_.Exception.Message -Type Error
        Write-BWLog -Level Error -Message "Unable to block executable '$path': $($_.Exception.Message)"
    }
    Pause-BW
}

function Invoke-BWBlockFolderFlow {
    $folder = Select-BWFolderPath
    if (-not $folder) { return }

    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        Write-BWMessage -Text 'Please select an existing folder.' -Type Error
        Pause-BW
        return
    }

    $recurse = Read-BWConfirmation -Prompt 'Include executables in subfolders?' -Default $true
    try {
        $executables = @(Get-BWExecutablesInFolder -FolderPath $folder -Recurse:$recurse)
    }
    catch {
        Write-BWMessage -Text $_.Exception.Message -Type Error
        Pause-BW
        return
    }

    if ($executables.Count -eq 0) {
        Write-BWMessage -Text 'No executable files were found in that folder.' -Type Warning
        Pause-BW
        return
    }

    if (-not (Read-BWConfirmation -Prompt "Create inbound and outbound block rules for $($executables.Count) executable(s)?" -Default $false)) { return }

    try {
        $summary = Block-BWFolder -FolderPath $folder -Recurse:$recurse -Executables $executables
        Show-BWFolderBlockSummary -Summary $summary
    }
    catch {
        Write-BWMessage -Text $_.Exception.Message -Type Error
        Write-BWLog -Level Error -Message "Unable to block folder '$folder': $($_.Exception.Message)"
    }
    Pause-BW
}

function Invoke-BWRemoveExecutableFlow {
    $path = Select-BWExecutablePath
    if (-not $path) { return }

    $records = @(Get-BWRuleRecords -ProgramPath $path)
    if ($records.Count -eq 0) {
        Write-BWMessage -Text 'No BarelyWall rules were found for this executable.' -Type Warning
        Pause-BW
        return
    }

    Show-BWRuleTable -Records $records
    if (Read-BWConfirmation -Prompt "Remove these $($records.Count) rule(s)?" -Default $false) {
        $result = Remove-BWRuleRecords -Records $records
        Show-BWRemovalSummary -Summary $result
    }
    Pause-BW
}

function Invoke-BWRemoveFolderFlow {
    $folder = Select-BWFolderPath
    if (-not $folder) { return }

    $records = @(Get-BWRuleRecordsInFolder -FolderPath $folder)
    if ($records.Count -eq 0) {
        Write-BWMessage -Text 'No BarelyWall rules were found under that folder.' -Type Warning
        Pause-BW
        return
    }

    Show-BWRuleTable -Records $records
    if (Read-BWConfirmation -Prompt "Remove these $($records.Count) rule(s)?" -Default $false) {
        $result = Remove-BWRuleRecords -Records $records
        Show-BWRemovalSummary -Summary $result
    }
    Pause-BW
}

function Invoke-BWRemoveOrphanedFlow {
    $records = @(Get-BWOrphanedRuleRecords)
    if ($records.Count -eq 0) {
        Write-BWMessage -Text 'No orphaned BarelyWall rules were found.' -Type Success
        Pause-BW
        return
    }

    Show-BWRuleTable -Records $records
    if (Read-BWConfirmation -Prompt "Remove these $($records.Count) orphaned rule(s)?" -Default $false) {
        $result = Remove-BWRuleRecords -Records $records
        Show-BWRemovalSummary -Summary $result
    }
    Pause-BW
}

function Invoke-BWSetRuleStateFlow {
    param([Parameter(Mandatory)][bool]$Enabled)

    Write-Host ''
    Write-Host 'Apply to: [1] all BarelyWall rules  [2] one executable  [0] cancel' -ForegroundColor DarkGray
    $scope = Read-Host 'Choice'
    $records = @()
    switch ($scope) {
        '1' { $records = @(Get-BWRuleRecords) }
        '2' {
            $path = Select-BWExecutablePath
            if ($path) { $records = @(Get-BWRuleRecords -ProgramPath $path) }
        }
        default { return }
    }

    if ($records.Count -eq 0) {
        Write-BWMessage -Text 'No matching BarelyWall rules were found.' -Type Warning
        Pause-BW
        return
    }

    $verb = if ($Enabled) { 'enable' } else { 'disable' }
    if (Read-BWConfirmation -Prompt "$verb $($records.Count) rule(s)?" -Default $false) {
        $result = Set-BWRuleState -Records $records -Enabled:$Enabled
        Show-BWRuleStateSummary -Summary $result -Verb $verb
    }
    Pause-BW
}

function Invoke-BWApplicationStatusFlow {
    $path = Select-BWExecutablePath
    if (-not $path) { return }

    $status = Get-BWApplicationStatus -ProgramPath $path
    Show-BWApplicationStatus -Status $status
    Pause-BW
}

function Invoke-BWSearchFlow {
    $searchText = Read-Host 'Search text (rule name or program path)'
    if ([string]::IsNullOrWhiteSpace($searchText)) { return }

    $records = @(Get-BWRuleRecords -SearchText $searchText)
    Show-BWRuleTable -Records $records -EmptyMessage 'No matching BarelyWall rules were found.'
    Pause-BW
}

function Invoke-BWExportFlow {
    try {
        $result = Export-BWRules
        Write-BWMessage -Text "Exported $($result.Count) rule(s) to:" -Type Success
        Write-Host " $($result.Path)" -ForegroundColor DarkGray
    }
    catch {
        Write-BWMessage -Text $_.Exception.Message -Type Error
    }
    Pause-BW
}

function Invoke-BWImportFlow {
    $path = Select-BWImportFile
    if (-not $path) { return }

    try {
        $preview = @(Get-BWImportRules -Path $path)
        if ($preview.Count -eq 0) {
            Write-BWMessage -Text 'That export does not contain any rules.' -Type Warning
            Pause-BW
            return
        }

        if (-not (Read-BWConfirmation -Prompt "Import $($preview.Count) rule(s) from `"$path`"? Existing duplicates will be skipped." -Default $false)) { return }
        $result = Import-BWRules -Path $path -Rules $preview
        Show-BWImportSummary -Summary $result
    }
    catch {
        Write-BWMessage -Text $_.Exception.Message -Type Error
        Write-BWLog -Level Error -Message "Unable to import rules from '$path': $($_.Exception.Message)"
    }
    Pause-BW
}

function Start-BarelyWall {
    try {
        Assert-BWWindows
        Initialize-BWWorkspace -RootPath $rootPath
        Set-BWConsoleTitle
    }
    catch {
        Write-Host "`nBarelyWall cannot start: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    if (-not (Test-BWAdministrator)) {
        Show-BWAdministratorRequired
        return
    }

    Write-BWLog -Level Information -Message 'BarelyWall started.'
    $running = $true
    Show-BWMenu
    while ($running) {
        $choice = Read-Host 'Select an option'
        Clear-Host

        switch ($choice) {
            '1'  { Invoke-BWBlockExecutableFlow -Mode Both }
            '2'  { Invoke-BWBlockExecutableFlow -Mode Inbound }
            '3'  { Invoke-BWBlockExecutableFlow -Mode Outbound }
            '4'  { Invoke-BWBlockFolderFlow }
            '5'  { Invoke-BWRemoveExecutableFlow }
            '6'  { Invoke-BWRemoveFolderFlow }
            '7'  { Invoke-BWRemoveOrphanedFlow }
            '8'  { Invoke-BWSetRuleStateFlow -Enabled:$true }
            '9'  { Invoke-BWSetRuleStateFlow -Enabled:$false }
            '10' { Invoke-BWApplicationStatusFlow }
            '11' { Invoke-BWSearchFlow }
            '12' { Show-BWRuleTable -Records @(Get-BWRuleRecords) -EmptyMessage 'No BarelyWall rules have been created yet.'; Pause-BW }
            '13' { Invoke-BWExportFlow }
            '14' { Invoke-BWImportFlow }
            '15' { $running = $false }
            default { Write-BWMessage -Text 'Choose a number from the menu.' -Type Warning; Pause-BW }
        }

        # Render immediately after every completed or cancelled action, rather
        # than leaving the previous submenu on screen until another keypress.
        if ($running) { Show-BWMenu }
    }

    Write-BWLog -Level Information -Message 'BarelyWall closed.'
    Write-Host 'BarelyWall closed.' -ForegroundColor DarkGray
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-BarelyWall
}
