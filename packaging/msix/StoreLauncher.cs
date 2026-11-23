using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

// Older packages redirected writes under AppData into their private LocalCache.
// Import those files before the native app opens its now-unvirtualized profile.
internal static class StoreLauncher
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetCurrentPackageFamilyName(ref uint length, StringBuilder name);

    [STAThread]
    private static int Main()
    {
        try
        {
            uint length = 0;
            const int insufficientBuffer = 122;
            if (GetCurrentPackageFamilyName(ref length, null) != insufficientBuffer)
                throw new IOException("Windows could not identify the installed Inkrail package.");
            var family = new StringBuilder((int)length);
            if (GetCurrentPackageFamilyName(ref length, family) != 0)
                throw new IOException("Windows could not read the Inkrail package family name.");

            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string package = Path.Combine(local, "Packages", family.ToString());
            var conflicts = Migrate(package, roaming, local);
            if (conflicts.Count > 0)
                MessageBox.Show("Inkrail recovered writing from the previous Store installation. " +
                    "Where two files differed, it kept the previous Store version active and saved " +
                    "the other version beside it.\n\n" + string.Join("\n", conflicts),
                    "Recovered Inkrail files", MessageBoxButtons.OK, MessageBoxIcon.Information);

            string app = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Inkrail.exe");
            return RunApp(app);
        }
        catch (Exception error)
        {
            MessageBox.Show("Inkrail could not finish starting. Keep this package installed so " +
                "its previous writing stays available, then retry.\n\n" + error.Message,
                "Inkrail", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static int RunApp(string app)
    {
        // Pass the original argument tail through with its Windows quoting intact.
        string command = Environment.CommandLine.TrimStart();
        int end = command[0] == '"' ? command.IndexOf('"', 1) + 1 : command.IndexOfAny(new[] { ' ', '\t' });
        var start = new ProcessStartInfo(app, end < 0 ? "" : command.Substring(end).TrimStart());
        start.UseShellExecute = false;
        start.WorkingDirectory = Path.GetDirectoryName(app);
        using (var process = Process.Start(start))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    internal static List<string> Migrate(string package, string roaming, string local)
    {
        var conflicts = new List<string>();
        string cache = Path.Combine(package, "LocalCache");
        string state = Path.Combine(package, "LocalState");
        string complete = Path.Combine(state, "Inkrail-profile-migrated-v1");
        if (Attributes(complete).HasValue || !Attributes(cache).HasValue)
            return conflicts;

        Directory.CreateDirectory(state);
        // File sharing serializes initializers across processes and releases on a crash.
        using (new FileStream(complete + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            if (Attributes(complete).HasValue) return conflicts;
            string profile = Path.Combine(roaming, "Inkrail");
            string oldProfile = Path.Combine(cache, "Roaming", "Inkrail");
            string journal = Path.Combine(state, "Inkrail-migration-conflicts.txt");
            CopyIfPresent(oldProfile, profile, journal);
            // The private cache belongs only to this package. Other AppData libraries
            // may be split between the real and virtual directories. Discover their
            // data folders even if the old preferences were lost or no longer parse.
            CopyLibraries(Path.Combine(cache, "Roaming"), roaming, oldProfile, journal);
            CopyLibraries(Path.Combine(cache, "Local"), local, Path.Combine(cache, "Local", "Inkrail", "WebView2"), journal);
            if (Attributes(journal).HasValue)
                conflicts.AddRange(File.ReadAllLines(journal).Where(File.Exists));
            using (new FileStream(complete, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { }
        }
        return conflicts;
    }

    private static FileAttributes? Attributes(string path)
    {
        try { return File.GetAttributes(path); }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
    }

    private static void CopyLibraries(string source, string target, string skip, string journal)
    {
        if (!Attributes(source).HasValue) return;
        foreach (string folder in Directory.GetDirectories(source))
        {
            if (string.Equals(folder, skip, StringComparison.OrdinalIgnoreCase)) continue;
            string name = Path.GetFileName(folder);
            string destination = Path.Combine(target, name);
            if (new[] { "Letters", "Recently Deleted", "Recovery" }.Contains(name, StringComparer.OrdinalIgnoreCase))
                CopyIfPresent(folder, destination, journal);
            else if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) == 0)
                CopyLibraries(folder, destination, skip, journal);
        }
    }

    private static void CopyIfPresent(string source, string target, string journal)
    {
        var attributes = Attributes(source);
        if (!attributes.HasValue) return;
        if ((attributes.Value & FileAttributes.ReparsePoint) != 0 ||
            (Attributes(target).GetValueOrDefault() & FileAttributes.ReparsePoint) != 0)
            throw new IOException("A linked path needs attention before copying " + source + " to " + target);
        if ((attributes.Value & FileAttributes.Directory) != 0)
        {
            Directory.CreateDirectory(target);
            foreach (string child in Directory.GetFileSystemEntries(source))
                CopyIfPresent(child, Path.Combine(target, Path.GetFileName(child)), journal);
            return;
        }

        using (var input = File.OpenRead(source))
        using (var hash = SHA256.Create())
        {
            byte[] expected = hash.ComputeHash(input);
            if (Attributes(target).HasValue)
                using (var existing = File.OpenRead(target))
                    if (expected.SequenceEqual(hash.ComputeHash(existing))) return;

            string temporary = Path.Combine(Path.GetDirectoryName(target), Guid.NewGuid().ToString("N") + ".migration-tmp");
            try
            {
                input.Position = 0;
                using (var copy = new FileStream(temporary, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None))
                {
                    input.CopyTo(copy);
                    copy.Flush(true);
                    copy.Position = 0;
                    if (!expected.SequenceEqual(hash.ComputeHash(copy)))
                        throw new IOException("Copy verification failed for " + source);
                }
                File.SetLastWriteTimeUtc(temporary, File.GetLastWriteTimeUtc(source));
                if (Attributes(target).HasValue)
                {
                    // ReplaceFile atomically saves the current destination as well, even
                    // if another process wrote it after the initial comparison.
                    string backup = target + "." + Guid.NewGuid().ToString("N") + ".before-store-migration";
                    File.AppendAllText(journal, backup + Environment.NewLine);
                    File.Replace(temporary, target, backup);
                }
                else File.Move(temporary, target);
            }
            finally { File.Delete(temporary); }
        }
    }
}
