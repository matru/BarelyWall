# BarelyWall v1.0.5

BarelyWall is a standalone, menu-driven PowerShell utility for creating and maintaining program-specific Windows Firewall block rules. It deliberately manages only rules whose names begin with `BW -`, leaving every other firewall rule alone.

The program does not replace Windows Firewall or run its own network filter; it simply provides an easier way to manage Windows Firewall rules, which are enforced by Windows through the Windows Filtering Platform. It uses Windows’ built-in firewall management commands to create, find, enable, disable, export, and remove program-specific rules. Every rule it creates is labeled with the BW - prefix, allowing it to manage only its own rules without affecting unrelated Windows Firewall settings.

BarelyWall is not a background service or always-running process. It only uses system resources while you have the utility open and are making changes; once closed, it adds no ongoing CPU, memory, or network overhead. Windows Firewall and the Windows Filtering Platform enforce the saved rules independently.

![img](/BarelyWall.png)

## Run it

1. Move the `BarelyWall` folder to your preferred location.
2. Open **Windows PowerShell** or **Terminal** as **Administrator**, `cd` to the directory.
3. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\BarelyWall.ps1
```

The script needs administrator permission because Windows Firewall does.

## What it manages

Rules are named like `BW - Block Inbound - Discord.exe` and are tagged with the **BarelyWall** group. Duplicate rules for the same executable and direction are skipped.

- Block an executable inbound, outbound, or both.
- Block every `.exe` in a folder, with optional subfolders.
- Browse for applications and folders, or enter paths manually (tab-completion supported); recently blocked applications are remembered.
- Remove rules for an executable or folder, or remove rules for deleted executables.
- Enable or disable all BarelyWall rules, or the rules for one executable.
- Check status, search, and list rules.
- Export and import rules as JSON. Paths below the current user's profile are
  stored portably, for example `%USERPROFILE%\Downloads\Test_Folder\Test.exe`.
- Remove orphaned rules for applications that no longer exist
- Keep activity logs

## Data folders

- `Data/RecentApps.json` stores recently used executable paths.
- `Data/Logs` contains daily activity logs.
- `Exports` receives rule backups.

An import never creates a rule for a missing executable and always skips an existing matching rule. The menu asks before any removal, bulk modification, or import.
