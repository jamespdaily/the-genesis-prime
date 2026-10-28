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
# screen point SetCursorPos acts on (the press is mouse_event), with the process DPI aware so both
# are in the window's own pixels (the borderless window is 3840x2160). The point must lie inside the
# window's client rectangle, and the window under the cursor must be the client's before the press,
# or nothing is pressed.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Click {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int command);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(ref POINT p);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int x, int y, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
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
$rootAncestor = 2

try {
  $ErrorActionPreference = 'Stop'
  $lines = (Get-Content -Raw -Encoding UTF8 $inputFile) -split "`n"
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
    [Click]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [Click]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [Click]::AttachThreadInput($thisThread, $foregroundThread, $true) | Out-Null
    [Click]::BringWindowToTop($window) | Out-Null
    [Click]::SetForegroundWindow($window) | Out-Null
    [Click]::AttachThreadInput($thisThread, $foregroundThread, $false) | Out-Null
    Start-Sleep -Milliseconds 300
  }
  if ([Click]::GetForegroundWindow() -ne $window) { throw 'the window could not be brought forward' }

  $client = New-Object Click+RECT
  if (-not [Click]::GetClientRect($window, [ref]$client)) { throw 'the window has no client rectangle' }
  if ($x -lt $client.Left -or $y -lt $client.Top -or $x -ge $client.Right -or $y -ge $client.Bottom) {
    throw "the point $x,$y is outside the client rectangle $($client.Right)x$($client.Bottom)"
  }
  $point = New-Object Click+POINT
  $point.X = $x
  $point.Y = $y
  if (-not [Click]::ClientToScreen($window, [ref]$point)) { throw 'the client point has no screen point' }
  if (-not [Click]::SetCursorPos($point.X, $point.Y)) { throw 'the cursor could not be moved' }
  # The client reads the real cursor on its own frame, so it rests on the point before the press.
  Start-Sleep -Milliseconds 300
  # The press goes to whatever is under the cursor, so it is made only when that is the client's window.
  $under = [Click]::WindowFromPoint($point)
  if ($under -eq 0 -or [Click]::GetAncestor($under, $rootAncestor) -ne $window) {
    throw "the window under the cursor at $($point.X),$($point.Y) is not the client's"
  }
  [Click]::mouse_event($leftDown, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [Click]::mouse_event($leftUp, 0, 0, 0, [UIntPtr]::Zero)
  $cursor = New-Object Click+POINT
  [Click]::GetCursorPos([ref]$cursor) | Out-Null
  $result = "clicked=$x,$y screen=$($point.X),$($point.Y) cursor_after=$($cursor.X),$($cursor.Y) foreground_is_client=$([Click]::GetForegroundWindow() -eq $window) pid=$($p.Id)"
} catch {
  $result = 'error: ' + ($_.Exception.Message -replace '\s+', ' ')
} finally {
  Remove-Item $inputFile -Force -ErrorAction SilentlyContinue
}
$result | Out-File -Encoding ascii "$resultFile.tmp"
Move-Item -Force "$resultFile.tmp" $resultFile
