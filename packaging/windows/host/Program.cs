using System.Security.Cryptography;
using System.Text;

namespace Inkrail.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        try
        {
            string defaultProfile = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Inkrail");
            string? profileOverride = null;
            int? debugPort = null;
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "-data" when i + 1 < args.Length:
                        profileOverride = Path.GetFullPath(args[++i]);
                        break;
                    case "-qa-port" when i + 1 < args.Length:
                        if (!int.TryParse(args[++i], out int port) || port is < 1 or > 65535)
                            throw new ArgumentException("Choose a valid port for the test profile.");
                        debugPort = port;
                        break;
                    default:
                        throw new ArgumentException("Unrecognized or incomplete argument: " + args[i]);
                }
            }

            if (debugPort.HasValue && (profileOverride == null ||
                Path.GetRelativePath(defaultProfile, profileOverride) == "."))
                throw new ArgumentException("Use a separate -data folder when running the native smoke test.");

            string profile = profileOverride ?? defaultProfile;
            string profileKey = Path.TrimEndingDirectorySeparator(Path.GetFullPath(profile)).ToUpperInvariant();
            string mutexName = @"Local\Inkrail-Desk-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(profileKey)));
            using var instance = new Mutex(false, mutexName, out bool firstInstance);
            if (!firstInstance)
            {
                MessageBox.Show("Inkrail is already open for this library profile. Switch to its existing window.",
                    "Inkrail", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 0;
            }
            string cache = profileOverride == null
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Inkrail", "WebView2")
                : Path.Combine(profile, "WebView2");
            using var window = new WriterWindow(new Library(profile), cache, debugPort);
            Application.Run(window);
            return window.ExitCode;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Inkrail", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
