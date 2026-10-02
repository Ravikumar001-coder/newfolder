$ErrorActionPreference = "Stop"

# ============================================================
# HELVIA WINDOWS INSTALLER
# ============================================================
#
# Architecture:
#
#   Windows Startup
#        |
#        v
#   PowerShell Hotkey Manager
#        |
#        +---- Ctrl + Alt + H
#        |
#        +---- Helvia already running -> focus/restore
#        |
#        +---- Helvia not running -> launch Helvia
#
# ============================================================

$AppName = "Helvia"

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Helvia"
$SupportDir = Join-Path $env:LOCALAPPDATA "Helvia"
$TempDir = Join-Path $env:TEMP "Helvia-Installer"

$ZipPath = Join-Path $TempDir "Helvia-Windows.zip"

$ReleaseUrl = "https://github.com/Ravikumar001-coder/newfolder/releases/download/v1.0.0/Helvia-Windows.zip"

$LogFile = Join-Path $SupportDir "Installer.log"
$HotkeyLogFile = Join-Path $SupportDir "HelviaHotkey.log"

# ============================================================
# Utility functions
# ============================================================

function Write-InstallerLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Line = "[$Timestamp] [$Level] $Message"

    Write-Host $Line

    try {
        if (-not (Test-Path $SupportDir)) {
            New-Item -ItemType Directory -Path $SupportDir -Force | Out-Null
        }

        Add-Content `
            -Path $LogFile `
            -Value $Line `
            -Encoding UTF8
    }
    catch {
        # Logging must never stop installation.
    }
}

function Fail-Installer {
    param(
        [string]$Message
    )

    Write-Host ""
    Write-Host "INSTALLATION FAILED" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    Write-Host ""

    Write-InstallerLog $Message "ERROR"

    throw $Message
}

# ============================================================
# Header
# ============================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "          HELVIA WINDOWS INSTALLER" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. Prepare installer
# ============================================================

Write-Host "[1/7] Preparing installer..." -ForegroundColor Yellow

try {

    if (-not (Test-Path $SupportDir)) {
        New-Item `
            -ItemType Directory `
            -Path $SupportDir `
            -Force | Out-Null
    }

    Write-InstallerLog "Starting Helvia installation."

    if (Test-Path $TempDir) {
        Write-InstallerLog "Removing previous temporary installer directory."

        Remove-Item `
            $TempDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    New-Item `
        -ItemType Directory `
        -Path $TempDir `
        -Force | Out-Null

    Write-InstallerLog "Temporary directory: $TempDir"
    Write-InstallerLog "Install directory: $InstallDir"

}
catch {
    Fail-Installer "Could not prepare installer directories. $($_.Exception.Message)"
}

# ============================================================
# 2. Download release
# ============================================================

Write-Host ""
Write-Host "[2/7] Downloading Helvia..." -ForegroundColor Yellow
Write-Host ""

try {

    Write-InstallerLog "Downloading Helvia from:"
    Write-InstallerLog $ReleaseUrl

    Invoke-WebRequest `
        -Uri $ReleaseUrl `
        -OutFile $ZipPath `
        -UseBasicParsing

    if (-not (Test-Path $ZipPath)) {
        Fail-Installer "Helvia download completed but ZIP file was not found."
    }

    $SizeMB = [math]::Round(
        (Get-Item $ZipPath).Length / 1MB,
        2
    )

    if ($SizeMB -lt 1) {
        Fail-Installer "Downloaded Helvia archive appears to be invalid or empty."
    }

    Write-Host "Downloaded: $SizeMB MB" -ForegroundColor Green

    Write-InstallerLog "Downloaded Helvia: $SizeMB MB"

}
catch {
    Fail-Installer "Helvia download failed. $($_.Exception.Message)"
}

# ============================================================
# 3. Install application
# ============================================================

Write-Host ""
Write-Host "[3/7] Installing Helvia..." -ForegroundColor Yellow

try {

    # --------------------------------------------------------
    # Stop ONLY previous hotkey manager processes.
    # Do NOT forcibly terminate Helvia itself.
    # --------------------------------------------------------

    Write-InstallerLog "Stopping old Helvia hotkey manager instances."

    Get-CimInstance Win32_Process `
        -Filter "Name='powershell.exe' OR Name='pwsh.exe'" `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like "*HelviaHotkey.ps1*"
        } |
        ForEach-Object {

            try {
                Stop-Process `
                    -Id $_.ProcessId `
                    -Force `
                    -ErrorAction SilentlyContinue

                Write-InstallerLog "Stopped old hotkey manager PID $($_.ProcessId)."
            }
            catch {
                Write-InstallerLog `
                    "Could not stop old hotkey manager PID $($_.ProcessId)." `
                    "WARN"
            }
        }

    Start-Sleep -Milliseconds 500

    # --------------------------------------------------------
    # Remove old installation
    # --------------------------------------------------------

    if (Test-Path $InstallDir) {

        Write-InstallerLog "Removing previous Helvia installation."

        Remove-Item `
            $InstallDir `
            -Recurse `
            -Force `
            -ErrorAction Stop
    }

    New-Item `
        -ItemType Directory `
        -Path $InstallDir `
        -Force | Out-Null

    Expand-Archive `
        -Path $ZipPath `
        -DestinationPath $InstallDir `
        -Force

    Write-InstallerLog "Helvia archive extracted."

}
catch {
    Fail-Installer "Could not install Helvia. $($_.Exception.Message)"
}

# ============================================================
# 4. Locate Helvia.exe
# ============================================================

Write-Host ""
Write-Host "[4/7] Locating Helvia executable..." -ForegroundColor Yellow

try {

    # --------------------------------------------------------
    # IMPORTANT:
    # Do NOT blindly select the first .exe.
    # --------------------------------------------------------

    $ExpectedExe = Join-Path $InstallDir "Helvia.exe"

    if (Test-Path $ExpectedExe) {

        $ExePath = (Resolve-Path $ExpectedExe).Path

        Write-InstallerLog "Found expected executable: $ExePath"

    }
    else {

        # Fallback search for Helvia.exe only.

        $Exe = Get-ChildItem `
            -Path $InstallDir `
            -Filter "Helvia.exe" `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $Exe) {
            Fail-Installer "Could not find Helvia.exe after extraction."
        }

        $ExePath = $Exe.FullName

        Write-InstallerLog "Found Helvia.exe through recursive search: $ExePath"
    }

    $ExeDirectory = Split-Path `
        -Parent `
        $ExePath

    $ExeName = Split-Path `
        -Leaf `
        $ExePath

    Write-Host ""
    Write-Host "Application:" -ForegroundColor Gray
    Write-Host $ExePath -ForegroundColor Green

}
catch {
    Fail-Installer "Could not locate Helvia.exe. $($_.Exception.Message)"
}

# ============================================================
# Verify executable
# ============================================================

if (-not (Test-Path $ExePath)) {
    Fail-Installer "Helvia.exe does not exist at $ExePath"
}

# ============================================================
# 5. Configure Ctrl + Alt + H
# ============================================================

Write-Host ""
Write-Host "[5/7] Configuring Ctrl + Alt + H..." -ForegroundColor Yellow

try {

    if (-not (Test-Path $SupportDir)) {
        New-Item `
            -ItemType Directory `
            -Path $SupportDir `
            -Force | Out-Null
    }

    $HotkeyScript = Join-Path `
        $SupportDir `
        "HelviaHotkey.ps1"

    # --------------------------------------------------------
    # Escape values for generated PowerShell script
    # --------------------------------------------------------

    $SafeExePath = $ExePath.Replace("'", "''")
    $SafeExeName = $ExeName.Replace("'", "''")
    $SafeLogFile = $HotkeyLogFile.Replace("'", "''")

    # --------------------------------------------------------
    # Generate hotkey manager
    # --------------------------------------------------------

    $HotkeyContent = @"
# ============================================================
# HELVIA GLOBAL HOTKEY MANAGER
# Ctrl + Alt + H
# ============================================================

`$ErrorActionPreference = "Continue"

`$ExePath = '$SafeExePath'
`$ExeName = '$SafeExeName'
`$LogFile = '$SafeLogFile'

# ============================================================
# Logging
# ============================================================

function Write-HelviaLog {
    param(
        [string]`$Message,
        [string]`$Level = "INFO"
    )

    try {

        `$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        `$Line = "[$Timestamp] [$Level] `$Message"

        Add-Content `
            -Path `$LogFile `
            -Value `$Line `
            -Encoding UTF8

    }
    catch {
        # Never allow logging failure to kill hotkey service.
    }
}

Write-HelviaLog "============================================================"
Write-HelviaLog "Helvia hotkey manager starting."
Write-HelviaLog "Executable: `$ExePath"

# ============================================================
# Validate executable
# ============================================================

if (-not (Test-Path `$ExePath)) {

    Write-HelviaLog `
        "Helvia executable does not exist: `$ExePath" `
        "ERROR"

    exit 1
}

# ============================================================
# Windows API
# ============================================================

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class HelviaHotkey
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(
        IntPtr hWnd,
        int id,
        uint fsModifiers,
        uint vk
    );

    [DllImport("user32.dll", SetLastError = true)]
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

    [DllImport("user32.dll")]
    public static extern bool IsWindow(
        IntPtr hWnd
    );

    [DllImport("user32.dll")]
    public static extern bool AllowSetForegroundWindow(
        int dwProcessId
    );

    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();
}

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

    [DllImport("user32.dll")]
    public static extern bool TranslateMessage(
        ref MSG lpMsg
    );

    [DllImport("user32.dll")]
    public static extern IntPtr DispatchMessage(
        ref MSG lpMsg
    );
}
'@

# ============================================================
# Constants
# ============================================================

# MOD_ALT       = 0x0001
# MOD_CONTROL   = 0x0002
# MOD_NOREPEAT  = 0x4000
# VK_H          = 0x48

`$MOD_ALT = 0x0001
`$MOD_CONTROL = 0x0002
`$MOD_NOREPEAT = 0x4000

`$VK_H = 0x48

`$HOTKEY_ID = 9001

`$MODIFIERS = `$MOD_CONTROL -bor `$MOD_ALT -bor `$MOD_NOREPEAT

# ============================================================
# Prevent duplicate hotkey manager instances
# ============================================================

try {

    `$MutexCreated = `$false

    `$Mutex = New-Object `
        System.Threading.Mutex(
            `$true,
            "Global\Helvia_CtrlAltH_Hotkey_Manager",
            [ref]`$MutexCreated
        )

    if (-not `$MutexCreated) {

        Write-HelviaLog `
            "Another Helvia hotkey manager is already running. Exiting." `
            "WARN"

        exit 0
    }

}
catch {

    Write-HelviaLog `
        "Could not create hotkey manager mutex: `$($_.Exception.Message)" `
        "ERROR"
}

# ============================================================
# Register Ctrl + Alt + H
# ============================================================

Write-HelviaLog "Registering Ctrl + Alt + H."

`$Registered = [HelviaHotkey]::RegisterHotKey(
    [IntPtr]::Zero,
    `$HOTKEY_ID,
    `$MODIFIERS,
    `$VK_H
)

if (-not `$Registered) {

    `$Win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

    Write-HelviaLog `
        "FAILED to register Ctrl + Alt + H. Win32 error: `$Win32Error" `
        "ERROR"

    Write-HelviaLog `
        "Another application may already own this global hotkey." `
        "ERROR"

    # Keep process alive briefly so startup logging is written.
    Start-Sleep -Seconds 2

    exit 1
}

Write-HelviaLog "Ctrl + Alt + H registered successfully."

# ============================================================
# Find Helvia window
# ============================================================

function Get-HelviaProcess {

    try {

        `$ProcessName = [System.IO.Path]::GetFileNameWithoutExtension(
            `$ExeName
        )

        `$Processes = Get-Process `
            -Name `$ProcessName `
            -ErrorAction SilentlyContinue

        foreach (`$Process in `$Processes) {

            if (`$Process.MainWindowHandle -ne [IntPtr]::Zero) {

                return `$Process
            }
        }

        return `$null
    }
    catch {

        Write-HelviaLog `
            "Error finding Helvia process: `$($_.Exception.Message)" `
            "ERROR"

        return `$null
    }
}

# ============================================================
# Focus existing Helvia
# ============================================================

function Show-HelviaWindow {

    param(
        [System.Diagnostics.Process]`$Process
    )

    try {

        if (-not `$Process) {
            return `$false
        }

        if (`$Process.HasExited) {
            return `$false
        }

        `$Handle = `$Process.MainWindowHandle

        if (`$Handle -eq [IntPtr]::Zero) {

            Write-HelviaLog `
                "Helvia process exists but has no main window yet." `
                "WARN"

            return `$false
        }

        # Restore minimized window.

        if ([HelviaHotkey]::IsIconic(`$Handle)) {

            Write-HelviaLog "Restoring minimized Helvia window."

            [HelviaHotkey]::ShowWindow(
                `$Handle,
                9
            ) | Out-Null
        }

        # Show window.

        [HelviaHotkey]::ShowWindow(
            `$Handle,
            5
        ) | Out-Null

        # Bring window to foreground.

        [HelviaHotkey]::SetForegroundWindow(
            `$Handle
        ) | Out-Null

        Write-HelviaLog "Helvia window focused."

        return `$true
    }
    catch {

        Write-HelviaLog `
            "Could not focus Helvia: `$($_.Exception.Message)" `
            "ERROR"

        return `$false
    }
}

# ============================================================
# Launch Helvia if not running
# ============================================================

function Start-Helvia {

    try {

        Write-HelviaLog "Helvia is not running. Starting Helvia."

        `$NewProcess = Start-Process `
            -FilePath `$ExePath `
            -WorkingDirectory (
                Split-Path -Parent `$ExePath
            ) `
            -PassThru

        Write-HelviaLog `
            "Helvia started. PID: `$(`$NewProcess.Id)"

        return `$NewProcess
    }
    catch {

        Write-HelviaLog `
            "FAILED to start Helvia: `$($_.Exception.Message)" `
            "ERROR"

        return `$null
    }
}

# ============================================================
# Handle Ctrl + Alt + H
# ============================================================

function Invoke-HelviaHotkey {

    Write-HelviaLog "Ctrl + Alt + H pressed."

    # --------------------------------------------------------
    # Look for existing Helvia process.
    # --------------------------------------------------------

    `$Existing = Get-HelviaProcess

    if (`$Existing) {

        Write-HelviaLog `
            "Existing Helvia process found. PID: `$(`$Existing.Id)"

        if (Show-HelviaWindow -Process `$Existing) {
            return
        }

        # Electron may still be starting.
        # Wait briefly for the main window.

        Write-HelviaLog `
            "Helvia process exists but window is not ready. Waiting."

        for (`$i = 0; `$i -lt 20; `$i++) {

            Start-Sleep -Milliseconds 250

            try {
                `$Existing.Refresh()
            }
            catch {
            }

            if (`$Existing.MainWindowHandle -ne [IntPtr]::Zero) {

                if (Show-HelviaWindow -Process `$Existing) {
                    return
                }
            }
        }

        Write-HelviaLog `
            "Existing Helvia process could not be focused." `
            "WARN"

        return
    }

    # --------------------------------------------------------
    # Helvia is not running.
    # --------------------------------------------------------

    `$Started = Start-Helvia

    if (-not `$Started) {
        return
    }

    # --------------------------------------------------------
    # Wait for Electron window.
    # --------------------------------------------------------

    for (`$i = 0; `$i -lt 40; `$i++) {

        Start-Sleep -Milliseconds 250

        try {
            `$Started.Refresh()
        }
        catch {
        }

        if (`$Started.MainWindowHandle -ne [IntPtr]::Zero) {

            if (Show-HelviaWindow -Process `$Started) {
                return
            }
        }
    }

    Write-HelviaLog `
        "Helvia started but main window was not detected within timeout." `
        "WARN"
}

# ============================================================
# Windows message loop
# ============================================================

try {

    Write-HelviaLog "Hotkey message loop started."

    while (`$true) {

        `$Msg = New-Object HelviaMessageLoop+MSG

        `$Result = [HelviaMessageLoop]::GetMessage(
            [ref]`$Msg,
            [IntPtr]::Zero,
            0,
            0
        )

        if (`$Result -eq 0) {
            Write-HelviaLog "Windows message loop received WM_QUIT."
            break
        }

        if (`$Result -eq -1) {

            Write-HelviaLog `
                "Windows message loop returned an error." `
                "ERROR"

            break
        }

        # WM_HOTKEY = 0x0312

        if (
            `$Msg.message -eq 0x0312 -and
            `$Msg.wParam.ToInt32() -eq `$HOTKEY_ID
        ) {

            Invoke-HelviaHotkey
        }

        [HelviaMessageLoop]::TranslateMessage(
            [ref]`$Msg
        ) | Out-Null

        [HelviaMessageLoop]::DispatchMessage(
            [ref]`$Msg
        ) | Out-Null
    }

}
catch {

    Write-HelviaLog `
        "Fatal hotkey manager error: `$($_.Exception.Message)" `
        "ERROR"

}
finally {

    Write-HelviaLog "Unregistering Ctrl + Alt + H."

    try {

        [HelviaHotkey]::UnregisterHotKey(
            [IntPtr]::Zero,
            `$HOTKEY_ID
        ) | Out-Null

    }
    catch {
    }

    try {

        if (`$Mutex) {
            `$Mutex.ReleaseMutex()
            `$Mutex.Dispose()
        }

    }
    catch {
    }

    Write-HelviaLog "Helvia hotkey manager stopped."
}
"@

    Set-Content `
        -Path $HotkeyScript `
        -Value $HotkeyContent `
        -Encoding UTF8 `
        -Force

    Write-InstallerLog "Hotkey manager created: $HotkeyScript"
    Write-InstallerLog "Hotkey log: $HotkeyLogFile"

}
catch {
    Fail-Installer "Could not create Helvia hotkey manager. $($_.Exception.Message)"
}

# ============================================================
# 6. Create shortcuts and startup
# ============================================================

Write-Host ""
Write-Host "[6/7] Creating shortcuts and startup..." -ForegroundColor Yellow

try {

    $Shell = New-Object -ComObject WScript.Shell

    # --------------------------------------------------------
    # Desktop shortcut
    # --------------------------------------------------------

    $DesktopPath = [Environment]::GetFolderPath("Desktop")

    $DesktopShortcut = Join-Path `
        $DesktopPath `
        "$AppName.lnk"

    if (Test-Path $DesktopShortcut) {
        Remove-Item `
            $DesktopShortcut `
            -Force `
            -ErrorAction SilentlyContinue
    }

    $Shortcut = $Shell.CreateShortcut(
        $DesktopShortcut
    )

    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = $ExeDirectory
    $Shortcut.Description = "Launch Helvia"

    $Shortcut.Save()

    Write-InstallerLog `
        "Desktop shortcut created: $DesktopShortcut"

    # --------------------------------------------------------
    # Start Menu shortcut
    # --------------------------------------------------------

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

    if (Test-Path $StartMenuShortcut) {
        Remove-Item `
            $StartMenuShortcut `
            -Force `
            -ErrorAction SilentlyContinue
    }

    $Shortcut = $Shell.CreateShortcut(
        $StartMenuShortcut
    )

    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = $ExeDirectory
    $Shortcut.Description = "Launch Helvia"

    $Shortcut.Save()

    Write-InstallerLog `
        "Start Menu shortcut created."

    # --------------------------------------------------------
    # Startup shortcut
    # --------------------------------------------------------

    $StartupDir = [Environment]::GetFolderPath("Startup")

    $StartupShortcut = Join-Path `
        $StartupDir `
        "Helvia Hotkey.lnk"

    # Remove old shortcut first.

    if (Test-Path $StartupShortcut) {

        Remove-Item `
            $StartupShortcut `
            -Force `
            -ErrorAction SilentlyContinue
    }

    # Use Windows PowerShell explicitly.

    $PowerShellPath = Join-Path `
        $env:SystemRoot `
        "System32\WindowsPowerShell\v1.0\powershell.exe"

    if (-not (Test-Path $PowerShellPath)) {

        Fail-Installer `
            "Windows PowerShell executable was not found at $PowerShellPath"
    }

    $Shortcut = $Shell.CreateShortcut(
        $StartupShortcut
    )

    $Shortcut.TargetPath = $PowerShellPath

    $Shortcut.Arguments =
        "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HotkeyScript`""

    $Shortcut.WorkingDirectory = $SupportDir

    $Shortcut.Description =
        "Helvia Ctrl + Alt + H Global Hotkey"

    $Shortcut.WindowStyle = 7

    $Shortcut.Save()

    Write-InstallerLog `
        "Startup hotkey shortcut created: $StartupShortcut"

}
catch {
    Fail-Installer "Could not create Helvia shortcuts/startup configuration. $($_.Exception.Message)"
}

# ============================================================
# 7. Start hotkey manager immediately
# ============================================================

Write-Host ""
Write-Host "[7/7] Starting Helvia hotkey service..." -ForegroundColor Yellow

try {

    # --------------------------------------------------------
    # Make absolutely sure an old hotkey manager isn't running.
    # --------------------------------------------------------

    Get-CimInstance Win32_Process `
        -Filter "Name='powershell.exe' OR Name='pwsh.exe'" `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like "*HelviaHotkey.ps1*"
        } |
        ForEach-Object {

            try {

                Stop-Process `
                    -Id $_.ProcessId `
                    -Force `
                    -ErrorAction SilentlyContinue

            }
            catch {
            }
        }

    Start-Sleep -Milliseconds 500

    # --------------------------------------------------------
    # Start hotkey manager.
    # --------------------------------------------------------

    $HotkeyProcess = Start-Process `
        -FilePath $PowerShellPath `
        -ArgumentList @(
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
            "-File",
            "`"$HotkeyScript`""
        ) `
        -WorkingDirectory $SupportDir `
        -WindowStyle Hidden `
        -PassThru

    Write-InstallerLog `
        "Started hotkey manager PID: $($HotkeyProcess.Id)"

    # --------------------------------------------------------
    # Give service time to initialize.
    # --------------------------------------------------------

    Start-Sleep -Seconds 2

    # --------------------------------------------------------
    # Verify process is still running.
    # --------------------------------------------------------

    $HotkeyRunning = Get-Process `
        -Id $HotkeyProcess.Id `
        -ErrorAction SilentlyContinue

    if (-not $HotkeyRunning) {

        Write-Host ""
        Write-Host "WARNING: Hotkey manager exited during startup." -ForegroundColor Red

        Write-InstallerLog `
            "Hotkey manager exited during startup." `
            "ERROR"

        if (Test-Path $HotkeyLogFile) {

            Write-Host ""
            Write-Host "Hotkey diagnostic log:" -ForegroundColor Yellow
            Write-Host $HotkeyLogFile -ForegroundColor Cyan
            Write-Host ""

            Get-Content `
                $HotkeyLogFile `
                -Tail 20
        }

        Write-Host ""
        Write-Host "Installation will continue, but Ctrl + Alt + H may not work." `
            -ForegroundColor Yellow
    }
    else {

        Write-Host "Hotkey manager started successfully." `
            -ForegroundColor Green

        Write-InstallerLog `
            "Hotkey manager is running successfully."
    }

}
catch {

    Write-InstallerLog `
        "Failed to start hotkey manager: $($_.Exception.Message)" `
        "ERROR"

    Write-Host ""
    Write-Host "WARNING: Could not start hotkey manager." -ForegroundColor Red
}

# ============================================================
# Cleanup
# ============================================================

try {

    if (Test-Path $TempDir) {

        Remove-Item `
            $TempDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Write-InstallerLog "Temporary installer files cleaned."

}
catch {

    Write-InstallerLog `
        "Temporary cleanup failed: $($_.Exception.Message)" `
        "WARN"
}

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
Write-Host "Hotkey log:"
Write-Host $HotkeyLogFile -ForegroundColor Gray

Write-Host ""
Write-Host "Installer log:"
Write-Host $LogFile -ForegroundColor Gray

Write-Host ""
Write-Host "Starting Helvia..." -ForegroundColor Yellow

try {

    # --------------------------------------------------------
    # Before launching, check whether Helvia is already running.
    # --------------------------------------------------------

    $ProcessName = [System.IO.Path]::GetFileNameWithoutExtension(
        $ExeName
    )

    $ExistingHelvia = Get-Process `
        -Name $ProcessName `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.MainWindowHandle -ne [IntPtr]::Zero
        } |
        Select-Object -First 1

    if ($ExistingHelvia) {

        Write-InstallerLog `
            "Helvia is already running. Reusing existing process."

    }
    else {

        $StartedHelvia = Start-Process `
            -FilePath $ExePath `
            -WorkingDirectory $ExeDirectory `
            -PassThru

        Write-InstallerLog `
            "Helvia started after installation. PID: $($StartedHelvia.Id)"
    }

}
catch {

    Write-InstallerLog `
        "Helvia could not be launched automatically: $($_.Exception.Message)" `
        "ERROR"

    Write-Host ""
    Write-Host "WARNING: Helvia was installed but could not be launched automatically." `
        -ForegroundColor Yellow

    Write-Host "You can launch it from the Desktop shortcut." `
        -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""

Write-Host "If Ctrl + Alt + H does not work, check:" -ForegroundColor Yellow
Write-Host $HotkeyLogFile -ForegroundColor Cyan
Write-Host ""
```
