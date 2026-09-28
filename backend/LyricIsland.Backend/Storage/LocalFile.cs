using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace LyricIsland.Backend.Storage;

// Linux local input seam: opening a FIFO must never wait for a writer. Check
// the opened descriptor, not a path that can change between stat and open.
internal static class LocalFile
{
    [StructLayout(LayoutKind.Explicit, Size = 256)]
    struct Statx { [FieldOffset(28)] public ushort Mode; }
    [DllImport("libc", EntryPoint = "open", SetLastError = true)]
    static extern int Open(string path, int flags);
    [DllImport("libc", EntryPoint = "statx", SetLastError = true)]
    static extern int Stat(int fd, string path, int flags, uint mask, out Statx stat);

    public static FileStream OpenRead(string path)
    {
        // O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW. Imports use regular files only.
        var fd = Open(path, 0x800 | 0x80000 | 0x20000);
        if (fd < 0) throw new RequestError("storage_error", "Could not open local file.");
        var handle = new SafeFileHandle((IntPtr)fd, ownsHandle: true);
        try
        {
            // AT_EMPTY_PATH and STATX_TYPE; statx has a stable layout on Linux.
            if (Stat(fd, "", 0x1000, 1, out var stat) != 0)
                throw new RequestError("storage_error", "Could not inspect local file.");
            if ((stat.Mode & 0xf000) != 0x8000)
                throw new RequestError("invalid_request", "Select a regular local file.");
            return new FileStream(handle, FileAccess.Read);
        }
        catch { handle.Dispose(); throw; }
    }
}
