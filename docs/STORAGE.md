# Choose where Inkrail saves your letters

[Back to the user guide](../README.md#your-letters)

Inkrail saves your library locally. The default folder is:

```text
~/Library/Application Support/Inkrail/
```

Open **Make it yours (⌘,) → Storage** to see your current location, or choose
**Writing → Show Local Files** to open it in Finder. Export Text and Export
Markdown save individual copies; they do not change the library location.

## Choose a different folder

1. Open **Make it yours → Storage → Change Location…**.
2. Choose an empty folder, or create a new folder in the chooser. Pick a
   writable folder that will be available whenever you open Inkrail. An
   iCloud Drive folder can be selected as the library location, but Inkrail
   does not provide built-in syncing; iCloud handles any syncing outside the
   app, and sync behavior is not guaranteed.
3. Inkrail saves any pending writing, copies the complete library and verifies
   the copied contents before switching locations. If saving or copying fails,
   the current location remains selected and Inkrail shows an error.
4. Check the new path in Storage. Future saves, deletion and restore use that
   folder, including after you quit and reopen the app.

The complete library includes **Letters**, **Recently Deleted**, previous saved
copies (`.json.bak`) and any **Recovery** files. Inkrail leaves the previous
folder intact as a safety copy. It no longer receives updates, so use the new
folder for backups and recovery after making further edits.

The destination must be empty. Inkrail does not merge libraries, overwrite
existing files, or allow a destination inside the current library. If a copy
fails, files already copied may remain in the destination; your original
library remains in place. Choose another empty folder when retrying.

Appearance and sound preferences stay in macOS settings on this Mac. They are
separate from the letter files. Inkrail does not provide built-in iCloud sync
or support simultaneous editing from multiple Macs. Keep a separate backup of
your library.

## Recently Deleted keeps letters for 30 days

Restore deleted letters from the letter box within 30 days of deletion. After
that, Inkrail permanently removes the deleted letter and its matching previous
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
Keep them with the library when backing it up. If cleanup fails, the app shows
a notice in Recently Deleted and retries later.

## Keep your library available

Use **Change Location…** when moving your library instead of dragging its
folder elsewhere in Finder. Inkrail remembers the selected path. If that
folder is missing or unavailable at launch, the app reports that storage is
unavailable rather than creating a replacement library elsewhere.

Reconnect an external disk or put the folder back at the selected path, then
reopen Inkrail. If you have written while storage was unavailable, **export
that writing before closing**. If a save fails because the disk is full or
unwritable, free space or fix access, then save again. A failed save is never
reported as successful.

Include the current library folder in your regular Mac backups. Previous saved
copies and the old folder left after relocation are useful fallbacks, but they
do not replace a separate backup.

## If you used the earlier symbolic-link workaround

You do not need to remove a working symbolic link to use the app. The new
location chooser can copy the library from the linked location into a new,
empty folder. After a successful change, Inkrail uses the new path directly.
Keep both the old link and its target until you have checked your new library
and backups; neither is removed by Inkrail.

If returning to a previously used folder, keep its old contents as a separate
backup first and select an empty destination. The chooser will not overwrite
the earlier library with newer writing.
