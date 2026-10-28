# Starts the WildStar client in the person's session without taking their focus, and records what
# it started as. It reads genesis-start-args.txt (one value per line: the client's install folder,
# the auth host, then the account and the password, or neither), deletes that file, and writes
# genesis-start.txt last.
#
# The client's command line must begin with /auth and the auth host, or it starts the launcher and
# exits (fact 0x14000ae77). A scheduled task puts the program's name first, so the program is given
# to CreateProcessW as the application name and the command line begins with /auth.
#
# The result records the window's style (GWL_STYLE). The play PC's client runs borderless (a popup
# with no caption); started behind another window it keeps drawing and takes posted input.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Launch {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct STARTUPINFO {
    public int cb;
    public string lpReserved, lpDesktop, lpTitle;
    public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
    public short wShowWindow, cbReserved2;
    public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool CreateProcessW(string application, StringBuilder commandLine, IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint flags, IntPtr environment, string directory, ref STARTUPINFO startup, out PROCESS_INFORMATION process);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] public static extern uint GetWindowLong(IntPtr h, int index);}
"@

$argsFile = "$env:USERPROFILE\genesis-start-args.txt"
$resultFile = "$env:USERPROFILE\genesis-start.txt"
$started = 0
try {
  $ErrorActionPreference = 'Stop'
  $values = @(Get-Content -Encoding UTF8 $argsFile)
  Remove-Item $argsFile -Force
  $dir = Join-Path $values[0] 'Client64'
  $exe = Join-Path $dir 'WildStar64.exe'
  $hash = (Get-FileHash -Algorithm SHA256 $exe).Hash

  # A word with a space or a quote is quoted the way CommandLineToArgvW reads it back.
  function Quote([string]$word) {
    if ($word -notmatch '[\s"]' -and $word -ne '') { return $word }
    return '"' + ($word -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
  }
  $line = "/auth $(Quote $values[1]) /authNc $(Quote $values[1]) /lang en /realmDataCenterId 9 -logFile -logFlush"
  if ($values.Count -ge 4) { $line += " -account $(Quote $values[2]) -password $(Quote $values[3])" }

  $before = [Launch]::GetForegroundWindow().ToInt64()
  $si = New-Object Launch+STARTUPINFO
  $si.cb = [Runtime.InteropServices.Marshal]::SizeOf($si)
  # Ask for the first window to be shown without activating it.
  $si.dwFlags = 1
  $si.wShowWindow = 4
  $pi = New-Object Launch+PROCESS_INFORMATION
  $command = New-Object System.Text.StringBuilder($line, 4096)
  $ok = [Launch]::CreateProcessW($exe, $command, [IntPtr]::Zero, [IntPtr]::Zero, $false, 0, [IntPtr]::Zero, $dir, [ref]$si, [ref]$pi)
  if (-not $ok) { throw "CreateProcessW failed with error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
  [Launch]::CloseHandle($pi.hProcess) | Out-Null
  [Launch]::CloseHandle($pi.hThread) | Out-Null
  $started = $pi.dwProcessId

  $p = Get-Process -Id $started
  $deadline = (Get-Date).AddSeconds(60)
  while ($true) {
    $p.Refresh()
    if ($p.HasExited) { throw "the client exited with code $($p.ExitCode) before it had a window" }
    if ($p.MainWindowHandle -ne 0) { break }
    if ((Get-Date) -gt $deadline) { throw 'no client window after 60 s' }
    Start-Sleep -Milliseconds 500
  }
  # The client may change its window's style once it has read its settings.
  Start-Sleep -Seconds 2
  $p.Refresh()
  $style = [Launch]::GetWindowLong($p.MainWindowHandle, -16)
  $after = [Launch]::GetForegroundWindow().ToInt64()
  $result = "pid=$started sha256=$hash style=0x$('{0:x8}' -f $style) foreground_before=$before foreground_after=$after foreground_kept=$($before -eq $after)"
} catch {
  if ($started -ne 0) { Stop-Process -Id $started -Force -ErrorAction SilentlyContinue }
  $result = 'error: ' + ($_.Exception.Message -replace '\s+', ' ')
} finally {
  Remove-Item $argsFile -Force -ErrorAction SilentlyContinue
}
$result | Out-File -Encoding ascii $resultFile
