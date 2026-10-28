# Types into the WildStar window without moving, restoring or focusing it: one WM_CHAR is posted
# to the window for each character. It reads genesis-input.ps1.in (UTF-8: the pid of the client
# client.sh started, a newline, that process's start time as a file time in UTC, a newline, then the
# text exactly as it is to be typed), deletes it, and writes genesis-input-result.txt last, all at
# once (a .tmp moved into place). It types only into the process with that pid, the name WildStar64
# and that start time, so a reused pid never reaches another client, the person's own included.
#
# Why this reaches the client with no focus (facts): a WM_CHAR inserts its character into the box
# that has the UI's own focus (0x140112a60); an Enter (13) in a one-line box raises EditBoxReturn
# (0x140111030); the login screen's UI handler takes WM_CHAR with no foreground check
# (0x1400e67a0). Never SendInput, SetForegroundWindow or SendMessage: they move the person's focus.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Input {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", EntryPoint = "PostMessageW", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool PostMessage(IntPtr h, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern short VkKeyScan(char c);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
}
"@

$inputFile = "$PSCommandPath.in"
$resultFile = "$env:USERPROFILE\genesis-input-result.txt"
try {
  $ErrorActionPreference = 'Stop'
  $raw = Get-Content -Raw -Encoding UTF8 $inputFile
  Remove-Item $inputFile -Force
  $first = $raw.IndexOf("`n")
  $second = $raw.IndexOf("`n", $first + 1)
  $wanted = [int]$raw.Substring(0, $first)
  $wantedStart = [int64]$raw.Substring($first + 1, $second - $first - 1)
  $text = $raw.Substring($second + 1)

  $p = Get-Process -Id $wanted -ErrorAction SilentlyContinue
  if (-not $p -or $p.ProcessName -ne 'WildStar64' -or $p.StartTime.ToFileTimeUtc() -ne $wantedStart) {
    throw "the client that was started (pid $wanted) is not running"
  }
  if ($p.MainWindowHandle -eq 0) { throw 'no WildStar window' }

  $before = [Input]::GetForegroundWindow().ToInt64()
  foreach ($c in $text.ToCharArray()) {
    # The scan code goes in bits 16-23 of lParam and the repeat count is 1. VkKeyScan gives Tab and
    # Return their virtual keys (9, 13) and MapVirtualKey their scan codes (0x0F, 0x1C).
    $key = [Input]::VkKeyScan($c)
    if ($key -eq -1) { $scan = 0 } else { $scan = [Input]::MapVirtualKey($key -band 0xff, 0) }
    $posted = [Input]::PostMessage($p.MainWindowHandle, 0x0102, [IntPtr][int]$c, [IntPtr](1 -bor ($scan -shl 16)))
    if (-not $posted) { throw "PostMessage failed with error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    Start-Sleep -Milliseconds 30
  }
  $after = [Input]::GetForegroundWindow().ToInt64()
  $result = "typed=$($text.Length) pid=$($p.Id) foreground_before=$before foreground_after=$after foreground_kept=$($before -eq $after)"
} catch {
  $result = 'error: ' + ($_.Exception.Message -replace '\s+', ' ')
} finally {
  Remove-Item $inputFile -Force -ErrorAction SilentlyContinue
}
$result | Out-File -Encoding ascii "$resultFile.tmp"
Move-Item -Force "$resultFile.tmp" $resultFile
