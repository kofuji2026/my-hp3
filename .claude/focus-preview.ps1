# focus-preview.ps1
# preview_screenshot の直前に Claude Code ウィンドウを前面に出すスクリプト

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern IntPtr FindWindow(string className, string windowName);
}
"@

# 方法1: WScript.Shell の AppActivate でタイトルから起動
$activated = $false
try {
    $shell = New-Object -ComObject WScript.Shell
    $activated = $shell.AppActivate("Claude")
    if ($activated) {
        Write-Output "AppActivate succeeded"
        Start-Sleep -Milliseconds 500
    }
} catch {}

# 方法2: FindWindow でウィンドウハンドルを取得して強制フォーカス
if (-not $activated) {
    $hwnd = [WinAPI]::FindWindow([NullString]::Value, "Claude")
    if ($hwnd -ne [IntPtr]::Zero) {
        [WinAPI]::ShowWindow($hwnd, 9)
        [WinAPI]::BringWindowToTop($hwnd)
        [WinAPI]::SetForegroundWindow($hwnd)
        Write-Output "FindWindow focused (HWND=$hwnd)"
        Start-Sleep -Milliseconds 500
    } else {
        Write-Output "Window not found – skip focus"
    }
}
