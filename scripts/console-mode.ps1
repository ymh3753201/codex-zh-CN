#Requires -Version 5.1
function Initialize-InstallerConsole {
    # Quick Edit in conhost can stop console writes when the user selects text.
    # Change only this console, never HKCU\Console or global terminal settings.
    if (-not ('CodexZh.ConsoleGuard' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CodexZh {
    public sealed class ConsoleGuard : IDisposable {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int handle);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetConsoleMode(IntPtr handle, out uint mode);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetConsoleMode(IntPtr handle, uint mode);
        public IntPtr InputHandle { get; private set; }
        public uint OriginalMode { get; private set; }
        public bool Active { get; private set; }
        public int ErrorCode { get; private set; }
        public static ConsoleGuard DisableQuickEdit() {
            var result = new ConsoleGuard();
            result.InputHandle = GetStdHandle(-10);
            uint mode;
            if (!GetConsoleMode(result.InputHandle, out mode)) {
                result.ErrorCode = Marshal.GetLastWin32Error();
                return result; // Redirected input / no console is a normal case.
            }
            result.OriginalMode = mode;
            // Microsoft requires EXTENDED_FLAGS when changing QUICK_EDIT_MODE.
            result.Active = SetConsoleMode(result.InputHandle, (mode | 0x0080u) & ~0x0040u);
            if (!result.Active) result.ErrorCode = Marshal.GetLastWin32Error();
            return result;
        }
        public void Dispose() {
            if (!Active) return;
            SetConsoleMode(InputHandle, OriginalMode | 0x0080u);
            Active = false;
        }
    }
}
'@
    }
    return [CodexZh.ConsoleGuard]::DisableQuickEdit()
}
