using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Inkrail.Windows;

internal static class FileDialogs
{
    private static readonly UTF8Encoding Utf8 = new(false, true);

    internal static object? Import(IWin32Window owner)
    {
        using var dialog = new OpenFileDialog {
            Title = "Import a letter", CheckFileExists = true, RestoreDirectory = true,
            Filter = "Text and Markdown files|*.txt;*.md;*.markdown;*.mdown;*.mkd|All files|*.*"
        };
        if (dialog.ShowDialog(owner) != DialogResult.OK) return null;
        string text;
        byte[] bytes = File.ReadAllBytes(dialog.FileName);
        ReadOnlySpan<byte> content = bytes;
        try
        {
            if (content.StartsWith(Encoding.Unicode.Preamble))
                text = new UnicodeEncoding(false, false, true).GetString(content[2..]);
            else if (content.StartsWith(Encoding.BigEndianUnicode.Preamble))
                text = new UnicodeEncoding(true, false, true).GetString(content[2..]);
            else
                text = Utf8.GetString(content.StartsWith(Encoding.UTF8.Preamble) ? content[3..] : content);
        }
        catch (DecoderFallbackException error)
        {
            throw new IOException("Save a copy in UTF-8 or in UTF-16 with a byte order mark and try again.", error);
        }
        string extension = Path.GetExtension(dialog.FileName).ToLowerInvariant();
        return new { text, markdown = extension is ".md" or ".markdown" or ".mdown" or ".mkd" };
    }

    private static string ExportName(string body)
    {
        string first = Regex.Split(body, @"\r\n|[\r\n\v\f\u0085\u2028\u2029]")
            .Select(s => s.Trim()).FirstOrDefault(s => s.Length != 0) ?? "Untitled letter";
        var elements = StringInfo.GetTextElementEnumerator(first);
        var title = new StringBuilder();
        for (int i = 0; i < 64 && elements.MoveNext(); i++) title.Append(elements.GetTextElement());
        var invalid = Path.GetInvalidFileNameChars();
        string safe = string.Concat(title.ToString().Select(c => c == '%' || invalid.Contains(c) ? '-' : c))
            .Trim().Trim('.').Trim();
        if (safe.Length == 0) return "Untitled letter";
        if (Regex.IsMatch(safe, @"^(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) safe = "_" + safe;
        return safe;
    }

    internal static bool Export(IWin32Window owner, JsonElement args)
    {
        bool markdown = args.GetProperty("markdown").GetBoolean();
        string extension = markdown ? "md" : "txt";
        using var dialog = new SaveFileDialog {
            Title = "Keep a copy of your letter", DefaultExt = extension,
            FileName = ExportName(args.GetProperty("body").GetString() ?? "") + "." + extension,
            Filter = markdown ? "Markdown file|*.md" : "Text file|*.txt",
            OverwritePrompt = true, RestoreDirectory = true
        };
        if (dialog.ShowDialog(owner) != DialogResult.OK) return false;
        string path = Path.GetFullPath(dialog.FileName);
        string temporary = Path.Combine(Path.GetDirectoryName(path)!, ".inkrail-export-" + Guid.NewGuid().ToString("N"));
        try
        {
            File.WriteAllText(temporary, args.GetProperty("text").GetString() ?? "", Utf8);
            File.Move(temporary, path, true);
            return true;
        }
        finally { File.Delete(temporary); }
    }

    internal static string? ChangeLocation(IWin32Window owner, Library library)
    {
        using var dialog = new FolderBrowserDialog {
            Description = "Choose an empty folder for your Inkrail library", UseDescriptionForTitle = true,
            ShowNewFolderButton = true
        };
        if (dialog.ShowDialog(owner) != DialogResult.OK) return null;
        library.Relocate(dialog.SelectedPath);
        return library.Location;
    }
}
