# Clicks in the WildStar window with the real mouse, in takeover mode: it brings the window forward,
# moves the real cursor to a point of the window's client area and presses and releases the left
# button there. It reads genesis-click.ps1.in (UTF-8: the pid of the client client.sh started, a
# newline, that process's start time as a file time in UTC, a newline, the client x, a newline, the
# client y), deletes it, and writes genesis-click-result.txt last, all at once (a .tmp moved into
# place). It acts only on the process with that pid, the name WildStar64 and that start time, so a
# reused pid never reaches another client, the person's own included. client.sh runs it only with
# --pc-free (or GENESIS_PC_FREE=1): it takes the person's focus and mouse.
#
# Why a posted message is not enough (facts): the client's UI pointer is the real cursor
# (GetCursorPos, converted to window terms, 0x1403f3790), so a click posted to the window moves no
# pointer and a hover never shows. The point is a client point: ClientToScreen turns it into the
# screen point SetCursorPos and SendInput act on, with the process DPI aware so both are in the
# window's own pixels (the borderless window is 3840x2160).
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Click {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
    public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo;
  }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int command);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern uint SendInput(uint count, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@
[Click]::SetProcessDPIAware() | Out-Null

$inputFile = "$PSCommandPath.in"
$resultFile = "$env:USERPROFILE\genesis-click-result.txt"
$leftDown = 0x0002
$leftUp = 0x0004
$restore = 9

# One left-button event through SendInput.
function Send-Button([uint32]$flags) {
  $press = New-Object Click+INPUT
  $press.type = 0
  $press.mi.dwFlags = $flags
  $sent = [Click]::SendInput(1, @($press), [Runtime.InteropServices.Marshal]::SizeOf([type][Click+INPUT]))
  if ($sent -ne 1) { throw "SendInput sent $sent events" }
}

try {
  $ErrorActionPreference = 'Stop'
  $lines = (Get-Content -Raw -Encoding UTF8 $inputFile) -split "`n"
  Remove-Item $inputFile -Force
  $wanted = [int]$lines[0]
  $wantedStart = [int64]$lines[1]
  $x = [int]$lines[2]
  $y = [int]$lines[3]

  $p = Get-Process -Id $wanted -ErrorAction SilentlyContinue
  if (-not $p -or $p.ProcessName -ne 'WildStar64' -or $p.StartTime.ToFileTimeUtc() -ne $wantedStart) {
    throw "the client that was started (pid $wanted) is not running"
  }
  $window = $p.MainWindowHandle
  if ($window -eq 0) { throw 'no WildStar window' }

  # Bring the window forward. A process that is not the foreground one may not take the focus, so
  # this thread's input is attached to the foreground window's thread for the call.
  if ([Click]::IsIconic($window)) { [Click]::ShowWindow($window, $restore) | Out-Null }
  $foreground = [Click]::GetForegroundWindow()
  if ($foreground -ne $window) {
    [uint32]$ignored = 0
    $foregroundThread = [Click]::GetWindowThreadProcessId($foreground, [ref]$ignored)
    $thisThread = [Click]::GetCurrentThreadId()
    [Click]::AttachThreadInput($thisThread, $foregroundThread, $true) | Out-Null
    [Click]::BringWindowToTop($window) | Out-Null
    [Click]::SetForegroundWindow($window) | Out-Null
    [Click]::AttachThreadInput($thisThread, $foregroundThread, $false) | Out-Null
    Start-Sleep -Milliseconds 300
  }
  if ([Click]::GetForegroundWindow() -ne $window) { throw 'the window could not be brought forward' }

  $point = New-Object Click+POINT
  $point.X = $x
  $point.Y = $y
  if (-not [Click]::ClientToScreen($window, [ref]$point)) { throw 'the client point has no screen point' }
  if (-not [Click]::SetCursorPos($point.X, $point.Y)) { throw 'the cursor could not be moved' }
  # The client reads the cursor on its own frame, so it rests on the point before the press and
  # the press is held, as a person's is.
  Start-Sleep -Milliseconds 300
  Send-Button $leftDown
  Start-Sleep -Milliseconds 150
  Send-Button $leftUp
  $result = "clicked=$x,$y screen=$($point.X),$($point.Y) pid=$($p.Id)"
} catch {
  $result = 'error: ' + ($_.Exception.Message -replace '\s+', ' ')
} finally {
  Remove-Item $inputFile -Force -ErrorAction SilentlyContinue
}
$result | Out-File -Encoding ascii "$resultFile.tmp"
Move-Item -Force "$resultFile.tmp" $resultFile
