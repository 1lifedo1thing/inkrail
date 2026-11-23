# Choose where Inkrail saves your letters

[Back to the user guide](../README.md#your-letters)

Inkrail saves your library locally. **Make it yours → Storage** shows the
current folder, including a custom location.

| Platform | Default library folder | Open the current folder |
| --- | --- | --- |
| macOS | `~/Library/Application Support/Inkrail/` | **Writing → Show Local Files** |
| Windows | `%APPDATA%\Inkrail\Library` | **Make it yours → Storage → Show in File Explorer** |

To move one letter between Mac and Windows, choose **File → Export Markdown…**
on Mac. On Windows, press **Alt+F** and choose **Export Markdown…**. Import the saved
`.md` file with **⌘O** on Mac or **Ctrl+O** on Windows. Use **Export Text…**
for a plain-text copy.

## Choose a different folder

1. Open **Make it yours → Storage → Change Location…**.
2. Choose an empty folder, or create a new folder in the chooser. Pick a
   writable folder that will be available whenever you open Inkrail.
3. Inkrail saves any pending writing, copies the complete library and verifies
   the copied contents before switching locations. If saving or copying fails,
   the current location remains selected and Inkrail shows an error.
4. Check the new path in Storage. Future saves, deletion and restore use that
   folder, including after you quit and reopen the app.

Use one running copy of Inkrail per library. Back up the whole current library
folder. On Windows, letters are in its **Letters** subfolder. Windows
preferences live separately in `%APPDATA%\Inkrail\preferences.json`.

### Windows Store upgrades

The updated Store package saves letters in the same default folder as the
portable app. Letters created there survive uninstall. When upgrading an older
Store installation, install the update over the existing app and open it once
before uninstalling. On first launch it can recover files that Windows kept in
the previous package’s private storage. Uninstalling the older package first
can erase those files.

If the old Store and portable profiles contain different versions of the same
file, the upgrade keeps the Store version active and saves the other version
beside it. The recovery notice lists those paths. Include them when backing up
the library.

### macOS storage details

On Mac, the complete library includes **Letters**, **Recently Deleted**, previous saved
copies (`.json.bak`) and any **Recovery** files. Inkrail leaves the previous
folder intact as a safety copy. It no longer receives updates, so use the new
folder for backups and recovery after making further edits.

The destination must be empty. Inkrail does not merge libraries, overwrite
existing files, or allow a destination inside the current library. If a copy
fails, files already copied may remain in the destination; your original
library remains in place. Choose another empty folder when retrying.

Appearance and sound preferences stay in macOS settings on this Mac. You
can choose a folder in iCloud Drive. iCloud handles syncing outside Inkrail,
and sync behavior is not guaranteed. Keep a separate backup and use one Mac
at a time to edit the library.

If another app, backup or sync service replaces an open letter, Inkrail checks
its saved contents before writing. If Inkrail reports that the saved copy
changed, export your open edits as Markdown, then reopen Inkrail to see the
version on disk. Import your exported file to keep both versions in the letter box.
On disks that support atomic file exchange, Inkrail can also detect a change
at the instant it replaces the file. In that case the open edits are already
saved, and the notice gives the path to the other version.

If a letter’s main file is missing or damaged, Inkrail looks for its matching
`.json.bak` and shows a notice when it opens that copy. This also applies in
Recently Deleted. Restore brings the readable copy back to Letters.

## Recently Deleted keeps letters for 30 days

Open the letter box with **⇧⌘O** on Mac or **Ctrl+Shift+O** on Windows.
Choose **Recently deleted**, then **Restore** beside the letter within
30 days of deletion.

### macOS cleanup details

After 30 days, the Mac app permanently removes the deleted letter and its matching previous
saved copy. It checks when opening the app, hourly while running, and before
showing Recently Deleted or restoring a letter. If the app is closed at expiry,
cleanup waits until the next launch.

The countdown uses the deletion date, not the letter's last edit date. Letters
deleted before this feature get 30 days from their first check in the updated
app. Missing or invalid deletion dates also receive a fresh window. Restore
stops the countdown; a later deletion starts it again.

This cleanup applies only to Recently Deleted in the current library. Active
letters, their `.json.bak` files, Recovery files and old library folders kept
after changing location are unaffected. Deletion dates move with the library,
so choosing a custom location does not reset the countdown.

Small `.trashinfo` files beside deleted letters record their deletion dates.
Keep them and any `.transfer` files with the library when backing it up.
Inkrail checks for interrupted moves before applying the deadline and reunites
matching files when it can verify them. If cleanup fails, the app shows a notice
in Recently Deleted and retries later.

## Keep your library available

Use **Change Location…** to move your library. Inkrail remembers the selected
path and reports when the folder is unavailable.

Reconnect an external disk or put the folder back at the selected path, then
reopen Inkrail. If you have written while storage was unavailable, **export
that writing before closing**. If a save fails because the disk is full or
unwritable, free space or fix access, then save again. A failed save is never
reported as successful.

Include the current library folder in your regular backups. Previous saved
copies and the old folder left after relocation are useful fallbacks, but they
do not replace a separate backup.

## If you used the earlier symbolic-link workaround

On macOS, you can keep a working symbolic link. The
location chooser can copy the library from the linked location into a new,
empty folder. After a successful change, Inkrail uses the new path directly.
Keep both the old link and its target until you have checked your new library
and backups; neither is removed by Inkrail.

If returning to a previously used folder, keep its old contents as a separate
backup first and select an empty destination. The chooser will not overwrite
the earlier library with newer writing.
