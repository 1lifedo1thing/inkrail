using System.Text.Json;
using Inkrail.Windows;

// Exercise the same storage service used by the WebView2 host, on a disposable profile.
internal static class StorageChecks
{
    private static JsonElement Json(object? value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool value, string reason)
    {
        if (!value) throw new InvalidOperationException(reason);
    }

    private static void MustFail(Action operation)
    {
        try { operation(); }
        catch (IOException) { return; }
        throw new InvalidOperationException("This operation should have preserved the existing files and failed.");
    }

    public static void Main()
    {
        string sandbox = Directory.CreateTempSubdirectory("Inkrail-storage-").FullName;
        try { CheckStorage(sandbox); }
        finally { Directory.Delete(sandbox, true); }
        Console.WriteLine("Passed Windows library compatibility, recovery, relocation, conflict and retention checks.");
    }

    private static void CheckStorage(string sandbox)
    {
        string profile = Path.Combine(sandbox, "profile");
        var store = new Library(profile);
        Check(Json(store.Boot()).GetProperty("available").GetBoolean(), "First launch failed.");
        string original = store.Location;
        string id = Guid.NewGuid().ToString("D").ToUpperInvariant();
        string date = "2026-01-31T19:05:34Z";
        JsonElement Letter(string text) => Json(new { id, text, privateTitle = "My letter", createdAt = date, modifiedAt = date,
            formatting = new[] { new { location = 0, length = 1, emphasis = 1 } } });
        var key = Json(new { id });
        string page = Path.Combine(original, "Letters", id + ".json");
        store.Dispatch("save", Letter("One"));
        store.Dispatch("save", Letter("Two"));
        Check(JsonDocument.Parse(File.ReadAllBytes(page + ".bak")).RootElement.GetProperty("text").GetString() == "One", "Missing previous revision.");

        File.WriteAllText(page, "broken JSON");
        store = new Library(profile);
        var recovered = Json(store.Boot());
        Check(recovered.GetProperty("pages")[0].GetProperty("text").GetString() == "One", "Backup recovery failed.");
        Check(recovered.GetProperty("warnings").GetArrayLength() > 0, "Backup recovery was silent.");
        store.Dispatch("save", Letter("Three"));
        Check(Directory.GetFiles(Path.Combine(original, "Recovery")).Any(file => File.ReadAllText(file) == "broken JSON"),
              "The damaged primary was discarded.");

        File.WriteAllBytes(page, JsonSerializer.SerializeToUtf8Bytes(Letter("External edit")));
        MustFail(() => store.Dispatch("save", Letter("Unseen change")));
        MustFail(() => store.Dispatch("trash", key));
        store = new Library(profile);
        store.Boot();
        store.Dispatch("settings", Json(new { preferences = new { typewriterSound = "office" }, selectedID = id }));
        var anotherWindow = new Library(profile);
        anotherWindow.Boot();
        string dest = Directory.CreateDirectory(Path.Combine(sandbox, "custom library")).FullName;
        store.Relocate(dest);
        MustFail(() => anotherWindow.Dispatch("save", Letter("Edit in a stale window")));
        string moved = Path.Combine(dest, "Letters", id + ".json");
        Check(File.ReadAllBytes(page).SequenceEqual(File.ReadAllBytes(moved)), "Relocation changed the letter.");
        Check(File.Exists(moved + ".bak"), "Relocation missed the backup.");
        store = new Library(profile);
        var reopened = Json(store.Boot());
        Check(store.Location == dest && reopened.GetProperty("settings").GetProperty("selectedID").GetString() == id,
              "The custom library or selection was lost.");

        store.Dispatch("trash", key);
        string trash = Path.Combine(dest, "Recently Deleted");
        string trashed = Path.Combine(trash, id + ".json");
        string receipt = Path.Combine(trash, id + ".trashinfo");
        Check(File.Exists(trashed) && File.Exists(trashed + ".bak") && File.Exists(receipt), "Incomplete trash transfer.");
        // Simulate interruption while restoring, just after moving the backup.
        File.WriteAllText(Path.Combine(trash, id + ".transfer"), "restore-v1");
        File.Move(trashed + ".bak", moved + ".bak");
        store = new Library(profile);
        store.Boot();
        var deleted = Json(store.Dispatch("list", Json(new { trash = true }))).GetProperty("pages");
        Check(deleted.GetArrayLength() == 1 && File.Exists(trashed + ".bak"), "Interrupted restore split the pair.");
        store.Dispatch("restore", key);
        Check(File.Exists(moved) && !File.Exists(receipt), "Restore did not clear the receipt.");
        store.Dispatch("trash", key);
        // A pre-journal release could leave the backup behind in Letters.
        File.Move(trashed + ".bak", moved + ".bak");
        store = new Library(profile);
        Check(Json(store.Boot()).GetProperty("pages").GetArrayLength() == 0 && File.Exists(trashed + ".bak"),
              "An interrupted legacy delete appeared as an active letter.");
        File.Delete(receipt);
        store.Dispatch("cleanup", default);
        Check(File.Exists(trashed) && File.Exists(receipt), "A legacy deleted letter did not receive a grace period.");
        File.WriteAllBytes(receipt, JsonSerializer.SerializeToUtf8Bytes(new { id, deletedAt = 1 }));
        store.Dispatch("cleanup", default);
        Check(File.Exists(trashed), "A malformed deletion record expired a letter.");
        File.WriteAllBytes(receipt, JsonSerializer.SerializeToUtf8Bytes(new { version = 1, id, deletedAt = DateTimeOffset.UtcNow.AddDays(-31).ToUnixTimeSeconds() }));
        var expired = Json(store.Dispatch("cleanup", default));
        Check(expired.GetProperty("removedIDs")[0].GetString() == id && !File.Exists(trashed + ".bak") && !File.Exists(receipt),
              "Retention left part of an expired letter.");
        Check(File.Exists(page), "Cleaning trash touched the former library.");

        Directory.Move(dest, dest + ".offline");
        store = new Library(profile);
        Check(!Json(store.Boot()).GetProperty("available").GetBoolean() && !Directory.Exists(dest),
              "A disconnected library was silently recreated.");
        string settings = Path.Combine(profile, "preferences.json");
        File.WriteAllText(settings, "{invalid settings");
        store = new Library(profile);
        Check(!Json(store.Boot()).GetProperty("available").GetBoolean(), "Unusable settings opened the wrong library.");
        MustFail(() => store.Dispatch("settings", Json(new { preferences = new { }, selectedID = id })));
        Check(File.ReadAllText(settings) == "{invalid settings", "Unusable settings were overwritten.");
    }
}
