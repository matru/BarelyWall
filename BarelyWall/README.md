# BarelyWall v1.0.5

BarelyWall is a standalone, menu-driven PowerShell utility for creating and maintaining program-specific Windows Firewall block rules. It deliberately manages only rules whose names begin with `BW -`, leaving every other firewall rule alone.

## Run it

1. Copy the `BarelyWall` folder to a suitable location on a Windows PC.
2. Open **Windows PowerShell** or **PowerShell 7** as **Administrator**.
3. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\BarelyWall.ps1
```

The script needs administrator permission because Windows Firewall does.

## What it manages

- Block an executable inbound, outbound, or both.
- Block every `.exe` in a folder, with optional subfolders.
- Remove rules for an executable or folder, or remove rules for deleted executables.
- Enable or disable all BarelyWall rules, or the rules for one executable.
- Check status, search, and list rules.
- Export and import rules as JSON. Paths below the current user's profile are
  stored portably, for example `%USERPROFILE%\Downloads\TestFolder\Mario.exe`.
- Browse for paths or enter them manually; recently blocked applications are remembered.

Rules are named like `BW - Block Inbound - Discord.exe` and are tagged with the **BarelyWall** group. Duplicate rules for the same executable and direction are skipped.

## Data folders

- `Data/Settings.json` stores user-adjustable settings.
- `Data/RecentApps.json` stores recently used executable paths.
- `Data/Logs` contains daily activity logs.
- `Exports` receives rule backups.

An import never creates a rule for a missing executable and always skips an existing matching rule. The menu asks before any removal, bulk modification, or import.

When entering a path manually in a normal PowerShell console, press **Tab** to complete existing file and folder names. Repeated Tab presses cycle matching entries.
