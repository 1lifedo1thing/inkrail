using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Inkrail.Windows;

// The portable and Store builds share the v0.1.1 profile and letter formats.
internal sealed class Library
{
    private readonly string profile;
    private string SettingsFile => Path.Combine(profile, "preferences.json");
    private string Letters => Path.Combine(Location, "Letters");
    private string Trash => Path.Combine(Location, "Recently Deleted");
    public string Location { get; private set; }

    private JsonObject settings = new();
    private string? settingsHash;
    private bool settingsReady;
    private bool available;

    private sealed record Revision(string? Primary, string? RecoveredBackup = null);
    private readonly Dictionary<Guid, Revision> revisions = new();

    public Library(string profileDirectory)
    {
        profile = Path.GetFullPath(profileDirectory);
        Location = Path.Combine(profile, "Library");
    }

    private static string? Hash(byte[]? bytes) =>
        bytes == null ? null : Convert.ToHexString(SHA256.HashData(bytes));

    private static bool IsFile(string path)
    {
        try
        {
            var attributes = File.GetAttributes(path);
            if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
                throw new IOException($"Expected a regular file at {path}.");
            return true;
        }
        catch (FileNotFoundException) { return false; }
    }

    private static byte[]? ReadOptional(string path) =>
        IsFile(path) ? File.ReadAllBytes(path) : null;

    private static void RequireDirectory(string path)
    {
        var attributes = File.GetAttributes(path);
        if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != FileAttributes.Directory)
            throw new IOException($"Expected a library folder at {path}.");
    }

    private static void CreateFolder(string path)
    {
        Directory.CreateDirectory(path);
        RequireDirectory(path);
    }

    private void CheckFolders()
    {
        RequireDirectory(Location);
        RequireDirectory(Letters);
        RequireDirectory(Trash);
    }

    // Stage on the same volume. The target is always either the old file or the complete new one.
    private static void WriteFile(string path, byte[] bytes, bool replace, string? backup = null)
    {
        string temp = Path.Combine(Path.GetDirectoryName(path)!, $".inkrail-{Guid.NewGuid():N}.tmp");
        try
        {
            using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                output.Write(bytes);
                output.Flush(true);
            }
            if (replace) File.Replace(temp, path, backup);
            else File.Move(temp, path);
        }
        finally { File.Delete(temp); }
    }

    private static JsonObject ReadObject(byte[] bytes) =>
        JsonNode.Parse(bytes) as JsonObject ?? throw new InvalidDataException("Expected a JSON object.");

    public object Boot()
    {
        var warnings = new List<string>();
        try
        {
            using var profileLock = LockPath(profile);
            Directory.CreateDirectory(profile);
            byte[]? original = ReadOptional(SettingsFile);
            settings = original == null ? new JsonObject() : ReadObject(original);
            if (settings["libraryLocation"] is JsonNode location && location.GetValue<string>() is { Length: > 0 } custom)
            {
                if (!Path.IsPathFullyQualified(custom)) throw new InvalidDataException("The saved library path must be absolute.");
                Location = Path.GetFullPath(custom);
            }
            else
            {
                CreateFolder(Location);
                CreateFolder(Letters);
                CreateFolder(Trash);
            }
            settingsHash = Hash(original);
            settingsReady = true;
            CheckFolders();
            using var guard = LockPath(Location);
            var removed = new List<string>();
            var trashWarnings = new List<string>();
            Cleanup(removed, trashWarnings);
            var pages = ListPages(false, warnings);
            available = true;
            return new { settings, available, path = Location, pages, warnings, trashWarning = string.Join("\n", trashWarnings) };
        }
        catch (Exception error)
        {
            available = false;
            return new { settings, available, path = Location, error = error.Message };
        }
    }

    // Synchronize cooperating Inkrail processes across both Windows architectures.
    private static IDisposable LockPath(string location)
    {
        string key = Hash(Encoding.UTF8.GetBytes(Path.TrimEndingDirectorySeparator(location).ToUpperInvariant()))!;
        var mutex = new Mutex(false, "Inkrail-Library-" + key);
        try
        {
            try
            {
                if (!mutex.WaitOne(TimeSpan.FromSeconds(3))) throw new IOException("The library is busy.");
            }
            catch (AbandonedMutexException) { /* This thread now owns the recovered mutex. */ }
            return new LibraryLock(mutex);
        }
        catch { mutex.Dispose(); throw; }
    }

    private sealed class LibraryLock(Mutex mutex) : IDisposable
    {
        public void Dispose() { mutex.ReleaseMutex(); mutex.Dispose(); }
    }

    private static string Name(Guid id) => id.ToString("D").ToUpperInvariant();
    private string PagePath(Guid id, bool trash) => Path.Combine(trash ? Trash : Letters, Name(id) + ".json");
    private string Receipt(Guid id) => Path.Combine(Trash, Name(id) + ".trashinfo");
    private string Marker(Guid id) => Path.Combine(Trash, Name(id) + ".transfer");
    private static Guid PageID(JsonElement page) => page.GetProperty("id").GetGuid();

    private static JsonElement Decode(byte[] bytes, Guid id)
    {
        var page = JsonSerializer.Deserialize<JsonElement>(bytes);
        if (page.ValueKind != JsonValueKind.Object || !page.TryGetProperty("id", out var value) ||
            value.ValueKind != JsonValueKind.String || !value.TryGetGuid(out var actual) || actual != id ||
            !page.TryGetProperty("text", out var text) || text.ValueKind != JsonValueKind.String ||
            !page.TryGetProperty("createdAt", out var created) || !page.TryGetProperty("modifiedAt", out var modified))
            throw new InvalidDataException($"Unrecognized letter or mismatched ID for {Name(id)}.");
        var first = ReadDate(created);
        var last = ReadDate(modified);
        if (created.ValueKind == JsonValueKind.String && modified.ValueKind == JsonValueKind.String) return page;
        // Foundation's older JSON date representation counts seconds from 1 January 2001.
        var normalized = ReadObject(bytes);
        normalized["createdAt"] = first;
        normalized["modifiedAt"] = last;
        return JsonSerializer.SerializeToElement(normalized);
    }

    private static DateTimeOffset ReadDate(JsonElement date)
    {
        if (date.ValueKind == JsonValueKind.String && date.TryGetDateTimeOffset(out var time)) return time;
        if (date.ValueKind == JsonValueKind.Number && date.TryGetDouble(out double seconds)
            && seconds is >= -63113904000 and < 252423993600)
            return DateTimeOffset.FromUnixTimeSeconds(978307200).AddSeconds(seconds);
        throw new InvalidDataException("Invalid letter date.");
    }

    private static bool TryDecode(byte[]? bytes, Guid id, out JsonElement page)
    {
        page = default;
        if (bytes == null) return false;
        try { page = Decode(bytes, id); return true; }
        catch (JsonException) { return false; }
        catch (InvalidDataException) { return false; }
    }

    private static IEnumerable<Guid> PageIDs(string folder)
    {
        var ids = new HashSet<Guid>();
        foreach (var path in Directory.EnumerateFileSystemEntries(folder))
        {
            string name = Path.GetFileName(path);
            if (name.Length <= 36 || !Guid.TryParseExact(name[..36], "D", out var id)) continue;
            if (name[36..] is ".json" or ".json.bak" or ".transfer") ids.Add(id);
        }
        return ids;
    }

    private List<JsonElement> ListPages(bool trash, List<string> warnings)
    {
        var pages = new List<JsonElement>();
        foreach (var id in PageIDs(trash ? Trash : Letters))
        {
            try
            {
                Reconcile(id);
                string path = PagePath(id, trash);
                byte[]? primary = ReadOptional(path);
                string? backupHash = null;
                if (!TryDecode(primary, id, out var page))
                {
                    byte[]? backup = ReadOptional(path + ".bak");
                    if (backup == null && primary == null) continue;
                    if (!TryDecode(backup, id, out page))
                        throw new InvalidDataException($"Could not read the letter {Name(id)} or its backup.");
                    warnings.Add($"Opened the previous saved copy of {Name(id)}.");
                    backupHash = Hash(backup);
                }
                if (!trash) revisions.TryAdd(id, new Revision(Hash(primary), backupHash));
                pages.Add(page);
            }
            catch (Exception error) { warnings.Add(error.Message); }
        }
        return pages.OrderByDescending(page => page.GetProperty("modifiedAt").GetDateTimeOffset()).ToList();
    }

    private static void Changed() => throw new IOException("The saved copy changed. Export your edits and reopen Inkrail.");

    private void VerifyRevision(Guid id, string path, byte[]? primary)
    {
        revisions.TryGetValue(id, out var known);
        if (Hash(primary) != known?.Primary) Changed();
        if (known?.RecoveredBackup != null && Hash(ReadOptional(path + ".bak")) != known.RecoveredBackup) Changed();
    }

    private string RecoveryPath(Guid id, string extension)
    {
        string recovery = Path.Combine(Location, "Recovery");
        CreateFolder(recovery);
        return Path.Combine(recovery, $"{Name(id)}-{Guid.NewGuid():N}.{extension}");
    }

    private void Save(JsonElement page)
    {
        Guid id = PageID(page);
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(page);
        Decode(bytes, id);
        Reconcile(id);
        string path = PagePath(id, false);
        byte[]? previous = ReadOptional(path);
        VerifyRevision(id, path, previous);
        bool hasBackup = IsFile(path + ".bak");
        if (!revisions.ContainsKey(id) && (hasBackup || IsFile(PagePath(id, true)) || IsFile(PagePath(id, true) + ".bak")))
            throw new IOException("A letter with this ID already exists.");
        // ReplaceFile captures the bytes actually displaced, including an outside edit
        // that raced with the revision check. Keep the readable .bak when repairing.
        string? displaced = previous == null ? null :
            TryDecode(previous, id, out _) ? path + ".bak" : RecoveryPath(id, "damaged");
        WriteFile(path, bytes, previous != null, displaced);
        revisions[id] = new Revision(Hash(bytes));
        if (displaced != null && Hash(ReadOptional(displaced)) != Hash(previous))
        {
            string conflict = RecoveryPath(id, "conflict");
            File.Copy(displaced, conflict);
            throw new IOException($"Your edits were saved. Another version changed during the save and was preserved at {conflict}.");
        }
    }

    private void CommitSettings(JsonObject next)
    {
        if (!settingsReady) throw new IOException("The original preferences could not be read.");
        byte[]? previous = ReadOptional(SettingsFile);
        if (Hash(previous) != settingsHash)
            throw new IOException("Preferences changed on disk. Reopen Inkrail before saving.");
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(next);
        string? displaced = previous == null ? null : SettingsFile + "." + Guid.NewGuid().ToString("N") + ".previous";
        WriteFile(SettingsFile, bytes, previous != null, displaced);
        settingsHash = Hash(bytes);
        settings = next;
        if (displaced != null && Hash(ReadOptional(displaced)) == Hash(previous))
            File.Delete(displaced);
    }

    public object? Dispatch(string operation, JsonElement args)
    {
        using var profileLock = LockPath(profile);
        using var guard = LockPath(Location);
        if (operation == "settings")
        {
            var next = (JsonObject)settings.DeepClone();
            var preferences = next["preferences"] as JsonObject ?? new JsonObject();
            foreach (var field in args.GetProperty("preferences").EnumerateObject())
                preferences[field.Name] = JsonNode.Parse(field.Value.GetRawText());
            next["preferences"] = preferences;
            next["selectedID"] = JsonNode.Parse(args.GetProperty("selectedID").GetRawText());
            CommitSettings(next);
            return null;
        }
        if (!available) throw new IOException("The library is unavailable.");
        CheckCurrentLocation();
        CheckFolders();
        var warnings = new List<string>();
        switch (operation)
        {
            case "save": Save(args); return null;
            case "list": return new { pages = ListPages(args.GetProperty("trash").GetBoolean(), warnings), warnings };
            case "cleanup":
                var removedIDs = new List<string>();
                Cleanup(removedIDs, warnings);
                return new { warnings, removedIDs };
            case "trash":
            case "restore": MoveLetter(PageID(args), operation == "trash"); return null;
            default: throw new ArgumentException($"Unknown library operation: {operation}");
        }
    }

    private void WriteReceipt(Guid id, DateTimeOffset now)
    {
        string path = Receipt(id);
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(new { version = 1, id = Name(id), deletedAt = now.ToUnixTimeSeconds() });
        WriteFile(path, bytes, IsFile(path));
    }

    private void MoveLetter(Guid id, bool deleting)
    {
        Reconcile(id);
        string from = PagePath(id, !deleting), to = PagePath(id, deleting);
        if (IsFile(to) || IsFile(to + ".bak")) throw new IOException("The destination already contains this letter.");
        byte[]? primary = ReadOptional(from);
        byte[]? backup = ReadOptional(from + ".bak");
        if (deleting) VerifyRevision(id, from, primary);
        if (!TryDecode(primary, id, out _))
        {
            if (!TryDecode(backup, id, out _)) throw new InvalidDataException("Neither saved copy of this letter is readable.");
            WriteFile(from, backup!, primary != null, primary != null ? RecoveryPath(id, "damaged") : null);
            primary = backup;
            if (deleting) revisions[id] = new Revision(Hash(primary));
        }
        if (deleting) WriteReceipt(id, DateTimeOffset.UtcNow);
        WriteFile(Marker(id), Encoding.UTF8.GetBytes(deleting ? "trash-v1" : "restore-v1"), false);
        try
        {
            if (backup != null) File.Move(from + ".bak", to + ".bak");
            File.Move(from, to);
        }
        finally { FinishTransfer(id); }
        if (deleting) revisions.Remove(id);
        else revisions[id] = new Revision(Hash(primary));
    }

    // The primary rename commits a move. Roll a prematurely moved backup back on restart.
    private void FinishTransfer(Guid id)
    {
        string marker = Marker(id);
        byte[]? journal = ReadOptional(marker);
        if (journal == null) return;
        bool deleting = Encoding.UTF8.GetString(journal) switch {
            "trash-v1" => true, "restore-v1" => false, _ => throw new InvalidDataException($"Unrecognized transfer at {marker}.")
        };
        string from = PagePath(id, !deleting), to = PagePath(id, deleting);
        bool pending = IsFile(from);
        if (pending == IsFile(to)) throw new IOException($"The interrupted transfer needs attention at {marker}.");
        if (pending && IsFile(to + ".bak")) File.Move(to + ".bak", from + ".bak");
        if (pending == deleting && IsFile(Receipt(id))) File.Delete(Receipt(id));
        File.Delete(marker);
    }

    private DateTimeOffset? ReadDeletionDate(Guid id)
    {
        byte[]? metadata = ReadOptional(Receipt(id));
        if (metadata == null) return null;
        JsonElement receipt;
        try { receipt = JsonSerializer.Deserialize<JsonElement>(metadata); }
        catch (JsonException) { return null; }
        if (receipt.ValueKind != JsonValueKind.Object ||
            !receipt.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out int number)) return null;
        if (number != 1) throw new InvalidDataException("Unrecognized deletion record version.");
        if (!receipt.TryGetProperty("id", out var key) || key.ValueKind != JsonValueKind.String ||
            !key.TryGetGuid(out var actual) || actual != id || !receipt.TryGetProperty("deletedAt", out var date)) return null;
        if (date.ValueKind == JsonValueKind.String && date.TryGetDateTimeOffset(out var time)) return time;
        if (date.ValueKind == JsonValueKind.Number && date.TryGetDouble(out var seconds) &&
            seconds is >= -62135596800 and < 253402300800)
            return DateTimeOffset.FromUnixTimeSeconds((long)seconds);
        return null;
    }

    private void Reconcile(Guid id)
    {
        FinishTransfer(id);
        // Earlier versions could move a primary without its backup and without a journal.
        string active = PagePath(id, false), deleted = PagePath(id, true);
        string activeBackup = active + ".bak", trashBackup = deleted + ".bak";
        if (!IsFile(active) && IsFile(deleted) && IsFile(activeBackup))
        {
            var current = Decode(File.ReadAllBytes(deleted), id);
            var previous = Decode(File.ReadAllBytes(activeBackup), id);
            var priorDate = ReadDate(previous.GetProperty("modifiedAt"));
            var deletionDate = ReadDeletionDate(id);
            if (IsFile(trashBackup) || deletionDate == null || deletionDate < priorDate ||
                ReadDate(current.GetProperty("createdAt")) != ReadDate(previous.GetProperty("createdAt")) ||
                ReadDate(current.GetProperty("modifiedAt")) < priorDate)
                throw new IOException($"A split letter needs attention at {activeBackup}.");
            File.Move(activeBackup, trashBackup);
        }
        else if (IsFile(active) && !IsFile(deleted) && IsFile(trashBackup))
        {
            byte[] candidate = File.ReadAllBytes(trashBackup);
            var prior = Decode(candidate, id);
            if (TryDecode(File.ReadAllBytes(active), id, out var current) &&
                (ReadDate(current.GetProperty("createdAt")) != ReadDate(prior.GetProperty("createdAt")) ||
                 ReadDate(current.GetProperty("modifiedAt")) < ReadDate(prior.GetProperty("modifiedAt"))))
                throw new IOException($"A split letter needs attention at {trashBackup}.");
            byte[]? other = ReadOptional(activeBackup);
            if (other == null) File.Move(trashBackup, activeBackup);
            else if (other.SequenceEqual(candidate)) File.Delete(trashBackup);
            else if (!TryDecode(other, id, out _))
            {
                WriteFile(activeBackup, candidate, true, RecoveryPath(id, "damaged"));
                File.Delete(trashBackup);
            }
            else throw new IOException($"Two different backups were kept for {Name(id)}.");
        }
    }

    private void Cleanup(List<string> removed, List<string> warnings)
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var id in PageIDs(Trash))
        {
            try
            {
                Reconcile(id);
                string path = PagePath(id, true);
                byte[]? main = ReadOptional(path), backup = ReadOptional(path + ".bak");
                if (main == null && backup == null) continue;
                if (IsFile(PagePath(id, false)) || IsFile(PagePath(id, false) + ".bak"))
                    throw new IOException("Both Letters and Recently Deleted contain this ID.");
                // Leave damaged or mismatched pairs available for manual recovery.
                if ((main != null && !TryDecode(main, id, out _)) || (backup != null && !TryDecode(backup, id, out _)))
                    throw new InvalidDataException("A saved copy could not be identified.");
                DateTimeOffset? deleted = ReadDeletionDate(id);
                if (deleted == null) { WriteReceipt(id, now); continue; }
                if (now - deleted < TimeSpan.FromDays(30)) continue;
                File.Delete(path + ".bak");
                File.Delete(path);
                File.Delete(Receipt(id));
                removed.Add(Name(id));
            }
            catch (Exception error) { warnings.Add($"Recently Deleted kept {Name(id)}: {error.Message}"); }
        }
    }

    private static Dictionary<string, string?> Inventory(string root)
    {
        var entries = new Dictionary<string, string?>();
        void Visit(string directory)
        {
            foreach (string item in Directory.EnumerateFileSystemEntries(directory))
            {
                var attributes = File.GetAttributes(item);
                string relative = Path.GetRelativePath(root, item);
                if ((attributes & FileAttributes.ReparsePoint) != 0) throw new IOException($"The library contains a link at {relative}.");
                if ((attributes & FileAttributes.Directory) != 0)
                {
                    entries.Add(relative, null);
                    Visit(item);
                }
                else
                {
                    using var stream = File.OpenRead(item);
                    entries.Add(relative, Convert.ToHexString(SHA256.HashData(stream)));
                }
            }
        }
        Visit(root);
        return entries;
    }

    private static string PhysicalDirectory(DirectoryInfo folder)
    {
        string path = folder.Parent is null ? folder.FullName
            : Path.Combine(PhysicalDirectory(folder.Parent), folder.Name);
        var current = new DirectoryInfo(path);
        return current.Attributes.HasFlag(FileAttributes.ReparsePoint)
            ? (current.ResolveLinkTarget(returnFinalTarget: true) ?? current).FullName : path;
    }

    private void CheckCurrentLocation()
    {
        byte[]? current = ReadOptional(SettingsFile);
        if (Hash(current) == settingsHash) return;
        string? saved = current == null ? null : ReadObject(current)["libraryLocation"]?.GetValue<string>();
        string root = string.IsNullOrEmpty(saved) ? Path.Combine(profile, "Library") : Path.GetFullPath(saved);
        if (!string.Equals(Path.TrimEndingDirectorySeparator(root), Path.TrimEndingDirectorySeparator(Location),
            StringComparison.OrdinalIgnoreCase))
            throw new IOException("Another copy of Inkrail changed the library folder. Export pending edits and reopen Inkrail.");
    }

    public void Relocate(string destination)
    {
        using var profileLock = LockPath(profile);
        using var guard = LockPath(Location);
        if (!available) throw new IOException("The library is unavailable.");
        CheckCurrentLocation();
        CheckFolders();
        destination = Path.TrimEndingDirectorySeparator(Path.GetFullPath(destination));
        string source = Path.TrimEndingDirectorySeparator(PhysicalDirectory(new DirectoryInfo(Location)));
        string targetRoot = Path.TrimEndingDirectorySeparator(PhysicalDirectory(new DirectoryInfo(destination)));
        static string Prefix(string folder) => Path.EndsInDirectorySeparator(folder) ? folder : folder + Path.DirectorySeparatorChar;
        if (Prefix(source).StartsWith(Prefix(targetRoot), StringComparison.OrdinalIgnoreCase) ||
            Prefix(targetRoot).StartsWith(Prefix(source), StringComparison.OrdinalIgnoreCase))
            throw new IOException("Choose a folder outside the current library.");
        if (Directory.EnumerateFileSystemEntries(targetRoot).Any()) throw new IOException("Choose an empty destination folder.");

        var original = Inventory(source);
        foreach (var (relative, digest) in original)
        {
            string target = Path.Combine(targetRoot, relative);
            if (digest == null) Directory.CreateDirectory(target);
            else File.Copy(Path.Combine(source, relative), target, overwrite: false);
        }
        foreach (var root in new[] { source, targetRoot })
        {
            var snapshot = Inventory(root);
            if (snapshot.Count != original.Count || original.Any(p => !snapshot.TryGetValue(p.Key, out var value) || p.Value != value))
                throw new IOException("The library copy could not be verified. The original folder remains selected.");
        }
        // A readable copy can still be an unusable library on a read-only volume.
        foreach (string folder in new[] { targetRoot, Path.Combine(targetRoot, "Letters"), Path.Combine(targetRoot, "Recently Deleted") })
        {
            using var probe = new FileStream(Path.Combine(folder, $".inkrail-{Guid.NewGuid():N}.tmp"),
                FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.DeleteOnClose);
            probe.WriteByte(1);
            probe.Flush(true);
        }
        var next = (JsonObject)settings.DeepClone();
        next["libraryLocation"] = destination;
        CommitSettings(next);
        Location = destination;
    }
}
