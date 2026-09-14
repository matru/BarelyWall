$script:BWGroup = 'BarelyWall'

function Assert-BWWindows {
    if ($env:OS -ne 'Windows_NT') {
        throw 'BarelyWall manages Windows Firewall and must be run on Windows.'
    }
}

function Initialize-BWWorkspace {
    param([Parameter(Mandatory)][string]$RootPath)

    $paths = [ordered]@{
        Root       = $RootPath
        Data       = Join-Path $RootPath 'Data'
        Logs       = Join-Path $RootPath 'Data/Logs'
        Exports    = Join-Path $RootPath 'Exports'
        Settings   = Join-Path $RootPath 'Data/Settings.json'
        RecentApps = Join-Path $RootPath 'Data/RecentApps.json'
    }

    foreach ($directory in @($paths.Data, $paths.Logs, $paths.Exports)) {
        if (-not (Test-Path -LiteralPath $directory)) {
            $null = New-Item -ItemType Directory -Path $directory -Force
        }
    }

    $Global:BWPaths = [pscustomobject]$paths
    if (-not (Test-Path -LiteralPath $paths.Settings)) {
        $settings = [ordered]@{
            Version          = '1.0.0'
            RulePrefix       = 'BW -'
            RecentMaxItems   = 15
            LogRetentionDays = 30
        }
        $settings | ConvertTo-Json | Set-Content -LiteralPath $paths.Settings -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $paths.RecentApps)) {
        '[]' | Set-Content -LiteralPath $paths.RecentApps -Encoding UTF8
    }

    # Keep settings in memory for this session. This avoids repeatedly reading
    # Settings.json during bulk operations.
    $Global:BWSettingsCache = Get-Content -LiteralPath $paths.Settings -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Get-BWPath {
    param([Parameter(Mandatory)][ValidateSet('Root', 'Data', 'Logs', 'Exports', 'Settings', 'RecentApps')][string]$Name)

    if (-not $Global:BWPaths) { throw 'BarelyWall has not been initialized.' }
    return $Global:BWPaths.$Name
}

function Get-BWSettings {
    if ($Global:BWSettingsCache) { return $Global:BWSettingsCache }

    $path = Get-BWPath -Name Settings
    try {
        $settings = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $Global:BWSettingsCache = $settings
        return $settings
    }
    catch {
        throw "Unable to read settings: $($_.Exception.Message)"
    }
}

function Get-BWRulePrefix {
    $settings = Get-BWSettings
    if ([string]::IsNullOrWhiteSpace($settings.RulePrefix)) { return 'BW -' }
    return [string]$settings.RulePrefix
}

function Get-BWVersion {
    $settings = Get-BWSettings
    return [string]$settings.Version
}

function Get-BWRuleGroup {
    return $script:BWGroup
}

function Assert-BWFirewallSupport {
    try {
        Import-Module NetSecurity -ErrorAction Stop
        $enabledType = 'Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled' -as [type]
        if ($null -eq $enabledType) {
            throw 'The NetSecurity Enabled type is unavailable.'
        }
    }
    catch {
        throw "The Windows NetSecurity module is unavailable. Details: $($_.Exception.Message)"
    }
}

function ConvertTo-BWFirewallEnabledValue {
    param([Parameter(Mandatory)][ValidateSet('True', 'False')][string]$State)

    $enabledType = 'Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled' -as [type]
    if ($null -eq $enabledType) {
        Assert-BWFirewallSupport
        $enabledType = 'Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled' -as [type]
    }
    return [System.Enum]::Parse($enabledType, $State, $true)
}

function Test-BWAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Resolve-BWPath {
    param([Parameter(Mandatory)][string]$Path)

    $expandedPath = Expand-BWPathVariables -Path $Path
    $resolved = Resolve-Path -LiteralPath $expandedPath -ErrorAction Stop | Select-Object -First 1
    return $resolved.ProviderPath
}

function Expand-BWPathVariables {
    param([AllowNull()][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
}

function ConvertTo-BWPortablePath {
    param([Parameter(Mandatory)][string]$Path)

    try {
        $fullPath = Resolve-BWPath -Path $Path
    }
    catch {
        # Preserve an orphaned rule's stored path rather than failing an export.
        return Expand-BWPathVariables -Path $Path
    }
    $userProfile = [Environment]::ExpandEnvironmentVariables('%USERPROFILE%').TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($userProfile)) { return $fullPath }

    $profileWithSeparator = $userProfile + [IO.Path]::DirectorySeparatorChar
    if ($fullPath.StartsWith($profileWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $fullPath.Substring($profileWithSeparator.Length)
        return '%USERPROFILE%' + [IO.Path]::DirectorySeparatorChar + $relativePath
    }
    if ($fullPath.Equals($userProfile, [StringComparison]::OrdinalIgnoreCase)) {
        return '%USERPROFILE%'
    }
    return $fullPath
}

function Test-BWExecutablePath {
    param([AllowNull()][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $expandedPath = Expand-BWPathVariables -Path $Path
    return (Test-Path -LiteralPath $expandedPath -PathType Leaf) -and ([IO.Path]::GetExtension($expandedPath) -ieq '.exe')
}

function Get-BWExecutablesInFolder {
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [bool]$Recurse = $true
    )

    $expandedFolderPath = Expand-BWPathVariables -Path $FolderPath
    if (-not (Test-Path -LiteralPath $expandedFolderPath -PathType Container)) {
        throw "Folder does not exist: $FolderPath"
    }

    return @(Get-ChildItem -LiteralPath $expandedFolderPath -Filter '*.exe' -File -Recurse:$Recurse -ErrorAction Stop | Sort-Object FullName)
}

function ConvertTo-BWComparablePath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        return (Resolve-BWPath -Path $Path).TrimEnd('\', '/').ToLowerInvariant()
    }
    catch {
        return [Environment]::ExpandEnvironmentVariables($Path).Trim().TrimEnd('\', '/').ToLowerInvariant()
    }
}

function Test-BWSamePath {
    param([AllowNull()][string]$Left, [AllowNull()][string]$Right)

    return (ConvertTo-BWComparablePath $Left) -eq (ConvertTo-BWComparablePath $Right)
}

function Test-BWPathInFolder {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$FolderPath
    )

    $candidate = ConvertTo-BWComparablePath $Path
    $folder = ConvertTo-BWComparablePath $FolderPath
    if (-not $candidate -or -not $folder) { return $false }
    if ($candidate -eq $folder) { return $true }

    $root = [IO.Path]::GetPathRoot($folder)
    if ($root -and $folder.Length -eq $root.TrimEnd('\', '/').Length) {
        return $candidate.StartsWith($root.ToLowerInvariant(), [StringComparison]::OrdinalIgnoreCase)
    }
    return $candidate.StartsWith($folder + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-BWExecutableDisplayName {
    param([Parameter(Mandatory)][string]$Path)

    $name = Split-Path -Path $Path -Leaf
    if ([string]::IsNullOrWhiteSpace($name)) { return $Path }
    return $name
}
