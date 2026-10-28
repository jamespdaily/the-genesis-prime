# Captures the WildStar window without moving, restoring or focusing it:
# PrintWindow with PW_RENDERFULLCONTENT asks the window to draw into a bitmap. It reads
# genesis-shot.ps1.in when that is there ("<pid> <start time>", the file client.sh keeps: the pid of
# the client it started and that process's start time as a file time in UTC) and captures only the
# process with that pid, the name WildStar64 and that start time; with no input it captures the
# first WildStar64 window. It writes genesis-shot.jpg, then genesis-shot.txt last, all at once (a
# .tmp moved into place). The picture is a JPEG of quality 90: a 4K PNG of the client is about
# 4.5 MB, and each one crosses the network.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Shot {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
"@
[Shot]::SetProcessDPIAware() | Out-Null
$inputFile = "$PSCommandPath.in"
$out = "$env:USERPROFILE\genesis-shot.jpg"
$resultFile = "$env:USERPROFILE\genesis-shot.txt"
try {
  $ErrorActionPreference = 'Stop'
  if (Test-Path $inputFile) {
    $words = (Get-Content -Raw $inputFile).Trim() -split '\s+'
    Remove-Item $inputFile -Force
    $p = Get-Process -Id ([int]$words[0]) -ErrorAction SilentlyContinue
    if (-not $p -or $p.ProcessName -ne 'WildStar64' -or $p.StartTime.ToFileTimeUtc() -ne [int64]$words[1]) {
      throw "the client that was started (pid $($words[0])) is not running"
    }
    if ($p.MainWindowHandle -eq 0) { $p = $null }
  } else {
    $p = Get-Process WildStar64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  }
  if (-not $p) { throw 'no WildStar window' }
  $r = New-Object Shot+RECT
  [Shot]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
  $w = $r.R - $r.L; $h = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $dc = $g.GetHdc()
  $ok = [Shot]::PrintWindow($p.MainWindowHandle, $dc, 2)
  $g.ReleaseHdc($dc)
  $jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.FormatID -eq [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid }
  $quality = New-Object System.Drawing.Imaging.EncoderParameters 1
  $quality.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]90)
  $bmp.Save($out, $jpeg, $quality)
  $result = "printwindow=$ok size=${w}x${h}"
} catch {
  $result = 'error: ' + ($_.Exception.Message -replace '\s+', ' ')
} finally {
  Remove-Item $inputFile -Force -ErrorAction SilentlyContinue
}
$result | Out-File -Encoding ascii "$resultFile.tmp"
Move-Item -Force "$resultFile.tmp" $resultFile
