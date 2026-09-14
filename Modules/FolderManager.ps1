function Block-BWFolder {
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [bool]$Recurse = $true,
        [System.IO.FileInfo[]]$Executables
    )

    if (-not $Executables) {
        $Executables = @(Get-BWExecutablesInFolder -FolderPath $FolderPath -Recurse:$Recurse)
    }

    $created = 0
    $skipped = 0
    $failed = 0
    $total = $Executables.Count
    # Read the firewall rules once, rather than once for every executable and
    # direction. This substantially speeds up larger folder operations.
    $existingRules = @(Get-BWRuleRecords)
    for ($index = 0; $index -lt $total; $index++) {
        $item = $Executables[$index]
        $percent = [math]::Round((($index + 1) / $total) * 100)
        Write-Progress -Activity 'Creating BarelyWall folder rules' -Status $item.Name -PercentComplete $percent
        $existingForProgram = @($existingRules | Where-Object {
            Test-BWSamePath -Left $_.Program -Right $item.FullName
        })
        $summary = Block-BWExecutable -Path $item.FullName -Directions @('Inbound', 'Outbound') -ExistingRecords $existingForProgram
        $created += $summary.Created
        $skipped += $summary.Skipped
        $failed += $summary.Failed
    }
    Write-Progress -Activity 'Creating BarelyWall folder rules' -Completed

    Write-BWLog -Level Information -Message "Processed $total executable(s) in folder '$FolderPath' (recurse: $Recurse)."
    return [pscustomobject]@{
        Folder      = Resolve-BWPath -Path $FolderPath
        Executables = $total
        Created     = $created
        Skipped     = $skipped
        Failed      = $failed
        Recurse     = $Recurse
    }
}
