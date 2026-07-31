using System;
using System.Runtime.InteropServices;

namespace EngagementCloud.Internal
{
    /// <summary>
    /// Helpers for pulling native UTF-8 pointers into managed strings.
    /// Shim-owned pointers are only valid for the duration of the callback,
    /// so copy immediately.
    /// </summary>
    internal static class NativeUtf8
    {
        internal static string PtrToString(IntPtr utf8Ptr)
        {
            if (utf8Ptr == IntPtr.Zero) return null;
            return Marshal.PtrToStringUTF8(utf8Ptr);
        }
    }
}
