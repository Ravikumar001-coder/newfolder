$ErrorActionPreference = "Stop"

# ============================================================
# Helvia Windows Installer
# ============================================================

$AppName = "Helvia"

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Helvia"
$SupportDir = Join-Path $env:LOCALAPPDATA "Helvia"
$TempDir = Join-Path $env:TEMP "Helvia-Installer"

$ZipPath = Join-Path $TempDir "Helvia-Windows.zip"

$ReleaseUrl = "https://github.com/Ravikumar001-coder/newfolder/releases/download/v1.0.0/Helvia-Windows.zip"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "          HELVIA WINDOWS INSTALLER" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. Prepare temporary directory
# ============================================================

Write-Host "[1/7] Preparing installer..." -ForegroundColor Yellow

if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# ============================================================
# 2. Download Release
# ============================================================

Write-Host ""
Write-Host "[2/7] Downloading Helvia..." -ForegroundColor Yellow
Write-Host ""

Invoke-WebRequest `
    -Uri $ReleaseUrl `
    -OutFile $ZipPath `
    -UseBasicParsing

if (-not (Test-Path $ZipPath)) {
    throw "Helvia download failed."
}

$SizeMB = [math]::Round(
    (Get-Item $ZipPath).Length / 1MB,
    2
)

Write-Host "Downloaded: $SizeMB MB" -ForegroundColor Green

# ============================================================
# 3. Install application
# ============================================================

Write-Host ""
Write-Host "[3/7] Installing Helvia..." -ForegroundColor Yellow

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

Expand-Archive `
    -Path $ZipPath `
    -DestinationPath $InstallDir `
    -Force

# ============================================================
# 4. Find application executable
# ============================================================

Write-Host ""
Write-Host "[4/7] Locating Helvia executable..." -ForegroundColor Yellow

$Exe = Get-ChildItem `
    -Path $InstallDir `
    -Filter "*.exe" `
    -Recurse `
    -File |
    Select-Object -First 1

if (-not $Exe) {
    throw "Could not find a Helvia executable after extraction."
}

$ExePath = $Exe.FullName
$ExeDirectory = $Exe.DirectoryName
$ExeName = $Exe.Name

Write-Host ""
Write-Host "Application:" -ForegroundColor Gray
Write-Host $ExePath -ForegroundColor Green

# ============================================================
# 5. Create Hotkey Manager
# ============================================================

Write-Host ""
Write-Host "[5/7] Configuring Ctrl + Alt + H..." -ForegroundColor Yellow

if (Test-Path $SupportDir) {
    Remove-Item $SupportDir -Recurse -Force
}

New-Item -ItemType Directory -Path $SupportDir -Force | Out-Null

$HotkeyScript = Join-Path $SupportDir "HelviaHotkey.ps1"

# Escape values for PowerShell-generated script
$SafeExePath = $ExePath.Replace("'", "''")
$SafeExeName = $ExeName.Replace("'", "''")

$HotkeyContent = @"
# ============================================================
# Helvia Global Hotkey Manager
# Ctrl + Alt + H
# ============================================================

`$ErrorActionPreference = "SilentlyContinue"

`$ExePath = '$SafeExePath'
`$ExeName = '$SafeExeName'

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class HelviaHotkey
{
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(
        IntPtr hWnd,
        int id,
        uint fsModifiers,
        uint vk
    );

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(
        IntPtr hWnd,
        int id
    );

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(
        IntPtr hWnd,
        int nCmdShow
    );

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(
        IntPtr hWnd
    );

    [DllImport("user32.dll")]
    public static extern bool IsIconic(
        IntPtr hWnd
    );
}
'@

# ------------------------------------------------------------
# Constants
# ------------------------------------------------------------

# MOD_ALT   = 0x0001
# MOD_CONTROL = 0x0002
# VK_H = 0x48

`$MOD_ALT = 0x0001
`$MOD_CONTROL = 0x0002
`$VK_H = 0x48

`$HOTKEY_ID = 9001

# ------------------------------------------------------------
# Register Ctrl + Alt + H
# ------------------------------------------------------------

$Registered = [HelviaHotkey]::RegisterHotKey(
    [IntPtr]::Zero,
    `$HOTKEY_ID,
    `$MOD_CONTROL -bor `$MOD_ALT,
    `$VK_H
)

if (-not `$Registered) {
    exit
}

# ------------------------------------------------------------
# Message loop
# ------------------------------------------------------------

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class HelviaMessageLoop
{
    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int ptX;
        public int ptY;
    }

    [DllImport("user32.dll")]
    public static extern int GetMessage(
        out MSG lpMsg,
        IntPtr hWnd,
        uint wMsgFilterMin,
        uint wMsgFilterMax
    );
}
'@

try {

    while (`$true) {

        `$msg = New-Object HelviaMessageLoop+MSG

        `$result = [HelviaMessageLoop]::GetMessage(
            [ref]`$msg,
            [IntPtr]::Zero,
            0,
            0
        )

        if (`$result -eq 0 -or `$result -eq -1) {
            break
        }

        # WM_HOTKEY = 0x0312
        if (`$msg.message -eq 0x0312 -and `$msg.wParam.ToInt32() -eq `$HOTKEY_ID) {

            # ------------------------------------------------
            # Find existing Helvia process
            # ------------------------------------------------

            `$processName = [System.IO.Path]::GetFileNameWithoutExtension(`$ExeName)

            `$existing = Get-Process -Name `$processName -ErrorAction SilentlyContinue |
                Where-Object {
                    `$_.MainWindowHandle -ne [IntPtr]::Zero
                } |
                Select-Object -First 1

            if (`$existing) {

                `$handle = `$existing.MainWindowHandle

                # Restore minimized window
                if ([HelviaHotkey]::IsIconic(`$handle)) {
                    [HelviaHotkey]::ShowWindow(`$handle, 9) | Out-Null
                }

                # Bring Helvia to foreground
                [HelviaHotkey]::SetForegroundWindow(`$handle) | Out-Null

            }
            else {

                # ------------------------------------------------
                # Helvia is not running -> launch it
                # ------------------------------------------------

                Start-Process `
                    -FilePath `$ExePath `
                    -WorkingDirectory ([System.IO.Path]::GetDirectoryName(`$ExePath))
            }
        }
    }

}
finally {

    [HelviaHotkey]::UnregisterHotKey(
        [IntPtr]::Zero,
        `$HOTKEY_ID
    ) | Out-Null
}
"@

Set-Content `
    -Path $HotkeyScript `
    -Value $HotkeyContent `
    -Encoding UTF8

# ============================================================
# 6. Create shortcuts
# ============================================================

Write-Host ""
Write-Host "[6/7] Creating shortcuts and startup..." -ForegroundColor Yellow

$Shell = New-Object -ComObject WScript.Shell

# ------------------------------------------------------------
# Desktop shortcut
# ------------------------------------------------------------

$DesktopPath = [Environment]::GetFolderPath("Desktop")
$DesktopShortcut = Join-Path $DesktopPath "$AppName.lnk"

$Shortcut = $Shell.CreateShortcut($DesktopShortcut)
$Shortcut.TargetPath = $ExePath
$Shortcut.WorkingDirectory = $ExeDirectory
$Shortcut.Description = "Launch Helvia"
$Shortcut.Save()

# ------------------------------------------------------------
# Start Menu shortcut
# ------------------------------------------------------------

$StartMenuDir = Join-Path `
    $env:APPDATA `
    "Microsoft\Windows\Start Menu\Programs"

New-Item `
    -ItemType Directory `
    -Path $StartMenuDir `
    -Force | Out-Null

$StartMenuShortcut = Join-Path `
    $StartMenuDir `
    "$AppName.lnk"

$Shortcut = $Shell.CreateShortcut($StartMenuShortcut)
$Shortcut.TargetPath = $ExePath
$Shortcut.WorkingDirectory = $ExeDirectory
$Shortcut.Description = "Launch Helvia"
$Shortcut.Save()

# ------------------------------------------------------------
# Startup shortcut for hotkey manager
# ------------------------------------------------------------

$StartupDir = [Environment]::GetFolderPath("Startup")

$StartupShortcut = Join-Path `
    $StartupDir `
    "Helvia Hotkey.lnk"

$PowerShellPath = (Get-Command powershell.exe).Source

$Shortcut = $Shell.CreateShortcut($StartupShortcut)

$Shortcut.TargetPath = $PowerShellPath

$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HotkeyScript`""

$Shortcut.WorkingDirectory = $SupportDir

$Shortcut.Description = "Helvia Ctrl + Alt + H Hotkey"

$Shortcut.WindowStyle = 7

$Shortcut.Save()

# ============================================================
# 7. Start Hotkey Manager immediately
# ============================================================

Write-Host ""
Write-Host "[7/7] Starting Helvia hotkey service..." -ForegroundColor Yellow

Start-Process `
    -FilePath $PowerShellPath `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HotkeyScript`"" `
    -WindowStyle Hidden

# Cleanup
Remove-Item $TempDir -Recurse -Force

# ============================================================
# Launch Helvia
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "       HELVIA INSTALLED SUCCESSFULLY" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

Write-Host "Installed to:"
Write-Host $InstallDir -ForegroundColor Cyan

Write-Host ""
Write-Host "Global hotkey:"
Write-Host "Ctrl + Alt + H" -ForegroundColor Cyan

Write-Host ""
Write-Host "Starting Helvia..." -ForegroundColor Yellow

Start-Process `
    -FilePath $ExePath `
    -WorkingDirectory $ExeDirectory

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""