<#
.SYNOPSIS
  Windows only. Makes a Claude-in-Chrome tab render (Chrome freezes hidden tabs, so screenshots and clicks, often
  scripts too, time out on them) WITHOUT taking the user's keyboard focus: the user keeps typing in their own window.

  How to use it from Claude:
    1. Keep ONE tab per Chrome window for your work (the window the Claude-in-Chrome tab group opened): reuse that tab
       by navigating it rather than creating more tabs. Then the tab you need is always the window's active tab.
    2. Give it a unique title with the javascript_tool:  document.title = 'CLAUDE-<something>'
       (re-set it after the page loads; apps such as Power Apps overwrite the title while loading).
    3. Run it IN-PROCESS from the PowerShell tool:
         & "<pp-test-verify skill folder>\scripts\Show-ChromeTab.ps1" -Marker 'CLAUDE-<something>'
       (not "pwsh -File": that opens a console window which takes the focus).
    4. Screenshot / click the tab with the Chrome tools as usual.

  What it does (no keystrokes, no SetForegroundWindow):
    - Finds the tab through Windows UI Automation: every Chrome window's tab strip lists its tabs (TabItem) by title.
    - Does NOT switch tabs by default: selecting a Chrome tab through UI Automation activates the Chrome window (tested
      2026-10-07), which takes the user's focus. If the tab is not its window's active tab the script stops with exit
      code 3; -AllowSelect selects it anyway and immediately gives the focus back (a short focus blip).
    - Makes the window visible without activating it: restores it if minimised (SW_SHOWNOACTIVATE) and raises it in
      the z-order with SWP_NOACTIVATE. If more than one monitor is connected and the window is on the primary monitor,
      it is moved to a secondary monitor first (sized to its work area), so the user's main screen is left alone. With
      a single monitor it stays where it is.
    - Checks the foreground window did not change and reports it.
  Exit codes: 0 = tab shown, 1 = tab not found, 2 = could not be selected, 3 = not the active tab (and no -AllowSelect).
#>
param(
  [Parameter(Mandatory)][string]$Marker,   # unique title prefix set on the target tab
  [switch]$StayOnMonitor,                  # do not move the window to a secondary monitor
  [switch]$AllowSelect                     # select the tab even if that briefly activates Chrome (focus is restored)
)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class NoFocusWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
  // Give the focus back: attach to the current foreground thread so SetForegroundWindow is allowed, retry a few times
  public static bool GiveBack(IntPtr h) {
    for (int i = 0; i < 5 && GetForegroundWindow() != h; i++) {
      keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
      uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero), me = GetCurrentThreadId();
      bool att = fg != me && AttachThreadInput(me, fg, true);
      BringWindowToTop(h); SetForegroundWindow(h);
      if (att) AttachThreadInput(me, fg, false);
      System.Threading.Thread.Sleep(80);
    }
    return GetForegroundWindow() == h; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  public static string Title(IntPtr h) { var sb = new System.Text.StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public const uint NOSIZE = 0x1, NOMOVE = 0x2, NOACTIVATE = 0x10, SHOWWINDOW = 0x40;
  public static readonly IntPtr TOPMOST = new IntPtr(-1), NOTOPMOST = new IntPtr(-2), TOP = IntPtr.Zero;
  // Raise above other windows without activating: topmost then not-topmost leaves it on top of the normal band
  public static void Raise(IntPtr h) { SetWindowPos(h, TOPMOST, 0, 0, 0, 0, NOMOVE | NOSIZE | NOACTIVATE | SHOWWINDOW); SetWindowPos(h, NOTOPMOST, 0, 0, 0, 0, NOMOVE | NOSIZE | NOACTIVATE | SHOWWINDOW); }
}
'@
$A = [System.Windows.Automation.AutomationElement]; $Scope = [System.Windows.Automation.TreeScope]; $C = [System.Windows.Automation.ControlType]
$fgBefore = [NoFocusWin]::GetForegroundWindow()

# 1. find the tab in any Chrome window's tab strip
$chromeCond = New-Object System.Windows.Automation.PropertyCondition($A::ClassNameProperty, 'Chrome_WidgetWin_1')
$tabCond = New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, $C::TabItem)
$hit = $null; $hitWin = $null
foreach ($w in $A::RootElement.FindAll($Scope::Children, $chromeCond)) {
  foreach ($tab in $w.FindAll($Scope::Descendants, $tabCond)) {
    if ($tab.Current.Name.StartsWith($Marker)) { $hit = $tab; $hitWin = $w; break }
  }
  if ($hit) { break }
}
if (-not $hit) { "not found: no Chrome tab titled '$Marker*'"; exit 1 }
$h = [IntPtr]$hitWin.Current.NativeWindowHandle
"found: '$($hit.Current.Name)' in window $h"

# 2. make the window visible without activating it (secondary monitor if there is one)
if ([NoFocusWin]::IsIconic($h)) { [void][NoFocusWin]::ShowWindow($h, 4) }   # SW_SHOWNOACTIVATE
$screens = [System.Windows.Forms.Screen]::AllScreens
if (-not $StayOnMonitor -and $screens.Count -gt 1) {
  $r = New-Object NoFocusWin+RECT; [void][NoFocusWin]::GetWindowRect($h, [ref]$r)
  $cx = [int](($r.L + $r.R) / 2); $cy = [int](($r.T + $r.B) / 2)
  $on = $screens | Where-Object { $_.Bounds.Contains($cx, $cy) } | Select-Object -First 1
  if (-not $on -or $on.Primary) {
    $sec = $screens | Where-Object { -not $_.Primary } | Select-Object -First 1
    $wa = $sec.WorkingArea
    if ([NoFocusWin]::IsZoomed($h)) { [void][NoFocusWin]::ShowWindow($h, 4) }   # un-maximise without activating
    [void][NoFocusWin]::SetWindowPos($h, [NoFocusWin]::TOP, $wa.X, $wa.Y, $wa.Width, $wa.Height, [NoFocusWin]::NOACTIVATE -bor [NoFocusWin]::SHOWWINDOW)
    "moved to secondary monitor $($sec.DeviceName) $($wa.X),$($wa.Y) $($wa.Width)x$($wa.Height)"
  }
}
[NoFocusWin]::Raise($h)

# 3. the tab must already be its window's active tab (selecting it would activate Chrome and take the focus)
$sel = $false; try { $sel = $hit.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected } catch { }
if (-not $sel) {
  if (-not $AllowSelect) { "not the active tab of its window - close/navigate the other tabs in that window, or use -AllowSelect"; exit 3 }
  $ok = $false; try { $hit.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $ok = $true } catch { }
  Start-Sleep -Milliseconds 150
  if ([NoFocusWin]::GetForegroundWindow() -ne $fgBefore) { [void][NoFocusWin]::GiveBack($fgBefore) }
  if (-not $ok) { 'could not select the tab'; exit 2 }
}
Start-Sleep -Milliseconds 300
$fgAfter = [NoFocusWin]::GetForegroundWindow()
"shown; foreground before: '$([NoFocusWin]::Title($fgBefore))', after: '$([NoFocusWin]::Title($fgAfter))' (unchanged: $($fgAfter -eq $fgBefore))"
exit 0