# Captures the WildStar window without moving, restoring or focusing it:
# PrintWindow with PW_RENDERFULLCONTENT asks the window to draw into a bitmap.
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
$out = "$env:USERPROFILE\genesis-shot.png"
$p = Get-Process WildStar64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { "no WildStar window" | Out-File "$env:USERPROFILE\genesis-shot.txt"; exit 1 }
$r = New-Object Shot+RECT
[Shot]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
$ok = [Shot]::PrintWindow($p.MainWindowHandle, $dc, 2)
$g.ReleaseHdc($dc)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
"printwindow=$ok size=${w}x${h}" | Out-File "$env:USERPROFILE\genesis-shot.txt"
