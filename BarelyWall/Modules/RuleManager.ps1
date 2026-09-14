function Get-BWFirewallRules {
    $prefix = Get-BWRulePrefix
    try {
        # BarelyWall creates local rules. PersistentStore is writable, unlike
        # ActiveStore, which is an aggregate view and can reject modifications.
        return @(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop |
            Where-Object { $_.DisplayName -like "$prefix*" })
    }
    catch {
        throw "Windows Firewall rules could not be read. Run BarelyWall as Administrator. Details: $($_.Exception.Message)"
    }
}

function Get-BWRuleRecords {
    param(
        [string]$ProgramPath,
        [string]$SearchText
    )

    $records = foreach ($rule in (Get-BWFirewallRules)) {
        $applicationFilter = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue | Select-Object -First 1
        $program = if ($applicationFilter) { [string]$applicationFilter.Program } else { '' }
        [pscustomobject]@{
            Rule        = $rule
            DisplayName = [string]$rule.DisplayName
            Program     = $program
            Direction   = [string]$rule.Direction
            Action      = [string]$rule.Action
            Enabled     = [string]$rule.Enabled
            Profile     = (@($rule.Profile) -join ', ')
            Description = [string]$rule.Description
        }
    }

    if ($PSBoundParameters.ContainsKey('ProgramPath')) {
        $records = @($records | Where-Object { Test-BWSamePath -Left $_.Program -Right $ProgramPath })
    }
    if (-not [string]::IsNullOrWhiteSpace($SearchText)) {
        $records = @($records | Where-Object {
            $_.DisplayName.IndexOf($SearchText, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.Program.IndexOf($SearchText, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    }
    return @($records | Sort-Object DisplayName, Direction)
}

function Get-BWRuleRecordsInFolder {
    param([Parameter(Mandatory)][string]$FolderPath)

    return @(Get-BWRuleRecords | Where-Object { $_.Program -and (Test-BWPathInFolder -Path $_.Program -FolderPath $FolderPath) })
}

function Get-BWOrphanedRuleRecords {
    return @(Get-BWRuleRecords | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.Program) -and -not (Test-Path -LiteralPath $_.Program -PathType Leaf)
    })
}

function Test-BWRuleDuplicate {
    param(
        [Parameter(Mandatory)][string]$ProgramPath,
        [Parameter(Mandatory)][ValidateSet('Inbound', 'Outbound')][string]$Direction,
        [string]$Action = 'Block',
        [object[]]$ExistingRecords
    )

    $records = if ($PSBoundParameters.ContainsKey('ExistingRecords')) {
        @($ExistingRecords)
    }
    else {
        @(Get-BWRuleRecords -ProgramPath $ProgramPath)
    }
    $matches = @($records | Where-Object {
        $_.Direction -eq $Direction -and $_.Action -eq $Action
    })
    return ($matches.Count -gt 0)
}

function New-BWFirewallRule {
    param(
        [Parameter(Mandatory)][string]$ProgramPath,
        [Parameter(Mandatory)][ValidateSet('Inbound', 'Outbound')][string]$Direction,
        [string]$DisplayName,
        [ValidateSet('Any', 'Domain', 'Private', 'Public')][string[]]$Profile = @('Any'),
        [ValidateSet('True', 'False')][string]$Enabled = 'True',
        [string]$Description,
        [object[]]$ExistingRecords
    )

    if (-not (Test-BWExecutablePath -Path $ProgramPath)) {
        return [pscustomobject]@{
            Status = 'Failed'; Direction = $Direction; Program = $ProgramPath; Message = 'The executable does not exist.'
            ErrorMessage = 'The executable does not exist.'; ErrorType = 'ValidationError'
        }
    }

    if ($Profile -contains 'Any' -and $Profile.Count -gt 1) {
        return [pscustomobject]@{
            Status = 'Failed'; Direction = $Direction; Program = $ProgramPath; Message = 'Any cannot be combined with other firewall profiles.'
            ErrorMessage = 'Any cannot be combined with other firewall profiles.'; ErrorType = 'ValidationError'
        }
    }

    $program = Resolve-BWPath -Path $ProgramPath
    $duplicateParameters = @{
        ProgramPath = $program
        Direction = $Direction
    }
    if ($PSBoundParameters.ContainsKey('ExistingRecords')) {
        $duplicateParameters.ExistingRecords = $ExistingRecords
    }
    if (Test-BWRuleDuplicate @duplicateParameters) {
        Write-BWLog -Level Information -Message "Skipped duplicate $Direction rule for '$program'."
        return [pscustomobject]@{
            Status = 'Skipped'; Direction = $Direction; Program = $program; Message = 'A matching rule already exists.'
            ErrorMessage = $null; ErrorType = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = '{0} Block {1} - {2}' -f (Get-BWRulePrefix), $Direction, (Get-BWExecutableDisplayName -Path $program)
    }
    if ([string]::IsNullOrWhiteSpace($Description)) {
        $Description = 'Created by {0} v{1}' -f (Get-BWRuleGroup), (Get-BWVersion)
    }

    try {
        $firewallEnabled = ConvertTo-BWFirewallEnabledValue -State $Enabled
        $null = New-NetFirewallRule -DisplayName $DisplayName -Description $Description -Group (Get-BWRuleGroup) `
            -Direction $Direction -Action Block -Program $program -Profile $Profile -Enabled $firewallEnabled -ErrorAction Stop
        Write-BWLog -Level Information -Message "Created $Direction block rule '$DisplayName' for '$program'."
        return [pscustomobject]@{
            Status = 'Created'; Direction = $Direction; Program = $program; Message = $DisplayName
            ErrorMessage = $null; ErrorType = $null
        }
    }
    catch {
        Write-BWLog -Level Error -Message "Failed to create $Direction rule for '$program': $($_.Exception.Message)"
        return [pscustomobject]@{
            Status = 'Failed'; Direction = $Direction; Program = $program; Message = $_.Exception.Message
            ErrorMessage = $_.Exception.Message; ErrorType = $_.Exception.GetType().FullName
        }
    }
}

function Block-BWExecutable {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('Inbound', 'Outbound')][string[]]$Directions,
        [object[]]$ExistingRecords
    )

    $existingForProgram = if ($PSBoundParameters.ContainsKey('ExistingRecords')) {
        @($ExistingRecords)
    }
    else {
        @(Get-BWRuleRecords -ProgramPath $Path)
    }
    $results = foreach ($direction in $Directions) {
        New-BWFirewallRule -ProgramPath $Path -Direction $direction -ExistingRecords $existingForProgram
    }
    if (@($results | Where-Object Status -eq 'Created').Count -gt 0) {
        Add-BWRecentApplication -Path $Path
    }
    return [pscustomobject]@{
        Program = Resolve-BWPath -Path $Path
        Created = @($results | Where-Object Status -eq 'Created').Count
        Skipped = @($results | Where-Object Status -eq 'Skipped').Count
        Failed  = @($results | Where-Object Status -eq 'Failed').Count
        Results = @($results)
    }
}

function Remove-BWRuleRecords {
    param([Parameter(Mandatory)][object[]]$Records)

    $removed = 0
    $failed = 0
    $errors = @()
    foreach ($record in $Records) {
        try {
            Remove-NetFirewallRule -Name $record.Rule.Name -PolicyStore PersistentStore -ErrorAction Stop
            $removed++
            Write-BWLog -Level Information -Message "Removed rule '$($record.DisplayName)' for '$($record.Program)'."
        }
        catch {
            $failed++
            $errors += [pscustomobject]@{
                DisplayName  = $record.DisplayName
                Program      = $record.Program
                ErrorMessage = $_.Exception.Message
                ErrorType    = $_.Exception.GetType().FullName
            }
            Write-BWLog -Level Error -Message "Could not remove '$($record.DisplayName)': $($_.Exception.Message)"
        }
    }
    return [pscustomobject]@{ Removed = $removed; Failed = $failed; Errors = $errors }
}

function Set-BWRuleState {
    param(
        [Parameter(Mandatory)][object[]]$Records,
        [Parameter(Mandatory)][bool]$Enabled
    )

    $changed = 0
    $failed = 0
    $errors = @()
    foreach ($record in $Records) {
        try {
            $requestedState = if ($Enabled) { 'True' } else { 'False' }
            $firewallState = ConvertTo-BWFirewallEnabledValue -State $requestedState
            Set-NetFirewallRule -Name $record.Rule.Name -PolicyStore PersistentStore -Enabled $firewallState -ErrorAction Stop
            $changed++
            $state = if ($Enabled) { 'enabled' } else { 'disabled' }
            Write-BWLog -Level Information -Message "$state rule '$($record.DisplayName)'."
        }
        catch {
            $failed++
            $errors += [pscustomobject]@{
                DisplayName  = $record.DisplayName
                Program      = $record.Program
                ErrorMessage = $_.Exception.Message
                ErrorType    = $_.Exception.GetType().FullName
            }
            Write-BWLog -Level Error -Message "Could not change '$($record.DisplayName)': $($_.Exception.Message)"
        }
    }
    return [pscustomobject]@{ Changed = $changed; Failed = $failed; Errors = $errors }
}

function Get-BWApplicationStatus {
    param([Parameter(Mandatory)][string]$ProgramPath)

    $records = @(Get-BWRuleRecords -ProgramPath $ProgramPath)
    $inbound = @($records | Where-Object Direction -eq 'Inbound')
    $outbound = @($records | Where-Object Direction -eq 'Outbound')
    return [pscustomobject]@{
        Program          = $ProgramPath
        Exists           = Test-BWExecutablePath -Path $ProgramPath
        Records          = $records
        InboundRules     = $inbound.Count
        OutboundRules    = $outbound.Count
        EnabledRules     = @($records | Where-Object Enabled -eq 'True').Count
        DisabledRules    = @($records | Where-Object Enabled -ne 'True').Count
        IsFullyBlocked   = ($inbound.Count -gt 0 -and $outbound.Count -gt 0)
    }
}
