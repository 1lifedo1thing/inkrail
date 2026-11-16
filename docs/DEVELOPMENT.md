# Development notes

[Back to the user guide](../README.md) · [Validation history](VALIDATION.md)

This document preserves the detailed implementation, compatibility and design
notes previously in the README. For everyday use, installation, shortcuts and
file recovery, start with the user guide. Dated implementation notes describe
how the app evolved; consult the validation history for checks actually run.

## Start on your Mac

To publish the source or offer a prebuilt app download on GitHub, follow
[the GitHub release guide](GITHUB_RELEASE.md). Release downloads use a
ZIP containing `Inkrail.app`; users of a prebuilt app do not need developer
tools. The build script currently uses ad-hoc signing, not Apple notarization.

To build from source, you need **macOS 13 or later** and **Apple's Swift 5.9+ developer toolchain**
(Xcode 15+ or a sufficiently recent Command Line Tools installation).
No Python, Node, package service, account, API key, or paid developer account
is required to build and run locally.

1. Extract the download and open the `Inkrail` folder.
2. Double-click **Launch.command**. It builds a native `.app` and opens it.
3. The resulting **dist/Inkrail.app** can be dragged into Applications.

Terminal alternative, from the extracted folder:

```bash
bash scripts/build-app.sh
open dist/Inkrail.app
```

If Apple's developer tools are not installed:

```bash
xcode-select --install
```

Complete the installer, then rerun the build command. If the installed tools
are too old for Swift 5.9, update them or install a current compatible Xcode.
If Xcode asks for first-launch setup or a license acceptance, finish that
inside Xcode before building again.

For development, open the folder's **Package.swift** in Xcode, select the
**Inkrail** scheme and **My Mac**, then press Run. This is a Swift package,
not a generated `.xcodeproj`; Xcode supports opening the package directly.
`swift run Inkrail` is another development option, but the built `.app` is
preferred for normal Dock and application-menu behavior.

## Make it yours

Open **Make it yours** with **Command-comma (⌘,)**. Settings are arranged in
seven tabs, with related controls in separate cards:

| Tab | Choices |
| --- | --- |
| Paper | Sheet or Paper roll, paper colour, texture and detail, embossing and relief, botanical margins, starting position and margins |
| Type | Eight typefaces, type size, ribbon colour, ink darkness, worn ribbon and ink buildup |
| Machine | Twelve capsule styles, Classic capsule colours and rail finishes |
| Desk | Six finishes, paired desk lamps or small decorative objects, Leather study/Walnut study/Warm oak scenes, and wider paper in Focus Mode |
| Sound | Classic, Soft, Crisp, Portable, Office or Electric keys, mute, volume and an explicit preview button |
| Light | Night writing, lamp intensity and warmth, with a live preview |
| Storage | Current letters folder, Show in Finder, and Change Location to a new or empty folder |

Paper textures are **Classic**, **Smooth**, **Laid** and **Cotton**. Use
**Texture detail** to adjust the surface where applicable. Embossing offers
**None**, **Botanical**, **Monogram** and **Sunburst**, with a **Relief** control.
These are original, deterministic paper treatments; the existing botanical
margin decoration remains a separate option.

The typefaces are **Courier**, **American Typewriter**, **Menlo**, **Georgia**,
**Courier New**, **Typewriter Light**, **Typewriter Condensed** and **Monaco**.
The Light and Condensed choices use American Typewriter's corresponding faces.
Inkrail resolves installed macOS fonts and uses a local fallback
if a face is unavailable. No font files are bundled or downloaded. The editor,
placeholder and previews use the same selected face. Font and paper styling
apply to the desk; plain-text and Markdown exports still contain only words.

For an uneven old-typewriter impression, open **Type → Ribbon & ink**, enable
**Worn ribbon** and raise **Ink buildup**. Some letters gain extra weight and
darker pooled ink, while others strike lightly, with small registration shifts.
The Type tab's live sample uses the same native ink renderer as the editor.
At 0% buildup, only light pressure/registration variation remains; turn Worn
ribbon off for even native text. Ink buildup defaults to 55%, and an existing
Worn ribbon off setting stays off. Patterns are deterministic, so the ink does
not flicker when redrawn. The treatment changes drawing only, keeping native
text advances, selection and editing. Complex graphemes, ligatures, emoji and
active composition retain native rendering.

The six synthesized sound profiles contain six original samples each: three key
strikes, space, delete and carriage return. **Classic** retains the original
samples; **Soft** uses muted, warmer sounds, and **Crisp** uses brighter, drier
strikes. **Portable** adds light mechanical clatter, **Office** adds weightier
keys and a ringing carriage bell, and **Electric** uses a compact powered snap
and a short paper-drive return without an idle hum. All 36 samples are bundled
for offline use. Sounds remain optional. **Preview sound** plays only when pressed;
changing the sound settings, leaving the tab or closing settings stops the
preview. Mute stops playback. All 18 previous sound files retain their original
bytes. An older Recorded selection safely falls back to Classic without
resetting other preferences.

Existing preferences retain their values. New fields default to **Classic
texture, no embossing, Courier and Classic sounds**, preserving the previous
appearance and sound. Letter files and storage locations are unchanged.

## Desk finishes and wider Focus Mode

Open **Make it yours (⌘,) → Desk** and choose **Leather study** for a warm
leather surface and paired bronze lamps, **Walnut study** for satin walnut
with the same lamps, or **Warm oak** for honey oak and two linen-shaded lamps.
The scene buttons change only the desk
finish and objects; your paper, embossing, roll, ink and lamp settings stay intact.

You can also mix **Charcoal**, **Walnut**, **Felt**, **Linen**, **Honey Oak** or
**Leather** with **Paired bronze lamps**, **Paired linen lamps**, **Botanical sprig**,
**Paperclip**, **Envelope** or **None**. The wooden surfaces use muted,
interrupted fibres and pores rather than repeating waves. Leather has an
original cached height-field texture with fine creases and surface shading.
The lamps use original three-dimensional models with bronze reflections or
woven linen, rendered locally into transparent artwork. The development-only
generator is `scripts/render-desk-lamps.sh`; no 3D engine runs in the app.
Small objects use folded paper, subtle metal glints and individually shaped leaves.

The paired lamps cast broad, soft pools onto the material and grazing light
along both paper edges, using the same warmth/intensity mapping as the capsule.
One layout anchors the modeled shade, emitter, desk pool and paper highlight.
Light fades within the outer 42 points, before the narrowest writing inset;
paper geometry, embossing and native text remain intact. Night writing reveals
paper grain inside that same edge field. This is a coordinated lighting
approximation, not a real-time physical simulation.

The default remains the original charcoal desk with no objects. These are
original procedural surfaces, locally rendered lamp artwork and small vector
objects, with no downloaded assets, random-on-redraw textures or animation
timers. Lamp bodies stay outside the paper; their light can reach its margins.
Objects and their light tuck away in narrow windows. A live settings preview uses
the same desk and paper components.

**Focus Mode (⇧⌘F)** widens the sheet from 720 to at most 960 points when the
window has room. At the default 1080-point window, 60-point borders remain on
both sides. **Desk → Wider paper in Focus Mode** can restore the original
width. Small windows retain the existing 52-point side inset.

The actual editor reflows at the new width; font size, inner margins, paper
height, embossing size and vertical roll geometry stay the same. The curved
shoulders continue to follow the paper width. Width changes in one native
layout step, avoiding stretched artwork or
repeated animated text wrapping. Focus temporarily uses the quiet charcoal
background with no desk accents. Leaving Focus restores the selected finish,
accent and regular sheet width. Paper, ink, lamp and sound preferences remain
independent; all decoration stays outside the editable text system.

## Paper roll from the supplied recording

Open **Make it yours (⌘,) → Paper → Page layout → Paper motion → Paper roll**.
**Start writing → Top or Bottom** remains available for both paper modes.
Top begins near the upper margin, advances downward, and feeds once the lower
writing band is reached. Bottom starts at the lower writing band and feeds
from the first new line. Lines feed in a short eased movement, and older lines flatten and
narrow as they pass over the stationary curved upper edge. Texture and
embossing use the same paper curve. The capsule returns quickly to the next
line. Reduce Motion makes the feed and carriage movement immediate.

**Sheet**, **Top** and **Classic sounds** remain the defaults. Switching paper
motion keeps the chosen starting position. **Curved upper corners** now uses
longer tapered shoulders, a shallow bowed lip and softer light across the
paper's bend. Turn it off to retain the simple rectangular edge.

The supplied 33-second recording informed the upper-edge bend
and approximately 0.18-second feed timing. This is an original native
approximation, not a claim of pixel-identical 3D rendering. Text input,
selection, undo and composition remain in `NSTextView`; the drawing and
pointer coordinates share a projection. See [implementation and validation
notes](PAPER_ROLL.md).

## Automatic paper feed and starting position

Open **Make it yours** with **Command-comma (⌘,)**, then choose
**Paper → Page layout → Start writing → Top or Bottom** in either paper mode.

- **Top** starts near the top of the paper. Lines advance downward until
  they reach the lower writing band, then the paper feeds upward automatically
  as you continue writing.
- **Bottom** starts near the lower part of the paper. As you type or delete
  lines, the text feeds upward or back down to keep the insertion line near
  the lower writing band, with the capsule and rail below it.

You can still scroll to read and select earlier text. Resuming typing brings
the active line into view; Bottom places it at the writing band. The grain,
embossing and upper paper edge move with the native scroll position. This
setting applies to the desk; switching it changes layout, not the content or
order of your letters. It
does not insert blank lines into saved notes or exports.

**Top remains the default**, including when upgrading existing preferences.
Bottom uses native text-view insets, a native scrollable viewport and the
existing `NSTextView` input pipeline. See [paper-feed implementation and
validation notes](PAPER_FEED.md). Sheet retains its existing feed behavior;
the new Paper roll option uses timing measured from the supplied recording.

## Slider styles

Open **Make it yours** with **Command-comma**, then **Machine → Slider styles**.
There are twelve designs for the moving typewriter capsule and rail. The six
original styles remain, alongside six new material and decorative choices:

| Style | Material treatment |
| --- | --- |
| Classic | Original capsule and its five colour swatches |
| Brushed Steel | Satin metal, rounded rectangular body, machined grip ribs |
| Champagne | Muted gold, Art Deco lines, inset diamond badge |
| Walnut | Procedural wood grain, brass nameplate and small screw heads |
| Porcelain | Rounded ivory ceramic, subtle speckling, sage inset |
| Midnight | Graphite housing, fine gold outline and monogram |
| Rose Quartz | Blush pearlescent finish |
| Sea Glass | Frosted teal with cool highlights |
| Lavender | Soft lilac enamel |
| Racing Green | Deep green with brass detailing |
| Copper | Warm hammered metal |
| Wildflower | Cream enamel with original floral decoration |

Tiles and previews reuse the actual desk components. Pick a style to apply it;
no restart or Apply button is needed. New styles use a coordinated rail by
default. Disable **Match rail to style** to choose Steel, Brass or Charcoal.
Your old Classic capsule colour and manual rail selection are kept separately;
returning to Classic restores those choices. Paper, ribbon, sound and the
night lamp's warmth/intensity are not changed by style selection.

The default remains Classic. Existing v0.1.2 preferences decode field-by-field
with defaults for the two new keys, avoiding an all-settings reset. The
UserDefaults key and letter-file storage have not been renamed. This feature
styles the moving writing mechanism, not the warmth/intensity slider controls.

All textures are drawn locally from deterministic paths. No external assets,
new dependencies, repeating timers or always-running animations were added.
The new designs keep the original 110 x 46-point housing, so the lamp, hammer
and caret geometry use the same coordinates. Native visual verification is
still required. Historical local notes are in `extras/SLIDER_STYLES.md` and
`extras/VALIDATION.md` (`extras/` is excluded from Git).

## Natural night lamp (v0.1.4, build 7)

The lamp now casts a broad, softly feathered fan up the paper, with a bright
pool connected to the capsule's emitting slit and very little spill below
the housing. This replaces the old blurred triangular cone. The light field
is generated once from original deterministic code and reused as the capsule
moves; no downloaded light texture or animation timer is involved.

The **Warmth** slider keeps its full cool-white → warm-white → amber range,
and **Lamp intensity** dims the entire beam. Both controls retain their saved
values. The desk, settings preview and all capsule styles use the same
light color and emitter position. Native text editing remains separate from
the paper-light rendering.

### Warmth controls (introduced in v0.1.2)

Warmth now changes the light colour from cool white through warm white to
amber. The paper tint and the capsule's emitting slit use the same mapping.
A live preview under the sliders uses the same paper and light components
as the desk. Intensity still controls how much of the darkness is removed;
temperature no longer just makes a fixed yellow screen overlay more opaque.

To compare the endpoints: open **Make it yours → Light**, enable Night writing,
set Lamp intensity near 80%,
and move Warmth between 0% and 100%. The preview should visibly change from
cooler paper to amber paper. See the local `extras/LAMP_WARMTH_FIX.md` for the diagnosis,
source locations, regression tests and native-testing limitations.

## SDK 27 / missing SwiftUIMacros fix

The v0.1.0 build can fail with `SwiftUIMacros.StateMacro` / `plugin for module
SwiftUIMacros not found` when the active standalone Command Line Tools uses
SDK 27 without the plugin needed for the new `@State` macro. Missing `$search`
and immutable-`self` diagnostics then follow from the failed expansion.

v0.1.1 changes the ten direct `@State` annotations to `@InkrailState`, a
project-local typealias to Apple's existing `SwiftUI.State<Value>` property
wrapper. This is not a custom state implementation or an SDK modification.
It preserves the older property-wrapper initialization model used by this
prototype; it does not implement the new macro's lazy initialization. The
UI, storage format and `@StateObject` model ownership are unchanged.

The packaging script now resolves Swift through `xcrun --sdk macosx`, reports
the selected toolchain and SDK, and type-checks a small SwiftUI state fixture
before starting the full build. The fixture exercises projected bindings,
optional state, backing-storage initialization and nonmutating assignment.
It is a compile probe, not a mounted-view lifecycle test.

Full Xcode is not required *by this alias workaround*. A complete, compatible
Apple SDK/toolchain remains required for the rest of the application. When
Xcode is already installed at the standard path, a per-command alternative is:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-app.sh
```

No global `xcode-select` change, system SDK edit, cache deletion, or letter
migration is part of this fix. The initial patch was authored on Linux; later native build results are
recorded in [Validation history](VALIDATION.md). Local notes are in `extras/STATE_COMPATIBILITY_FIX.md`.

## Scope of this version

The goal is closeness to Platen's writing-screen composition, not a generic
vintage editor. It is **not yet pixel-identical**. The capsule is drawn in 2D
with gradients rather than a scanned/3D physical material. Paper curvature
uses a projected native drawing and edge treatment, not a deforming 3D mesh.
Ink wear is subtle glyph variation, not a full simulated ribbon. All six sound
profiles are synthesized. Botanicals are original vector forms.

There is no destructive typewriter-correction mode, photo stamps, charms,
pack marketplace, iCloud sync, styled image/PDF export, or exact reproduction
of Platen's animation timings. The first build prioritizes editing, storage,
and the paper/rail/capsule visual relationship. In **Top** mode, editing in the
middle of a letter can still let the mechanism cover text on the following
line; scrolling or moving the insertion point exposes it. **Bottom** mode
keeps the mechanism below the native editor viewport. Following text remains
in the document and is available through normal scrolling.

Use the [paper-feed manual checklist](PAPER_FEED.md#manual-checklist) for
native verification, plus `extras/MAC_TEST_CHECKLIST.md` when those local notes
are available.
Use **AGENTS.md** for continuing development with Codex.

## Repository map

```text
Sources/Inkrail/                native application
  Editor/                      NSTextView bridge and glyph rendering
  Views/                       paper, capsule, lamp, studio, letter box
  Services/                    local audio, resources, text export
  Resources/                   original artwork, AppIcon.png + WAV files
Sources/InkrailCore/            portable models and durable local storage
Tests/InkrailCoreTests/         executable Foundation tests
scripts/build-app.sh           creates the local native .app
scripts/generate-assets.py     optional original-asset regeneration
scripts/generate-sound-styles.py original sound-profile synthesis (Python stdlib)
scripts/check-sounds.py        validates the exact set of 36 bundled WAV files
scripts/check-sounds-native.sh AVFoundation + packaged resource checks
scripts/check-paper-feed.sh    isolated native editor/font checks
scripts/check-paper-roll-render.sh isolated native roll scene renders
scripts/check-customization.sh production settings/paper component renders
scripts/check-ink-preferences.sh standalone font/ink preference and parameter checks
scripts/check-ink-rendering.sh native uneven-ink pixels, layout and Unicode checks
scripts/check-desk-preferences.sh standalone desk migration and focus-width checks
scripts/check-settings-popups.sh native dropdown contrast and binding checks
scripts/check-library-location.sh safe complete-library copying and path guards
scripts/check-storage-model.sh AppModel location persistence and failure checks
scripts/check-trash-retention.sh fixed-clock Recently Deleted expiry and failure checks
scripts/check-app-icon.sh       packaged and runtime application icon checks
scripts/check-machine-styles.sh twelve-style gallery and lamp/migration checks
packaging/                     app Info.plist
.github/workflows/macos.yml     native macOS build/test workflow
```

The app has **zero external Swift package dependencies**. The optional asset
regeneration script uses NumPy and Pillow; all generated assets are already
included, so these packages are not build or runtime requirements. The separate
sound-profile generator and WAV validator use only Python's standard library;
the new profiles preserve all eighteen Classic, Soft and Crisp WAVs. The finished
app icon includes a subtle Inkrail wordmark. The canonical artwork is
`Sources/Inkrail/Resources/AppIcon.png`; the build script uses it to generate
the Finder icon, and the application uses it as a fallback for SwiftPM launches.
Asset regeneration preserves that finished icon and writes
the procedural base icon to `.build/icon-base-generated.png` for reference.
