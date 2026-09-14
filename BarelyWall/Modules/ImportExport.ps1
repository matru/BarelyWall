function ConvertTo-BWExportRule {
    param([Parameter(Mandatory)][object]$Record)

    return [pscustomobject]@{
        DisplayName = $Record.DisplayName
        Program     = ConvertTo-BWPortablePath -Path $Record.Program
        Direction   = $Record.Direction
        Action      = $Record.Action
        Enabled     = ($Record.Enabled -eq 'True')
        Profile     = $Record.Profile
        Description = $Record.Description
    }
}

function Export-BWRules {
    $records = @(Get-BWRuleRecords)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path (Get-BWPath -Name Exports) "BarelyWall-Rules-$timestamp.json"
    $payload = [pscustomobject]@{
        SchemaVersion = 1
        Product       = (Get-BWRuleGroup)
        Version       = (Get-BWVersion)
        ExportedAt    = (Get-Date).ToString('o')
        Rules         = @($records | ForEach-Object { ConvertTo-BWExportRule -Record $_ })
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-BWLog -Level Information -Message "Exported $($records.Count) rule(s) to '$path'."
    return [pscustomobject]@{ Path = $path; Count = $records.Count }
}

function Get-BWImportRules {
    param([Parameter(Mandatory)][string]$Path)

    $expandedPath = Expand-BWPathVariables -Path $Path
    if (-not (Test-Path -LiteralPath $expandedPath -PathType Leaf)) { throw "Import file does not exist: $Path" }
    try {
        $payload = Get-Content -LiteralPath $expandedPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The import file is not valid JSON: $($_.Exception.Message)"
    }
    if ($payload.Product -ne (Get-BWRuleGroup) -or $payload.SchemaVersion -ne 1) {
        throw 'This is not a BarelyWall v1 export file.'
    }
    return @($payload.Rules)
}

function Import-BWRules {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Rules
    )

    $created = 0
    $skipped = 0
    $failed = 0
    $total = $Rules.Count
    $prefix = Get-BWRulePrefix
    for ($index = 0; $index -lt $total; $index++) {
        $item = $Rules[$index]
        $percent = [math]::Round((($index + 1) / $total) * 100)
        Write-Progress -Activity 'Importing BarelyWall rules' -Status $item.DisplayName -PercentComplete $percent

        if (-not $item.Program -or -not (Test-BWExecutablePath -Path $item.Program)) {
            $failed++
            Write-BWLog -Level Warning -Message "Skipped import rule because executable is missing: '$($item.Program)'."
            continue
        }
        if ($item.Direction -notin @('Inbound', 'Outbound') -or $item.Action -ne 'Block') {
            $failed++
            Write-BWLog -Level Warning -Message "Skipped invalid import rule '$($item.DisplayName)'."
            continue
        }

        $enabled = 'True'
        if ($null -ne $item.Enabled) {
            $enabled = if ([System.Convert]::ToBoolean($item.Enabled)) { 'True' } else { 'False' }
        }
        $profiles = if ($item.Profile) { @([string]$item.Profile -split '\s*,\s*') } else { @('Any') }
        $displayName = [string]$item.DisplayName
        if ($displayName -notlike "$prefix*") {
            $displayName = '{0} Imported - {1}' -f $prefix, (Get-BWExecutableDisplayName -Path $item.Program)
        }
        $result = New-BWFirewallRule -ProgramPath $item.Program -Direction $item.Direction -DisplayName $displayName `
            -Profile $profiles -Enabled $enabled -Description ([string]$item.Description)
        switch ($result.Status) {
            'Created' { $created++ }
            'Skipped' { $skipped++ }
            default   { $failed++ }
        }
    }
    Write-Progress -Activity 'Importing BarelyWall rules' -Completed
    Write-BWLog -Level Information -Message "Imported rules from '$Path': $created created, $skipped skipped, $failed failed."
    return [pscustomobject]@{ Created = $created; Skipped = $skipped; Failed = $failed; Total = $total }
}
