# Presses one key in the WildStar window with the real keyboard input, in takeover mode: it brings the
# window forward, presses the key with a hardware scan code, holds it, and releases it. It reads
# genesis-key.ps1.in (UTF-8: the pid of the client client.sh started, a newline, that process's start
# time as a file time in UTC, a newline, the scan code as a decimal number (0xE000 added for an
# extended key), a newline, the hold in milliseconds), deletes it, and writes genesis-key-result.txt
# last, all at once (a .tmp moved into place). It acts only on the process with that pid, the name
# WildStar64 and that start time, so a reused pid never reaches another client, the person's own
# included. client.sh runs it only with --pc-free (or GENESIS_PC_FREE=1): it takes the person's focus
# and keyboard.
#
# Why a posted message is not enough (facts): the client's key bindings read WM_KEYDOWN by its
# hardware scan code in the input device (0x1407ac6f0, InputDeviceHandleMessage), and only while the
# client is the foreground window (0x1407acdf0, UpdateInputDevice); it reads no raw keyboard and no
# DirectInput (0x1407a7780). So the key goes through SendInput with KEYEVENTF_SCANCODE (8), |1
# (KEYEVENTF_EXTENDEDKEY) for a 0xE0 key, |2 (KEYEVENTF_KEYUP) for the release. A 64-bit INPUT is 40
# bytes, its union at offset 8 (the union's largest member, MOUSEINPUT, is 32 bytes), and SendInput
# refuses any other size. The client reads its keys on its own frame, so the key is held long enough
# for a frame to see it. When the client loses the front during the hold, the key is released at once
# and nothing more is pressed: the key would otherwise go to another window. The release is in a
# finally block over the press and the hold, so any way the script ends but a kill releases the key;
# client.sh gives the task 30 s plus the hold, so run_task never kills it during the hold.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Key {
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort vk; public ushort scan; public uint flags; public uint time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size = 40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT k; }
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int command);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

  // Sends one key event by scan code; returns 0 when it was sent, else the Win32 error.
  public static int Send(ushort scan, uint flags) {
    INPUT[] i = new INPUT[1];
    i[0].type = 1;
    i[0].k.scan = scan;
    i[0].k.flags = flags;
    if (SendInput(1, i, Marshal.SizeOf(typeof(INPUT))) == 1) { return 0; }
    return Marshal.GetLastWin32Error();
  }
}
"@

$inputFile = "$PSCommandPath.in"
$resultFile = "$env:USERPROFILE\genesis-key-result.txt"
$scanCodeFlag = 8
$extendedFlag = 1
$releaseFlag = 2
$restore = 9
$slice = 20

try {
  $ErrorActionPreference = 'Stop'
  $lines = (Get-Content -Raw -Encoding UTF8 $inputFile) -split "`n"
  $wanted = [int]$lines[0]
  $wantedStart = [int64]$lines[1]
  $code = [int]$lines[2]
  $hold = [int]$lines[3]
  $scan = [uint16]($code -band 0xFF)
  $flags = $scanCodeFlag
  if (($code -band 0xFF00) -eq 0xE000) { $flags = $flags -bor $extendedFlag }

  $p = Get-Process -Id $wanted -ErrorAction SilentlyContinue
  if (-not $p -or $p.ProcessName -ne 'WildStar64' -or $p.StartTime.ToFileTimeUtc() -ne $wantedStart) {
    throw "the client that was started (pid $wanted) is not running"
  }
  $window = $p.MainWindowHandle
  if ($window -eq 0) { throw 'no WildStar window' }

  # Bring the window forward, as genesis-click.ps1 does: a process that is not the foreground one may
  # not take the focus, so this thread's input is attached to the foreground window's thread for the call.
  if ([Key]::IsIconic($window)) { [Key]::ShowWindow($window, $restore) | Out-Null }
  $foreground = [Key]::GetForegroundWindow()
  if ($foreground -ne $window) {
    [uint32]$ignored = 0
    $foregroundThread = [Key]::GetWindowThreadProcessId($foreground, [ref]$ignored)
    $thisThread = [Key]::GetCurrentThreadId()
    [Key]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [Key]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [Key]::AttachThreadInput($thisThread, $foregroundThread, $true) | Out-Null
    [Key]::BringWindowToTop($window) | Out-Null
    [Key]::SetForegroundWindow($window) | Out-Null
    [Key]::AttachThreadInput($thisThread, $foregroundThread, $false) | Out-Null
    Start-Sleep -Milliseconds 300
  }
  if ([Key]::GetForegroundWindow() -ne $window) { throw 'the window could not be brought forward' }

  # The release is in a finally block that covers the press and the hold: a throw during the hold, or
  # a stopped pipeline, still lets the key go up. A process that is killed runs no finally, which is
  # why client.sh gives the task its limit plus the hold.
  $pressed = $false
  $lost = $false
  $error2 = 0
  $watch = [Diagnostics.Stopwatch]::StartNew()
  try {
    $error1 = [Key]::Send($scan, $flags)
    if ($error1 -ne 0) { throw "SendInput refused the press with error $error1" }
    $pressed = $true
    while ($watch.ElapsedMilliseconds -lt $hold) {
      Start-Sleep -Milliseconds ([Math]::Min($slice, [Math]::Max(1, $hold - $watch.ElapsedMilliseconds)))
      if ([Key]::GetForegroundWindow() -ne $window) { $lost = $true; break }
    }
  } finally {
    if ($pressed) { $error2 = [Key]::Send($scan, $flags -bor $releaseFlag) }
  }
  $held = $watch.ElapsedMilliseconds
  if ($error2 -ne 0) { throw "SendInput refused the release with error $error2" }
  if ($lost) { throw "the client lost the front after $held ms of the $hold ms hold; the key was released then" }
  $result = "pressed=0x$('{0:X}' -f $code) held=$held foreground_is_client=$([Key]::GetForegroundWindow() -eq $window) pid=$($p.Id)"
} catch {
  $result = 'error: ' + ($_.Exception.Message -replace '\s+', ' ')
} finally {
  Remove-Item $inputFile -Force -ErrorAction SilentlyContinue
}
$result | Out-File -Encoding ascii "$resultFile.tmp"
Move-Item -Force "$resultFile.tmp" $resultFile
