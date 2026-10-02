$ErrorActionPreference = "Stop"

# ============================================================
# HELVIA WINDOWS INSTALLER
# ============================================================

$InstallDir      = Join-Path $env:LOCALAPPDATA "Programs\Helvia"
$SupportDir      = Join-Path $env:LOCALAPPDATA "Helvia"
$HotkeyScript    = Join-Path $SupportDir "HelviaHotkey.ps1"
$HotkeyLogFile   = Join-Path $SupportDir "HelviaHotkey.log"

$ReleaseUrl      = "https://github.com/Ravikumar001-coder/newfolder/releases/download/v1.0.0/Helvia-Windows.zip"
$ZipPath         = Join-Path $env:TEMP "Helvia-Windows.zip"
$ExtractDir      = Join-Path $env:TEMP "Helvia-Extract"

$ExeName         = "Helvia.exe"

# ------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------

function Write-InstallerLog {
    param(
        [string]$Message
    )

    Write-Host "[Helvia] $Message"
}

# ------------------------------------------------------------
# HEADER
# ------------------------------------------------------------

Clear-Host

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "          HELVIA WINDOWS INSTALLER" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# 1. PREPARE DIRECTORIES
# ------------------------------------------------------------

Write-Host "[1/7] Preparing installer..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $SupportDir -Force | Out-Null

if (Test-Path $ExtractDir) {
    Remove-Item $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null

# ------------------------------------------------------------
# 2. DOWNLOAD RELEASE
# ------------------------------------------------------------

Write-Host ""
Write-Host "[2/7] Downloading Helvia..." -ForegroundColor Yellow

try {
    Invoke-WebRequest `
        -Uri $ReleaseUrl `
        -OutFile $ZipPath `
        -UseBasicParsing

    if (-not (Test-Path $ZipPath)) {
        throw "Helvia ZIP was not downloaded."
    }

    $ZipSize = (Get-Item $ZipPath).Length

    if ($ZipSize -lt 100000) {
        throw "Downloaded Helvia ZIP appears to be invalid or incomplete."
    }

    Write-InstallerLog "Download completed."
}
catch {
    Write-Host ""
    Write-Host "ERROR: Failed to download Helvia." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 3. STOP OLD HELVIA + HOTKEY MANAGER
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3/7] Stopping previous Helvia processes..." -ForegroundColor Yellow

# Stop old hotkey managers
try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like "*HelviaHotkey.ps1*"
        } |
        ForEach-Object {
            try {
                Write-InstallerLog "Stopping old hotkey manager PID $($_.ProcessId)"
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
            catch {}
        }
}
catch {}

# Small delay so the old mutex/process can disappear
Start-Sleep -Milliseconds 500

# ------------------------------------------------------------
# EXTRACT HELVIA
# ------------------------------------------------------------

Write-InstallerLog "Extracting Helvia..."

try {
    Expand-Archive `
        -Path $ZipPath `
        -DestinationPath $ExtractDir `
        -Force
}
catch {
    Write-Host "ERROR: Failed to extract Helvia." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# FIND HELVIA.EXE
# ------------------------------------------------------------

$FoundExe = Get-ChildItem `
    -Path $ExtractDir `
    -Filter $ExeName `
    -File `
    -Recurse `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $FoundExe) {
    Write-Host ""
    Write-Host "ERROR: Helvia.exe was not found in the release ZIP." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# INSTALL FILES
# ------------------------------------------------------------

Write-InstallerLog "Installing Helvia to $InstallDir"

try {
    if (Test-Path $InstallDir) {
        Get-ChildItem $InstallDir -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Copy-Item `
        -Path (Join-Path $FoundExe.Directory.FullName "*") `
        -Destination $InstallDir `
        -Recurse `
        -Force
}
catch {
    Write-Host ""
    Write-Host "ERROR: Failed to install Helvia." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

$HelviaExe = Join-Path $InstallDir $ExeName

if (-not (Test-Path $HelviaExe)) {
    Write-Host ""
    Write-Host "ERROR: Installed Helvia.exe could not be found." -ForegroundColor Red
    exit 1
}

Write-InstallerLog "Helvia installed successfully."

# ------------------------------------------------------------
# 4. CREATE HOTKEY MANAGER
# ------------------------------------------------------------

Write-Host ""
Write-Host "[4/7] Installing Ctrl + Alt + H hotkey manager..." -ForegroundColor Yellow

$HotkeyContent = @"
`$ErrorActionPreference = "Continue"

# ============================================================
# HELVIA HOTKEY MANAGER
# Ctrl + Alt + H
# ============================================================

`$ExePath      = "$HelviaExe"
`$ExeName      = "$ExeName"
`$LogFile      = "$HotkeyLogFile"
`$MutexName    = "Global\Helvia_CtrlAltH_Hotkey_Manager"
`$HotkeyId     = 9001

`$SupportDirectory = Split-Path -Parent `$LogFile

if (-not (Test-Path `$SupportDirectory)) {
    New-Item -ItemType Directory -Path `$SupportDirectory -Force | Out-Null
}

# ------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------

function Write-HelviaLog {
    param(
        [string]`$Message,
        [string]`$Level = "INFO"
    )

    try {
        `$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        `$LogDirectory = Split-Path -Parent `$LogFile

        if (-not (Test-Path `$LogDirectory)) {
            New-Item -ItemType Directory -Path `$LogDirectory -Force | Out-Null
        }

        `$LogLine = "[`$Timestamp] [`$Level] `$Message"

        Add-Content -Path `$LogFile -Value `$LogLine -ErrorAction SilentlyContinue
    }
    catch {
        # Never allow logging failure to terminate the hotkey manager.
    }
}

# ------------------------------------------------------------
# WIN32 API
# ------------------------------------------------------------

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class HelviaHotkey
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool RegisterHotKey(
        IntPtr hWnd,
        int id,
        uint fsModifiers,
        uint vk
    );

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool UnregisterHotKey(
        IntPtr hWnd,
        int id
    );

    [DllImport("user32.dll", SetLastError=true)]
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
    public static extern bool BringWindowToTop(
        IntPtr hWnd
    );

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool IsWindow(
        IntPtr hWnd
    );

    [DllImport("user32.dll")]
    public static extern bool IsIconic(
        IntPtr hWnd
    );

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(
        IntPtr hWnd,
        out uint processId
    );

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(
        IntPtr hWnd
    );

    public delegate bool EnumWindowsProc(
        IntPtr hWnd,
        IntPtr lParam
    );

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(
        EnumWindowsProc lpEnumFunc,
        IntPtr lParam
    );
}
'@

# ------------------------------------------------------------
# SINGLE INSTANCE
# ------------------------------------------------------------

try {
    `$CreatedNew = `$false

    `$Mutex = New-Object System.Threading.Mutex(
        `$true,
        `$MutexName,
        [ref]`$CreatedNew
    )

    if (-not `$CreatedNew) {
        Write-HelviaLog "Another Helvia hotkey manager is already running."
        exit 0
    }
}
catch {
    Write-HelviaLog "Could not create mutex: `$(`$_.Exception.Message)" "WARN"
}

# ------------------------------------------------------------
# PROCESS HELPERS
# ------------------------------------------------------------

function Get-HelviaProcesses {

    try {

        `$ProcessName = [System.IO.Path]::GetFileNameWithoutExtension(`$ExeName)

        return @(
            Get-Process `
                -Name `$ProcessName `
                -ErrorAction SilentlyContinue
        )

    }
    catch {

        Write-HelviaLog `
            "Error finding Helvia processes: `$(`$_.Exception.Message)" `
            "ERROR"

        return @()
    }
}

# ------------------------------------------------------------
# FIND WINDOWS BELONGING TO HELVIA
# ------------------------------------------------------------

function Find-HelviaWindow {

    param(
        [System.Diagnostics.Process]`$Process
    )

    if (-not `$Process) {
        return [IntPtr]::Zero
    }

    if (`$Process.HasExited) {
        return [IntPtr]::Zero
    }

    try {
        `$Process.Refresh()

        if (`$Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return `$Process.MainWindowHandle
        }
    }
    catch {}

    `$Result = [IntPtr]::Zero
    `$TargetPid = `$Process.Id

    `$Callback = [HelviaHotkey+EnumWindowsProc]{
        param(
            [IntPtr]`$Hwnd,
            [IntPtr]`$LParam
        )

        try {

            if (-not [HelviaHotkey]::IsWindowVisible(`$Hwnd)) {
                return `$true
            }

            [uint32]`$WindowPid = 0

            [HelviaHotkey]::GetWindowThreadProcessId(
                `$Hwnd,
                [ref]`$WindowPid
            ) | Out-Null

            if (`$WindowPid -eq `$TargetPid) {
                `$script:HelviaWindowResult = `$Hwnd
                return `$false
            }

        }
        catch {}

        return `$true
    }

    `$script:HelviaWindowResult = [IntPtr]::Zero

    try {
        [HelviaHotkey]::EnumWindows(
            `$Callback,
            [IntPtr]::Zero
        ) | Out-Null
    }
    catch {}

    return `$script:HelviaWindowResult
}

# ------------------------------------------------------------
# FOCUS HELVIA
# ------------------------------------------------------------

function Show-HelviaWindow {

    param(
        [System.Diagnostics.Process]`$Process
    )

    if (-not `$Process) {
        return `$false
    }

    if (`$Process.HasExited) {
        return `$false
    }

    Write-HelviaLog "Attempting to focus Helvia PID `$(`$Process.Id)"

    for (`$i = 0; `$i -lt 40; `$i++) {

        try {
            `$Process.Refresh()
        }
        catch {}

        `$Handle = Find-HelviaWindow -Process `$Process

        if (`$Handle -ne [IntPtr]::Zero) {

            Write-HelviaLog "Helvia window found. HWND: `$Handle"

            try {

                # Restore minimized window
                if ([HelviaHotkey]::IsIconic(`$Handle)) {

                    Write-HelviaLog "Helvia is minimized. Restoring..."

                    [HelviaHotkey]::ShowWindow(
                        `$Handle,
                        9
                    ) | Out-Null
                }
                else {

                    [HelviaHotkey]::ShowWindow(
                        `$Handle,
                        5
                    ) | Out-Null
                }

                # Bring it above other windows
                [HelviaHotkey]::BringWindowToTop(
                    `$Handle
                ) | Out-Null

                # Give it foreground focus
                [HelviaHotkey]::SetForegroundWindow(
                    `$Handle
                ) | Out-Null

                Start-Sleep -Milliseconds 150

                `$Foreground = [HelviaHotkey]::GetForegroundWindow()

                if (`$Foreground -eq `$Handle) {

                    Write-HelviaLog `
                        "Helvia successfully focused. HWND: `$Handle"

                    return `$true
                }

                Write-HelviaLog `
                    "SetForegroundWindow did not immediately make Helvia foreground." `
                    "WARN"

                # Try one more time
                [HelviaHotkey]::BringWindowToTop(
                    `$Handle
                ) | Out-Null

                [HelviaHotkey]::SetForegroundWindow(
                    `$Handle
                ) | Out-Null

                Start-Sleep -Milliseconds 100

                return `$true
            }
            catch {

                Write-HelviaLog `
                    "Focus operation failed: `$(`$_.Exception.Message)" `
                    "ERROR"

                return `$false
            }
        }

        Start-Sleep -Milliseconds 250
    }

    Write-HelviaLog `
        "Helvia process exists but no visible window was detected." `
        "WARN"

    return `$false
}

# ------------------------------------------------------------
# START HELVIA
# ------------------------------------------------------------

function Start-Helvia {

    try {

        if (-not (Test-Path `$ExePath)) {

            Write-HelviaLog `
                "Helvia executable not found: `$ExePath" `
                "ERROR"

            return `$null
        }

        Write-HelviaLog "Starting Helvia..."

        `$Process = Start-Process `
            -FilePath `$ExePath `
            -PassThru

        Write-HelviaLog `
            "Helvia started. PID: `$(`$Process.Id)"

        return `$Process
    }
    catch {

        Write-HelviaLog `
            "Failed to start Helvia: `$(`$_.Exception.Message)" `
            "ERROR"

        return `$null
    }
}

# ------------------------------------------------------------
# HOTKEY ACTION
# ------------------------------------------------------------

function Invoke-HelviaHotkey {

    Write-HelviaLog "Ctrl + Alt + H pressed."

    # --------------------------------------------------------
    # CHECK EXISTING PROCESSES
    # --------------------------------------------------------

    `$Processes = Get-HelviaProcesses

    if (`$Processes.Count -gt 0) {

        Write-HelviaLog `
            "Found `$(`$Processes.Count) existing Helvia process(es)."

        foreach (`$Process in `$Processes) {

            if (`$Process.HasExited) {
                continue
            }

            Write-HelviaLog `
                "Using existing Helvia PID `$(`$Process.Id)"

            if (Show-HelviaWindow -Process `$Process) {
                return
            }
        }

        # ----------------------------------------------------
        # Existing process found but window isn't ready yet.
        # Wait before launching another instance.
        # ----------------------------------------------------

        `$ExistingProcess = `$Processes |
            Where-Object { -not `$_.HasExited } |
            Select-Object -First 1

        if (`$ExistingProcess) {

            Write-HelviaLog `
                "Waiting for existing Helvia window..."

            if (Show-HelviaWindow -Process `$ExistingProcess) {
                return
            }
        }
    }

    # --------------------------------------------------------
    # HELVIA NOT RUNNING
    # --------------------------------------------------------

    Write-HelviaLog "Helvia is not currently available. Starting it..."

    `$StartedProcess = Start-Helvia

    if (-not `$StartedProcess) {
        return
    }

    # --------------------------------------------------------
    # WAIT FOR WINDOW
    # --------------------------------------------------------

    Start-Sleep -Milliseconds 500

    Show-HelviaWindow -Process `$StartedProcess | Out-Null
}

# ------------------------------------------------------------
# REGISTER CTRL + ALT + H
# ------------------------------------------------------------

# MOD_CONTROL = 0x0002
# MOD_ALT     = 0x0001
# MOD_NOREPEAT = 0x4000
# VK_H = 0x48

`$MOD_CONTROL  = 0x0002
`$MOD_ALT      = 0x0001
`$MOD_NOREPEAT = 0x4000
`$VK_H         = 0x48

`$Modifiers = `$MOD_CONTROL -bor `$MOD_ALT -bor `$MOD_NOREPEAT

Write-HelviaLog "Registering global Ctrl + Alt + H hotkey..."

`$Registered = [HelviaHotkey]::RegisterHotKey(
    [IntPtr]::Zero,
    `$HotkeyId,
    `$Modifiers,
    `$VK_H
)

if (-not `$Registered) {

    `$ErrorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

    Write-HelviaLog `
        "FAILED to register Ctrl + Alt + H. Windows error code: `$ErrorCode" `
        "ERROR"

    if (`$ErrorCode -eq 1409) {

        Write-HelviaLog `
            "Error 1409 means Ctrl + Alt + H is already registered by another application." `
            "ERROR"
    }

    exit 1
}

Write-HelviaLog "Ctrl + Alt + H registered successfully."

# ------------------------------------------------------------
# MESSAGE LOOP
# ------------------------------------------------------------

try {

    `$Msg = New-Object HelviaHotkey+MSG

    while (`$true) {

        `$Result = [HelviaHotkey]::GetMessage(
            [ref]`$Msg,
            [IntPtr]::Zero,
            0,
            0
        )

        if (`$Result -eq -1) {

            Write-HelviaLog `
                "GetMessage returned an error." `
                "ERROR"

            break
        }

        if (`$Result -eq 0) {
            break
        }

        if (`$Msg.message -eq 0x0312) {

            if (`$Msg.wParam.ToUInt32() -eq `$HotkeyId) {

                Invoke-HelviaHotkey
            }
        }

        [HelviaHotkey]::TranslateMessage(
            [ref]`$Msg
        ) | Out-Null

        [HelviaHotkey]::DispatchMessage(
            [ref]`$Msg
        ) | Out-Null
    }
}
catch {

    Write-HelviaLog `
        "Hotkey message loop failed: `$(`$_.Exception.Message)" `
        "ERROR"
}
finally {

    try {

        [HelviaHotkey]::UnregisterHotKey(
            [IntPtr]::Zero,
            `$HotkeyId
        ) | Out-Null

        Write-HelviaLog "Ctrl + Alt + H unregistered."

    }
    catch {}

    try {
        if (`$Mutex) {
            `$Mutex.ReleaseMutex() | Out-Null
            `$Mutex.Dispose()
        }
    }
    catch {}
}
"@

Set-Content `
    -Path $HotkeyScript `
    -Value $HotkeyContent `
    -Encoding UTF8 `
    -Force

Write-InstallerLog "Hotkey manager installed."

# ------------------------------------------------------------
# 5. CLEAN LEGACY HELVIA SHORTCUTS
# ------------------------------------------------------------

Write-Host ""
Write-Host "[5/7] Cleaning old Helvia shortcuts..." -ForegroundColor Yellow

$DesktopPath = [Environment]::GetFolderPath("Desktop")

$StartMenuPath = Join-Path `
    $env:APPDATA `
    "Microsoft\Windows\Start Menu\Programs"

$ShortcutRoots = @(
    $DesktopPath,
    $StartMenuPath
)

$Shell = New-Object -ComObject WScript.Shell

foreach ($Root in $ShortcutRoots) {

    if (-not (Test-Path $Root)) {
        continue
    }

    Get-ChildItem `
        -Path $Root `
        -Filter "*.lnk" `
        -File `
        -ErrorAction SilentlyContinue |
        ForEach-Object {

            try {

                $ExistingShortcut = $Shell.CreateShortcut($_.FullName)

                $Target = $ExistingShortcut.TargetPath

                if (
                    $Target -and
                    ([IO.Path]::GetFileName($Target) -ieq $ExeName)
                ) {

                    Write-InstallerLog `
                        "Removing legacy Helvia shortcut: $($_.Name)"

                    Remove-Item `
                        $_.FullName `
                        -Force `
                        -ErrorAction SilentlyContinue
                }
            }
            catch {}
        }
}

# ------------------------------------------------------------
# 6. CREATE SHORTCUTS
# ------------------------------------------------------------

Write-Host ""
Write-Host "[6/7] Creating Helvia shortcuts..." -ForegroundColor Yellow

$DesktopShortcut = Join-Path `
    $DesktopPath `
    "Helvia.lnk"

$StartMenuShortcut = Join-Path `
    $StartMenuPath `
    "Helvia.lnk"

$StartupPath = Join-Path `
    $env:APPDATA `
    "Microsoft\Windows\Start Menu\Programs\Startup"

$StartupShortcut = Join-Path `
    $StartupPath `
    "Helvia Hotkey.lnk"

New-Item `
    -ItemType Directory `
    -Path $StartMenuPath `
    -Force |
    Out-Null

New-Item `
    -ItemType Directory `
    -Path $StartupPath `
    -Force |
    Out-Null

# ------------------------------------------------------------
# DESKTOP SHORTCUT
# ------------------------------------------------------------

$Shortcut = $Shell.CreateShortcut($DesktopShortcut)

$Shortcut.TargetPath       = $HelviaExe
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description      = "Helvia"
$Shortcut.IconLocation     = "$HelviaExe,0"

# IMPORTANT:
# Do NOT assign Ctrl+Alt+H to this shortcut.
# The global hotkey manager owns Ctrl+Alt+H.
$Shortcut.Hotkey = ""

$Shortcut.Save()

# ------------------------------------------------------------
# START MENU SHORTCUT
# ------------------------------------------------------------

$Shortcut = $Shell.CreateShortcut($StartMenuShortcut)

$Shortcut.TargetPath       = $HelviaExe
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description      = "Helvia"
$Shortcut.IconLocation     = "$HelviaExe,0"

$Shortcut.Hotkey = ""

$Shortcut.Save()

# ------------------------------------------------------------
# STARTUP HOTKEY MANAGER
# ------------------------------------------------------------

$Shortcut = $Shell.CreateShortcut($StartupShortcut)

$Shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$Shortcut.Arguments = @(
    "-NoProfile",
    "-ExecutionPolicy Bypass",
    "-WindowStyle Hidden",
    "-File `"$HotkeyScript`""
) -join " "

$Shortcut.WorkingDirectory = $SupportDir
$Shortcut.Description      = "Helvia Ctrl + Alt + H Hotkey Manager"

$Shortcut.Save()

Write-InstallerLog "Desktop shortcut created."
Write-InstallerLog "Start Menu shortcut created."
Write-InstallerLog "Startup hotkey manager created."

# ------------------------------------------------------------
# 7. START HOTKEY MANAGER
# ------------------------------------------------------------

Write-Host ""
Write-Host "[7/7] Starting Helvia hotkey manager..." -ForegroundColor Yellow

# Stop any remaining old hotkey manager
try {

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -like "*HelviaHotkey.ps1*"
        } |
        ForEach-Object {

            if ($_.ProcessId -ne $PID) {

                Stop-Process `
                    -Id $_.ProcessId `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
}
catch {}

Start-Sleep -Milliseconds 500

try {

    $HotkeyProcess = Start-Process `
        -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-WindowStyle",
            "Hidden",
            "-File",
            "`"$HotkeyScript`""
        ) `
        -WindowStyle Hidden `
        -PassThru

    Write-InstallerLog `
        "Hotkey manager started. PID: $($HotkeyProcess.Id)"

}
catch {

    Write-Host ""
    Write-Host "WARNING: Could not start hotkey manager." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# ------------------------------------------------------------
# CLEAN TEMP FILES
# ------------------------------------------------------------

try {
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
}
catch {}

# ------------------------------------------------------------
# FINISH
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "       HELVIA INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

Write-Host "Helvia installed at:" -ForegroundColor Cyan
Write-Host "  $InstallDir"
Write-Host ""

Write-Host "Global hotkey:" -ForegroundColor Cyan
Write-Host "  CTRL + ALT + H" -ForegroundColor Green
Write-Host ""

Write-Host "Hotkey manager:" -ForegroundColor Cyan
Write-Host "  $HotkeyScript"
Write-Host ""

Write-Host "Hotkey log:" -ForegroundColor Cyan
Write-Host "  $HotkeyLogFile"
Write-Host ""

Write-Host "Behavior:" -ForegroundColor Cyan
Write-Host "  • Helvia running   -> restore/focus Helvia"
Write-Host "  • Helvia minimized -> restore Helvia"
Write-Host "  • Helvia closed    -> launch Helvia"
Write-Host "  • Startup          -> hotkey manager starts automatically"
Write-Host ""

Write-Host "Installation finished successfully." -ForegroundColor Green
Write-Host ""
