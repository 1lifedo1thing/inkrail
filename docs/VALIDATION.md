# Validation history

[Back to the user guide](../README.md). These records distinguish implemented
features, checks actually run, blocked checks and remaining manual testing.
Dated results describe their respective revisions; they are not a claim that
every check was rerun for the latest change.

The public version is **0.1.0, unreleased**. Earlier version labels below
identify internal development iterations, not published releases.

## Recently Deleted expires after 30 days — 16 November 2026

Deleted letters now carry a separate deletion date. Inkrail checks for expiry
at launch, hourly while running, before listing/restoring deleted letters and
before copying the library to a new location. After 30 elapsed days it removes
the deleted letter and its matching previous saved copy. Restoring stops the
countdown, and deleting again starts a fresh period. Legacy deleted letters
receive a full 30 days from the first check rather than using their edit date.
Active letters, Recovery files and old library safety copies are unaffected.

The letter box and deletion confirmation explain the time limit. Cleanup
failures appear in Recently Deleted and retain the deadline for retry. The
removal order keeps an identifiable copy until last, including when the
primary file is damaged and its backup is readable. Version remains 0.1.0.

- **Passed:** `bash scripts/build-app.sh`, including the state compile probe,
  native release build and strict ad-hoc signature verification.
- **Passed:** `bash scripts/check-trash-retention.sh` — 85 Foundation checks
  with a fixed clock and disposable files: exact/fractional 30-day boundary,
  legacy and invalid dates, restoration/re-deletion, active-file preservation,
  unknown files, symlinks, identity mismatches, failed writes/moves/removals,
  interrupted cleanup retries and custom-location deadline preservation.
- **Passed:** `bash scripts/check-storage-model.sh` — 100 production AppModel
  checks, including 34 new assertions for startup/hourly expiry, legacy grace,
  forced checks, view refresh revision and current-library-only cleanup.
- **Passed:** `bash scripts/check-library-location.sh` — 55 existing complete
  copy and path-guard checks after adding deletion-date files.
- **Blocked:** `swift test` was attempted and still cannot resolve XCTest in
  the installed Command Line Tools. Six new XCTest regressions were added;
  they have not run under XCTest.
- **Unverified:** live letter-box interaction and wall-clock timer firing.
  Expiry and scheduling were exercised with an injected clock; no user letters
  or preferences were used, relocated or deleted by these checks.

## App icon and custom letters folder — 16 November 2026

The app now explicitly installs its original icon at launch and supplies it to
the About panel. The bundled ICNS and SwiftPM PNG fallback come from the same
original artwork. The public bundle version is held at 0.1.0.

**Make it yours → Storage → Change Location…** copies the complete library to
a new or empty folder, verifies it and checks destination writes before
switching future saves. Pending edits must save first. The previous folder is
kept intact, and occupied or overlapping destinations are refused. A missing
custom folder at startup reports unavailable storage without creating a new
library or falling back to the default path.

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI state probe,
  native release build and strict ad-hoc signature verification.
- **Passed:** `bash scripts/check-library-location.sh` — 55 Foundation checks
  for complete copies, active/deleted letters, backups, recovery, hidden files,
  unchanged originals, collisions, missing paths, symlink overlap (including
  a missing leaf beneath a linked parent), interrupted and corrupted copies.
- **Passed:** `bash scripts/check-storage-model.sh` — 66 production AppModel
  checks for pending edits, location persistence/restart, subsequent saves,
  delete/restore, missing custom folders and failed-save preservation. These
  use disposable folders and in-memory defaults, not the user's library.
- **Passed:** `bash scripts/check-app-icon.sh` — 14 checks on the rebuilt
  bundle, ICNS sizes, PNG fallback and native NSApplication icon readback.
- **Passed:** `bash scripts/check-settings-popups.sh` — 150 native settings
  checks; `bash scripts/check-desk-preferences.sh` — 2,577 Foundation assertions.
- **Rendered:** `bash scripts/check-customization.sh --settings-only` produced
  ten isolated native settings views. The new Storage screen was inspected.
- **Blocked:** `swift test` was attempted; the installed Command Line Tools
  still cannot resolve XCTest. Five new XCTest regressions were added but
  have not run under XCTest.
- **Unverified:** live Dock/About appearance, folder-picker interaction and
  the full manual checklist. Icon readback and unshown view renders are not
  live screen captures. No actual user library or preferences were relocated.

## Hover labels below icons — 16 November 2026

Corrected the labels to start six points below each 34-point icon. The control
strip now overlays the clipped paper, keeping label text visible across the
lower paper edge without moving the icons.

- **Passed:** `bash scripts/build-app.sh`, including the state compile probe,
  native release build and strict signature verification.
- **Rendered and inspected:** 12 native writing-view snapshots at narrow,
  normal and Focus widths in day/night. Temporary source snapshots forced one
  hovered label; these are visual layout checks, not live pointer tests. The
  initial alignment-guide approach still overlapped icons, so the final code
  uses an explicit offset based on the icon height.
- **Blocked:** `swift test` still cannot resolve XCTest in the installed tools.
  Live hover and the full manual checklist were not exercised.

## Hover labels, wider Focus and end-of-writing scroll — 16 November 2026

The five bottom paper controls now show noninteractive themed hover labels
with action names and shortcuts. Focus paper grows to 960 points, leaving
60-point borders in a 1080-point window; normal paper and narrow-window insets
remain unchanged. A native clip constraint prevents Bottom's large symmetric
text inset from becoming blank scrollable space past the last written line.
Earlier writing remains scrollable, and Return/word wrapping still feed paper.
The README now explains deletion, restore, default storage and the optional
filesystem relocation workaround; no storage preference or migration UI was added.

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI state compile
  probe, native release build and strict ad-hoc signature verification.
- **Passed:** `bash scripts/check-paper-feed.sh` — 363/363 native checks,
  including 108 new end-scroll checks for Sheet/Roll, Top/Bottom, empty/short/
  wrapped/newline content, same-line typing, earlier reading, resize, deletion,
  undo and programmatic composition. The former Bottom layout allowed roughly
  510 points of blank trailing scroll on an empty letter.
- **Passed:** `bash scripts/check-desk-preferences.sh` — six Foundation groups /
  2,577 assertions, including updated width limits and saved preference handling.
- **Passed:** final `bash scripts/check-writing-desk.sh --focus-only` — 329
  assertions plus capsule/rail pixel checks, with all changes integrated.
  Normal/Focus/restored widths preserve the native editor, text and selection
  across Sheet/Roll, Top/Bottom and minimum/standard/wide windows.
- **Passed:** 38 disposable filesystem/production-repository checks for the
  documented copy/verify/rename/symlink workflow, save/reload/delete/restore,
  preserved original copies and path guards. No user library was moved.
- **Inspected:** production hover labels in day/night and a final 1080 × 820
  widened Focus render. Local documentation links and code fences were checked.
- **Blocked:** `swift test` was attempted; the installed Command Line Tools
  cannot resolve XCTest. Updated XCTest expectations have not run.
- **Unverified:** live pointer hover, trackpad scrolling, OS input methods,
  VoiceOver and a live app storage relocation. Native renders and programmatic
  checks do not replace those interactions; live capture was not retried.

## Settings control theme — 16 November 2026

Done now has explicit olive artwork, and every settings dropdown uses a
paper-coloured field with an olive arrow. The shared accent also remains the
settings tint. Dropdowns retain `NSPopUpButton` and native menu handling; only
their closed appearance is drawn locally. Done retains its Return shortcut.

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI compile probe,
  native release build and strict ad-hoc signature verification.
- **Passed:** `bash scripts/check-settings-popups.sh` — 150 native checks for
  olive/no-blue pixels in light/dark hosts, readable dropdown titles (11:1
  measured contrast), native focus, enabled/disabled state, selection/binding
  updates and programmatic Return invoking Done exactly once.
- **Inspected:** native dropdown gallery and final Done crop. The former
  dropdown appearance failed the positive olive-colour check. Unshown native
  windows did not reproduce the screenshot's active blue Done bezel, so no
  before/after pixel reproduction of that runtime state is claimed.
- **Blocked:** `swift test` was attempted and cannot resolve XCTest in the
  installed Command Line Tools.
- **Unverified:** live menu opening/highlighting, real keyboard navigation,
  VoiceOver and the full manual checklist. Captures are isolated native views;
  the previously encountered live screen-capture failure was not retried.

## User guide rewrite — 16 November 2026

Rewrote the README around installation, first use, customization, local saving,
recovery and export. Moved detailed implementation notes to `DEVELOPMENT.md`
and retained the dated validation reports here. Reused an existing repository
screenshot; no new live capture or application behavior change is claimed.

- **Passed:** source review of menu labels, shortcuts, settings, storage,
  import/export and known limitations; local Markdown link and code-fence checks.
- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI compile probe,
  native release build and strict ad-hoc signature verification.
- **Blocked:** `swift test` was rerun and cannot resolve XCTest in the installed
  Command Line Tools. No XCTest pass is claimed.
- **Not rerun:** native interaction, visual regression and manual checklist
  checks; their earlier results remain in the dated entries below.

## Matching paired lamp light — 16 November 2026

Both side lamps already shared one colour and intensity. Diagonal ambient
shading, plus an angled satin reflection on wooden desks, made the same light
look different on each side through the material's colour-dodge blend. Those
two shading layers now run vertically when paired lamps are visible, balancing
the light while retaining the original grain and lamp artwork.

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI compile
  probe, native release build and strict ad-hoc signature verification.
- **Passed:** `bash scripts/check-writing-desk.sh --desk-lamp-colour-only` —
  144 mirrored emitter/pool colour checks across all six finishes, both lamp
  styles, three warmth settings and day/night at 1080 × 820. The same fixed
  tolerance caught 90 failures before the fix; all now pass. Maximum mean
  channel difference is below one 8-bit colour value.
- **Passed:** `bash scripts/check-writing-desk.sh --desk-grazing-only` — 240
  assertions plus capsule/rail checks, covering paper-edge light, warmth and
  intensity, Focus, narrow windows and unchanged native text/selection.
  Updated 1080 × 820 bronze and linen renders were visually inspected.
- **Passed:** `bash scripts/check-desk-preferences.sh` — six Foundation
  groups / 2,577 assertions.
- **Blocked:** `swift test` cannot resolve XCTest in the installed Command
  Line Tools. Live app capture failed again with ScreenCaptureKit error −3811;
  the renders above are isolated native views, not live screenshots. The full
  keyboard/IME, quit and save-failure checklist was not rerun.

## Reference-led leather scene and grazing light — 16 November 2026

Replaced the illustrated paired lamps with original locally modeled bronze
and linen lamps, added Leather study, and coordinated each emitter with its
desk pool, cast/contact shadow and paper-edge light. Four transparent body
and emitter assets are bundled; their reproducible native 3D generator is
included. The app itself uses cached images and native decorative rendering.
The source reference image is not bundled. The existing `brassLamps` saved
ID now selects the bronze model; defaults and unrelated choices remain intact.

- **Passed:** `bash scripts/build-app.sh`, including the state compile probe,
  native release build and strict signature verification. All four lamp
  assets in the signed app match their source files.
- **Passed:** `bash scripts/check-desk-preferences.sh` — six Foundation groups,
  2,577 assertions, including literal pre-leather preferences and all 72
  finish/object/focus combinations.
- **Passed:** `bash scripts/check-writing-desk.sh --desk-grazing-only` — 240
  assertions; `--desk-isolation-only` — 33 assertions. Together these cover
  273 assertions plus housing/rail checks and 37 production-view captures.
  Both paper edges brighten, follow warmth/intensity, and stop before the
  text inset. Central paper, embossing, actual native text and selection are
  preserved. Both styles pass day/night at 1080 and 1733 points; Focus and
  660-point windows clear both objects and illumination. Asset alpha and
  projected emitter positions are checked against the shared scene geometry.
- **Passed:** nine settings renders, 106 native popup checks, and the existing
  capsule-only night-light regression (10 profile groups plus four rendered
  checks / 12 captures). The reference comparison uses a clean 1733 × 908
  render of the production writing view, not a mockup pasted over an editor.
- **Blocked:** `swift test` was attempted; the installed Command Line Tools
  still cannot resolve XCTest. New XCTest coverage is authored but unrun.
- **Unverified:** live screenshots, real keyboard/IME/VoiceOver interaction
  and frame-rate performance. The visual captures are isolated native views.
  The modeled lamp materials and projected light are a practical visual
  approximation, not a claim of photographic fidelity or real-time ray tracing.

## Desk material refinement — 16 November 2026

Reworked the optional desk artwork around the paper's restrained material
style: muted nonrepeating wood fibres/pores, foreshortened lamps with aged
metal and soft reflections, layered envelope folds, fine wire highlights and
varied leaves with contact shadows. No new preferences, assets, dependencies,
timers or input changes. These remain original shaded 2D forms, not a
photorealistic rendering or physical lighting simulation.

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI compile probe,
  native release build and strict ad-hoc signature verification. The updated
  `dist/Inkrail.app` was opened successfully.
- **Passed:** `bash scripts/check-desk-preferences.sh` — five Foundation
  groups / 2,537 assertions, including literal legacy preference records.
- **Passed:** `bash scripts/check-writing-desk.sh --desk-lamps-only` — 74
  assertions plus production housing/rail checks and 26 native captures.
  Both lamp pairs preserve paper/embossing pixels and the native editor,
  respond to shared warmth/intensity, remain stable on idle redraws, and
  disappear completely in Focus and minimum-width windows.
- **Rendered and inspected:** the two full 1080 × 820 desk scenes, sprig and
  envelope, plus four day/night artwork previews. Eight isolated settings
  views rendered successfully; the Walnut study settings preview was inspected.
- **Blocked:** `swift test` was attempted; the installed Command Line Tools
  cannot resolve XCTest. No XCTest result is claimed.
- **Unverified:** live screenshot comparison, keyboard/IME/VoiceOver and
  frame-rate performance. The captures above are isolated native views, not
  running-app screenshots. Letters and saved choices were not reset.

## Wooden desk scenes and paired lamps — 16 November 2026

Added Walnut study and Warm oak scene buttons, Honey Oak, richer Walnut grain,
and two paired-lamp choices. Existing desk IDs/defaults and saved choices remain.

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI compile probe,
  native release build and strict ad-hoc signature verification. Updated app:
  `dist/Inkrail.app`.
- **Passed:** `bash scripts/check-desk-preferences.sh` — five Foundation
  groups / 2,537 assertions, including literal pre-lamp desk preferences and
  all 60 finish/object/focus combinations.
- **Passed:** `bash scripts/check-writing-desk.sh --desk-lamps-only` — 74
  assertions plus housing/rail checks, with 26 production-view captures.
  Both lamps are visible in day/night; their shared warmth and intensity work
  in the expected direction. Paper/embossing pixels and native text remain
  intact. Both lamps disappear in Focus and minimum-width windows.
- **Passed:** 106 native popup contrast/binding checks and eight isolated
  settings captures, including both scene selections. Both 1080 × 820 desk
  scenes and their settings previews were visually inspected, alongside four
  independent day/night artwork renders.
- **Blocked:** `swift test` was attempted but the installed Command Line
  Tools still lack XCTest. One additional XCTest method was authored and
  syntax-checked but **not run**, alongside the updated existing tests.
- **Unverified:** live running-app interaction, real keyboard/IME/VoiceOver
  and quit/relaunch. Captures are isolated native renders, not live screenshots.
  No letters or saved preferences were reset or automatically switched to a scene.

## Desk finishes and wider Focus Mode — 16 November 2026

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI compile probe,
  native release build and strict ad-hoc signature verification. Updated app:
  `dist/Inkrail.app`.
- **Passed:** `bash scripts/check-desk-preferences.sh` — four Foundation
  groups / 2,450 assertions covering literal legacy records, all desk choices,
  independent fallback, focus width limits and unchanged vertical roll geometry.
- **Passed:** `bash scripts/check-writing-desk.sh --focus-only` — 308 assertions
  and 44 production-view captures across 1080 × 820, minimum and large windows,
  Sheet/Roll and Top/Bottom. Entering/leaving Focus retains the native editor,
  text, selection and visible caret. Desk choices preserve opaque paper pixels
  and are hidden in both Focus gutters. The width opt-out also passed.
- **Passed:** `bash scripts/check-writing-desk.sh --emboss-only` — 36 assertions
  and 12 renders. Botanical, Monogram and Sunburst have identical measured
  relief dimensions at 720/880 points in both Sheet and Roll.
- **Passed:** `bash scripts/check-paper-feed.sh` — 255/255 native checks,
  including 60 new width-transition, native editing, undo and programmatic
  composition checks. These do not exercise real OS input-method candidates.
- **Passed:** six native settings captures and 106 popup contrast/binding
  checks. The Desk tab was visually inspected; its preview and all choices fit
  the initial viewport. An independent render pass produced all 16 finish/accent
  combinations; representative wood/sprig, felt/paperclip and linen/envelope
  previews plus the actual wide Roll writing view were visually inspected.
- **Blocked:** `swift test` was attempted after the changes but the installed
  Command Line Tools still lack XCTest. Seven new XCTest methods were authored
  but have **not run**; standalone/native checks above are separate.
- **Unverified:** live running-app capture, real keyboard/IME/VoiceOver and
  quit/relaunch/save-failure interaction. Existing ScreenCaptureKit capture
  failure was not retried. Render fixtures use unshown native windows or native
  components, with no user letters or saved preferences reset.

## Fonts and uneven ink — 16 November 2026

Added four locally installed font choices and adjustable ink buildup. The Type
tab uses a compact native font menu and a live sample drawn by the editor's
actual layout manager. No fonts are bundled or downloaded.

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI compatibility
  probe, native release build and strict ad-hoc signature verification.
- **Passed:** `bash scripts/check-ink-preferences.sh` — four standalone
  Foundation groups / 1,985 assertions, covering deterministic and bounded
  drawing parameters, all eight font IDs, and literal legacy preference
  decoding, null/default/clamping behavior and round-trips.
- **Passed:** `bash scripts/check-ink-rendering.sh` — 680 native assertions
  and 34 component renders. All eight fonts at 20/28pt show occasional heavier
  and lighter strikes with identical layout, text, selection and hit mapping.
  Repeat renders are stable; wear-off restores native pixels. Combining accents,
  complex scripts, emoji, the composition guard and native ligatures retain
  native rendering. Courier clean/worn and Typewriter Light worn were visually
  inspected. These are component renders, not running-app screenshots.
- **Passed:** `bash scripts/check-paper-feed.sh` — 195/195 standalone native
  checks including all eight installed faces, switching with selection,
  programmatic Unicode input/composition, undo, resize and Sheet/Roll feed.
- **Passed:** `bash scripts/check-customization.sh --settings-only` generated
  five native settings captures. The Type preview, font menu, Worn ribbon and
  Ink buildup control were visually inspected in the initial viewport.
- **Blocked:** `swift test` was attempted after the changes but the installed
  Command Line Tools still lack XCTest. Nine new XCTest methods were authored
  but have **not run**; the standalone checks above are separate.
- **Unverified:** live keyboard/OS input-method and VoiceOver interaction,
  quit/relaunch and save-failure checks. The existing ScreenCaptureKit live
  capture failure was not retried for this change. No user letters or saved
  preferences were reset.

## Sound expansion — 16 November 2026

Added Portable, Office and Electric with eighteen original synthesized samples.
The Sound tab now has a compact two-column selection grid. Existing sound
choices, mute and volume remain intact; Classic is still the default.

- **Passed:** final `bash scripts/build-app.sh`, including the SwiftUI compile
  probe, native release build and strict ad-hoc signature verification.
  The rebuilt app is `dist/Inkrail.app`.
- **Passed:** Python WAV validation for all 36 source and packaged samples:
  exact resource set, encoding, durations, signal bounds and distinct waveforms.
  All eighteen previous WAVs retain their hashes; regenerating all thirty
  non-Classic samples in a separate folder produced byte-identical files.
- **Passed:** `bash scripts/check-sounds-native.sh` loaded and fully decoded
  all 36 WAVs through both production resource lookup paths. Standalone checks
  also passed for all six persisted IDs, literal saved preferences and safe
  missing/null/removed/unknown sound fallback without resetting other choices.
- **Passed:** `bash scripts/check-customization.sh --settings-only` generated
  five isolated native settings captures. The final Sound view was visually
  inspected: all six labels, volume and Preview sound fit the initial viewport.
  These captures do not exercise live clicks or audio playback.
- **Blocked:** `swift test` was attempted after the changes but cannot compile
  because the installed Command Line Tools lack XCTest. Three new XCTest
  methods were authored but have **not run**.
- **Unverified:** audible playback, subjective sound quality and live app
  interaction. The app launch command succeeded, but native screen capture
  again failed with ScreenCaptureKit error −3811. No live 1080 × 820 capture
  or full typing/IME, quit/relaunch or save-failure checklist pass is claimed.
  No letters or saved preferences were reset.

## v0.1.8 build 11

Fixed the capsule housing disappearing near the left edge of the writing
page. The exact production `WritingDesk` reproduced it on empty pages and
when moving the native caret to the beginning of an existing line. Its stem,
indicator dots and rail remained visible. Grouping the capsule artwork after
its fixed-size frame keeps the body and hardware rendered together without
moving the carriage, lamp or text.

- **Passed:** `bash scripts/build-app.sh`, including the SwiftUI compile
  probe, native release build and strict ad-hoc signature verification.
  The rebuilt app is `dist/Inkrail.app`.
- **Passed:** `bash scripts/check-writing-desk.sh` — 77 exact production-view
  captures, including all ten previously failing cases. Coverage includes
  native caret movement to both edges, Sheet/Roll with Top/Bottom, all twelve
  styles in day/night, empty/short/long pages and three window sizes. Housing
  pixels are compared with centered references of the same capsule; Classic
  also has independent body/rail visibility checks. Before/after empty-page,
  night and Sea Glass captures were visually inspected. The earlier component
  fixture omitted the production button host and did not catch this bug.
- **Passed:** a separate peak-strike render confirmed the hammer still draws
  above the capsule's fixed frame and its shadow remains visible.
- **Blocked:** `swift test` was retried and still cannot compile because
  the installed Command Line Tools lack XCTest. No XCTest pass is claimed.
- **Unverified:** live running-app capture/control remains unavailable after
  the ScreenCaptureKit failure. These checks render the actual writing-page
  view in unshown native windows with an inert in-memory model; they are not
  screenshots of the user's running app. Real keyboard/IME input and live
  quit/relaunch were not repeated. No user letters or preferences were reset.

## v0.1.7 build 10

The final native production build, SwiftUI state compile probe and strict
ad-hoc signature verification passed. The rebuilt app is `dist/Inkrail.app`.

- **Passed:** `bash scripts/check-paper-feed.sh` — **163/163 standalone
  native checks**, including both roll starting positions, downward progression
  before Top feeds, mode switching with selection, Unicode hit mapping, undo
  and programmatic composition.
- **Passed:** `bash scripts/check-settings-popups.sh` — **70 native checks**
  in light and dark hosts. Actual selected-title pixels are dark and readable;
  native target-actions and external binding changes update the selected values.
  The popup renders were visually inspected.
- **Passed:** `bash scripts/check-machine-styles.sh` — five check groups,
  including legacy migration, all 72 style/rail combinations, the shared
  housing dimensions and all twelve lamp emitters. The twelve-style gallery,
  production style picker and warmth previews were visually inspected.
- **Passed:** 13 customization groups with 38 component renders, eight native
  paper/editor captures at standard/minimum sizes, and ten lamp-profile groups
  plus four rendered-light checks. Top/Bottom roll starts, the new shoulders,
  the curved/square edge choices and settings were visually inspected.
- **Passed:** the exact set of 18 source and packaged WAVs; all original audio
  bytes are preserved. AVFoundation loaded and fully decoded all eighteen
  through both production resource paths. The app contains no Recorded WAVs;
  the removed preference decodes to Classic.
- **Blocked:** `swift test` still cannot compile because this Mac's Command
  Line Tools lack XCTest. New XCTest cases are authored but **not run**.
- **Unverified:** real keyboard/IME input, live mouse dragging and opened-menu
  keyboard/highlight/VoiceOver behavior, audible playback, quit/relaunch and
  save-failure checks. Component captures are not running-app screenshots;
  the earlier ScreenCaptureKit live-capture failure was not resolved here.
  No release ZIP was created.

## v0.1.6 build 9

The final native production build, SwiftUI state compile probe and strict
ad-hoc signature verification passed. The rebuilt app is `dist/Inkrail.app`.

- **Passed:** `bash scripts/check-paper-feed.sh` — **151/151** standalone
  checks, including legacy migration, real native scroll interpolation,
  mode switching, resize, deletion/undo, Unicode insertion, interruption,
  programmatic composition and insertion-point mapping on compressed
  Latin/Hindi/CJK lines. Repeated after the projected caret redraw fix.
- **Passed:** `bash scripts/check-customization.sh` — **13 check groups**,
  including a stationary roll silhouette and moving deterministic grain;
  **39 component renders** generated. Paper-roll settings and Recorded sound
  choices were visually inspected.
- **Passed:** `bash scripts/check-paper-roll-render.sh` — five isolated
  native component captures using the actual editor: 1080 × 820 roll day,
  roll night, short starting page and Sheet control, plus 660 × 580 roll.
  All were visually inspected. These are still component fixtures, not
  running-app screenshots or a motion recording.
- **Passed:** ten lamp-profile groups and four rendered-light checks.
- **Passed:** all 24 source WAV integrity checks, unchanged hashes for all
  18 existing sounds and byte-identical regeneration of the six excerpts.
  `bash scripts/check-sounds-native.sh` loaded and fully decoded all 24
  packaged WAVs through both production resource-resolver branches.
- **Blocked:** `swift test` cannot compile because the installed Command
  Line Tools lack XCTest. The added geometry/projection XCTest methods have
  **not run**. A separate numerical projection sweep passed 13,344 assertions;
  this is not an XCTest pass.
- **Unverified:** real mouse dragging, keyboard/clipboard actions, actual OS
  input-method candidates, VoiceOver range frames and audible playback.
  The initial app was launched, but live capture failed with ScreenCaptureKit
  error −3811. Audio was inspected through synchronized frames and signal
  analysis; no subjective listening pass is claimed. Existing save-failure,
  quit/relaunch and recovery checks were not repeated in this pass. No release
  ZIP was created.

## v0.1.5 build 8

The final native production build, SwiftUI state compile probe and ad-hoc
signature verification passed. The rebuilt app is `dist/Inkrail.app`.

- **Passed:** `bash scripts/check-paper-feed.sh` — **107/107 standalone native
  editor, migration and font checks** after fixing insufficient scroll space
  below the final line in Top mode. These are isolated in-memory checks, not
  real keyboard/IME or visual tests.
- **Passed:** standard-library validation of all 18 source and packaged WAV files, including
  encoding, duration, signal bounds, distinct PCM and unchanged Classic bytes.
  Regenerating the 12 new samples produced byte-identical files. Audio output
  and subjective listening have **not** been tested.
- **Passed:** `bash scripts/check-customization.sh` — eleven customization
  check groups and 30 component render files. The paper/embossing and font
  galleries were visually inspected. All five settings tabs were inspected
  using isolated `NSHostingView` layout captures, since `ImageRenderer` cannot
  draw their native pickers and scroll views. Pixel comparisons allow small
  display-quantization differences on opaque paper. These captures do not
  validate running-app interaction or every compositor effect.
- **Passed on the final paper rendering:** ten lamp-profile groups and four
  rendered-light checks, including warmth endpoints and intensity.
- **Confirmed on this Mac:** all four selected writing font faces resolve.
- **Blocked:** another `swift test` attempt could not compile because the
  installed Command Line Tools lack XCTest. Eight new customization XCTest
  methods have been authored but **not run**.
- **Unverified:** real keyboard/IME input, settings interaction and audible
  playback in the running app, plus older macOS compatibility. Isolated test
  windows do not load saved letters or write user preferences.
  No v0.1.5 release ZIP has been produced in this pass.

## Earlier validation

The **v0.1.4 build 7 night-lamp update** passed the native production build
and SwiftUI state compile probe. `bash scripts/check-night-lamp.sh` passed
**10 numerical check groups and 4 rendered-light checks** for spatial falloff,
below-lamp spill, warmth range and intensity. It generated 12 isolated renders
of the production SwiftUI components, including the six styles, three papers,
slider endpoints and paper-edge positions. These are component renders, not
screenshots or interactive tests of the running editor. The default beam,
style previews and edge clipping were visually inspected. Outputs are under
`.build/night-lamp-checks/` and can be regenerated with that script.

`swift test` was attempted again and is still blocked by the installed Command
Line Tools' missing XCTest module; the seven new XCTest beam tests have **not
run**. In-app interaction, native text under the lamp, real IME and older macOS
compatibility remain unverified. The isolated render fixture uses SwiftUI
sample text, not `NSTextView`.

The **v0.1.4 build 6 Focus Mode fix** passed the native build, SwiftUI state
compile probe, extracted-archive content/signature checks and SHA-256 check.
`swift test` was attempted again and remains blocked by missing XCTest.
The hover behavior was reviewed in code but has not been visually exercised;
the existing native screen-capture limitation remains. The 47 checks below
cover paper feed and preferences, not this hover interaction.

For **v0.1.4**, the native production build and SwiftUI state compile probe
passed. `swift test` was attempted but remains blocked by the installed
Command Line Tools' missing XCTest module. Fourteen new XCTest tests were
authored (six preference/migration and eight feed-geometry tests); they have
**not run**. The separate native test harness passed **47/47 checks**, including
legacy preference decoding, native text insertion, undo, selection, wrapping,
resizing, manual scrolling and programmatic composition. These are isolated
in-memory checks, not real keyboard/IME or visual tests. Manual typing, IME,
resizing and appearance checks remain on the
[manual checklist](PAPER_FEED.md#manual-checklist). Current feature details and
validation are in [PAPER_FEED.md](PAPER_FEED.md).

The following is earlier **v0.1.3 packaging evidence**, separate from the
new paper-feed feature:

The original implementation was authored and tested on Linux. A macOS
packaging pass was performed on **14 November 2026**, using an Apple Silicon
Mac, macOS 27.0.1, Command Line Tools Swift 6.4 and SDK 27.

- **Passed on macOS:** SwiftUI state compile probe, native release build,
  ad-hoc signature verification, shell syntax and plist validation. The ZIP
  was extracted and its contents compared with the built app; its signature,
  included license and SHA-256 checksum were verified. Audio files and paper
  texture are present in the archive; playback/rendering were not tested.
  The build and archive checks were repeated after adding Aaryan Verma's
  authorship credits; About panel and settings-footer appearance are unverified.
  The icon wordmark update was also rebuilt and verified in the release ZIP;
  the 1024- and 128-pixel icon images were visually inspected. Finder/Dock
  rendering remains unverified.
- **Attempted, blocked on macOS:** `swift test` could not compile because the
  installed Command Line Tools lack the XCTest module. Full Xcode was not
  installed. No tests passed in this macOS run.
- **Historical Linux results:** 36 passing portable tests (14 model/storage,
  10 lamp, 12 style/migration), source syntax and manifest checks, and 11 patch
  installer checks. These are separate from the latest macOS build.
- **Unverified:** native launch/appearance, editing and IME, save-failure UI,
  bundle audio playback, accessibility and compatibility on older macOS.
  The native UI inspection attempt failed with a screen-capture error; no
  native screenshot or manual checklist completion is claimed.
- **Included, not executed here:** the GitHub Actions macOS build/test
  workflow. It retains a CI artifact, not an automatically published release.

For a future v0.1.5 Apple Silicon release, the planned archive filename is
`dist/Inkrail-v0.1.5-macOS-arm64.zip`; this is a packaging convention, not a
claim that the archive has been created. Builds use ad-hoc local signing and have
**not** been Developer ID signed or notarized. Complete the native checklist
before a general release. The local `extras/VALIDATION.md` records earlier
results; [paper-feed notes](PAPER_FEED.md) separate the current changes
from the earlier verified archive and the remaining visual/IME checks.
