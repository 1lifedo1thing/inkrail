using System;
using System.IO;
using System.Linq;

internal static class ProfileMigrationChecks
{
    private static void Put(string file, string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(file));
        File.WriteAllText(file, content);
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    private static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "Inkrail-migration-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string local = Path.Combine(root, "local");
            string roaming = Path.Combine(root, "roaming");
            string package = Path.Combine(local, "Packages", "example");
            string cache = Path.Combine(package, "LocalCache");
            string profile = Path.Combine(roaming, "Inkrail");
            string oldProfile = Path.Combine(cache, "Roaming", "Inkrail");
            string letter = Path.Combine("Library", "Letters", "letter.json");
            string active = Path.Combine(profile, letter);
            string old = Path.Combine(oldProfile, letter);
            string library = Path.Combine(local, "Chosen library");
            string customLetter = Path.Combine("Recently Deleted", "another.json");
            Put(old, "Store version");
            Put(old + ".bak", "Store backup");
            Put(active, "Portable version");
            Put(Path.Combine(profile, "Library", "Recovery", "existing.damaged"), "recovery");
            // A corrupt preferences file or a later folder change must not hide
            // libraries that the previous Store installation wrote to AppData.
            Put(Path.Combine(oldProfile, "preferences.json"), "{incomplete");
            Put(Path.Combine(cache, "Local", "Chosen library", customLetter), "custom trash");
            string previousLetter = Path.Combine("Earlier library", "Letters", "prior.json");
            Put(Path.Combine(cache, "Roaming", previousLetter), "previous custom letter");
            Put(Path.Combine(cache, "Local", "Inkrail", "WebView2", "Cache"), "not library data");

            // Restore the failed destination and retry after a partial migration.
            string blocked = Path.Combine(library, customLetter);
            Directory.CreateDirectory(blocked);
            bool failed = false;
            try { StoreLauncher.Migrate(package, roaming, local); }
            catch (IOException) { failed = true; }
            catch (UnauthorizedAccessException) { failed = true; }
            Require(failed, "A copy error must interrupt migration.");
            Require(!File.Exists(Path.Combine(package, "LocalState", "Inkrail-profile-migrated-v1")), "Premature completion marker.");
            Directory.Delete(blocked);
            var recovered = StoreLauncher.Migrate(package, roaming, local);

            Require(File.ReadAllText(active) == "Store version", "The previous Store view should be active.");
            Require(File.ReadAllText(active + ".bak") == "Store backup", "Lost prior backup.");
            Require(File.ReadAllText(blocked) == "custom trash", "Lost custom library.");
            Require(File.ReadAllText(Path.Combine(roaming, previousLetter)) == "previous custom letter", "Lost an earlier custom library.");
            Require(File.ReadAllText(old) == "Store version", "Private source was modified.");
            Require(File.ReadAllText(Path.Combine(profile, "Library", "Recovery", "existing.damaged")) == "recovery", "Lost existing recovery file.");
            var saved = Directory.GetFiles(Path.GetDirectoryName(active), "*.before-store-migration");
            Require(saved.Length == 1 && File.ReadAllText(saved.Single()) == "Portable version", "Unrecoverable migration conflict.");
            Require(recovered.Contains(saved.Single()), "A partial migration lost the location of the portable version.");
            Require(!Directory.Exists(Path.Combine(local, "Inkrail", "WebView2")), "Unrelated cache migrated.");
            Put(active, "writing after migration");
            StoreLauncher.Migrate(package, roaming, local);
            Require(File.ReadAllText(active) == "writing after migration", "Old data replayed after migration.");
            Directory.Delete(package, true);
            StoreLauncher.Migrate(package, roaming, local);
            Require(File.ReadAllText(active) == "writing after migration" && File.ReadAllText(blocked) == "custom trash",
                "Removing package-owned storage lost migrated letters.");
            Console.WriteLine("Store profile migration checks passed.");
            return 0;
        }
        finally { Directory.Delete(root, true); }
    }
}
