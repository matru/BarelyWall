function Get-BWRecentApplications {
    $path = Get-BWPath -Name RecentApps
    try {
        $content = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) { return @() }
        $items = @(ConvertFrom-Json -InputObject $content -ErrorAction Stop)
        return @($items | Where-Object {
            $null -ne $_ -and
            $null -ne $_.PSObject.Properties['Path'] -and
            -not [string]::IsNullOrWhiteSpace([string]$_.Path)
        })
    }
    catch {
        Write-BWLog -Level Warning -Message "Unable to read recent applications: $($_.Exception.Message)"
        return @()
    }
}

function Add-BWRecentApplication {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-BWExecutablePath -Path $Path)) { return }
    $normalizedPath = Resolve-BWPath -Path $Path
    $existing = @(Get-BWRecentApplications | Where-Object { -not (Test-BWSamePath $_.Path $normalizedPath) })
    $entry = [pscustomobject]@{
        Path       = $normalizedPath
        LastUsedAt = (Get-Date).ToString('o')
    }
    $settings = Get-BWSettings
    $maxItems = [int]$settings.RecentMaxItems
    $items = @($entry) + $existing | Select-Object -First $maxItems
    $items | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Get-BWPath -Name RecentApps) -Encoding UTF8
}

function Select-BWRecentApplication {
    $items = @(Get-BWRecentApplications | Where-Object {
        Test-BWExecutablePath -Path ([string]$_.Path)
    })
    if ($items.Count -eq 0) {
        Write-BWMessage -Text 'No recent applications are available.' -Type Warning
        return $null
    }

    Write-Host ''
    for ($index = 0; $index -lt $items.Count; $index++) {
        Write-Host (' [{0}] {1}' -f ($index + 1), $items[$index].Path) -ForegroundColor DarkGray
    }
    Write-Host ' [0] Cancel' -ForegroundColor DarkGray
    $choice = Read-Host 'Recent application'
    if ($choice -notmatch '^\d+$') { return $null }
    $selected = [int]$choice
    if ($selected -lt 1 -or $selected -gt $items.Count) { return $null }

    $path = [string]$items[$selected - 1].Path
    Add-BWRecentApplication -Path $path
    return $path
}
