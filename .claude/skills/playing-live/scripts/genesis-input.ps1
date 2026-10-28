# Types into the WildStar window without moving, restoring or focusing it: one WM_CHAR is posted
# to the window for each character. It reads genesis-input.txt (UTF-8: the client's pid, or 0 for
# any WildStar64 process, then a newline, then the text exactly as it is to be typed), deletes it,
# and writes genesis-input-result.txt last.
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
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint message, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern short VkKeyScan(char c);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
}
"@

$inputFile = "$env:USERPROFILE\genesis-input.txt"
$resultFile = "$env:USERPROFILE\genesis-input-result.txt"
try {
  $ErrorActionPreference = 'Stop'
  $raw = Get-Content -Raw -Encoding UTF8 $inputFile
  Remove-Item $inputFile -Force
  $newline = $raw.IndexOf("`n")
  $wanted = [int]$raw.Substring(0, $newline)
  $text = $raw.Substring($newline + 1)

  if ($wanted -ne 0) { $p = Get-Process -Id $wanted -ErrorAction SilentlyContinue }
  else { $p = Get-Process WildStar64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
  if (-not $p -or $p.MainWindowHandle -eq 0) { throw 'no WildStar window' }

  $before = [Input]::GetForegroundWindow().ToInt64()
  foreach ($c in $text.ToCharArray()) {
    # The scan code goes in bits 16-23 of lParam and the repeat count is 1.
    if ($c -eq [char]9) { $scan = 0x0F }
    elseif ($c -eq [char]13) { $scan = 0x1C }
    else {
      $key = [Input]::VkKeyScan($c)
      if ($key -eq -1) { $scan = 0 } else { $scan = [Input]::MapVirtualKey($key -band 0xff, 0) }
    }
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
$result | Out-File -Encoding ascii $resultFile
