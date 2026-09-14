function Write-BWLog {
    param(
        [Parameter(Mandatory)][ValidateSet('Information', 'Warning', 'Error')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    try {
        $logDirectory = Get-BWPath -Name Logs
        $logFile = Join-Path $logDirectory ("BarelyWall-{0:yyyy-MM-dd}.log" -f (Get-Date))
        $line = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Level.ToUpperInvariant(), $Message
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    }
    catch {
        # Logging must never stop a firewall operation.
    }
}
