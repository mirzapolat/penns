# Penns

One note, always one glance away: a Mac menu bar app, an iPhone/iPad app and an Apple Watch app sharing one core. These are settled decisions; follow them on every surface.

## Layout

- `Packages/PennsKit`: the core (models, `NoteStore`, `EditorRules`, `Checklist`, `ListMarker`, `InlineMarkup`, `LockScreenFold`, `WatchSnapshot`/`WatchCommand`) with all the unit tests.
- `Penns/` Mac app · `PennsiOS/` iPhone/iPad app · `PennsWatch/` watch app · `PennsShare/` iOS share extension.
- `PennsWidget/` widgets for Mac and iOS (`#if os(iOS)` for Lock Screen, Live Activity, Control) · `PennsWatchWidget/` complications.
- `SharedApp/` code for both apps (view model, profiles, fonts, App Intents, Handoff) · `Shared/` code for apps and extensions (store intents, `LiveActivity/`).
- `Config/` holds every Info.plist and entitlements file. The `.pbxproj` is hand-written with synchronized folders: new files are picked up automatically.

## Product

- **One active note per profile.** No lists of notes, folders or search. Archiving or deleting leaves a blank note.
- **Everything is free.** No paid plan, Pro tier or paywall.
- **Feature filter:** a feature must make the note easier to *see*, faster to *capture* or easier to *let go of*. Nothing to manage, nothing that nags.
- **The note must be safe.** Losing text is the worst bug: save often, keep safety copies, migrate whenever storage moves, back up before touching it.
- **README:** advertising but down-to-earth (*bodenständig*): a clear promise, a few concrete benefits, where Penns lives, the philosophy as the closing line. No hype, no superlatives.

## Look

- **Native Apple first:** system `DatePicker`, menus, share sheet, `Form` in Settings. Don't hand-build what the system provides.
- **Liquid Glass:** system glass surfaces; controls float as glass pills in a `GlassEffectContainer`. Minimal: no extra chrome.
- **Typography:** one body style for the whole note (14 pt Mac, 17 pt iOS by default; the user picks font and size, stored in App Group defaults as `NoteStyle`). Only explicit headings differ (`#` 22, `##` 18, `###` 15 pt at a 14 pt body), with their marks hidden.
- **Color:** system semantic colors; the accent is the only highlight, plus a small dot per profile.
- **Spacing:** one 16 pt margin on every side, symmetric. Text, pills and headers line up on it.
- **Checkboxes:** Notes-style circles, clearly visible on glass. Ticked text is crossed out but stays readable (80% label color).
- **All done:** no extra button appears; the archive button grows into a tinted "Archive" pill. Important pills keep full size; less important ones (lifespan) shrink to an icon.
- **Mac toolbar pill:** archive, share, Format (Aa), "…" (Show Archive, profiles, settings). **iOS:** Aa, archive, share, "…" (Go Live, Show Archive, settings).

## Behavior

- **Mac panel:** opens ready (focus, cursor in the note, first click counts), closes like a popover (click outside, Esc, app switch), resizable, remembers its size. The menu bar shows an icon (choice + size) or the first line.
- **Deep links:** `penns://note`, `penns://archive`.
- **Typing rules** (`EditorRules`, shared by both editors, tested):
  - `- ` + space starts a checklist (the user chose this over Apple Notes' dashed list). `* ` → `• `, `-- ` → `– `, `1. ` numbered.
  - Return continues an item or list (numbers count up and renumber); Return on an empty item ends it; Backspace right after a marker removes the whole marker.
  - Bold `**b**`, italic `_i_`, underline `++u++`, strikethrough `~~s~~` are hidden markers. Apple Notes shortcuts: ⌘B ⌘I ⌘U ⇧⌘X, lists ⇧⌘7 ⇧⌘8 ⇧⌘9, checklist ⇧⌘L.
  - Tab / Shift-Tab indent every selected line. The caret never rests inside a hidden marker.
- **Lifespans:** presets plus a custom date and time (native picker); optional morning fresh start per profile.
- **Onboarding** in its own window/screens, never inside the note.
- **iOS Lock Screen:** a faint line in the editor marks where the rectangular widget stops (`LockScreenFold`). Full width means the Live Activity ("Go Live"), renewed when the app opens.
- **Sync:** iCloud (SwiftData + CloudKit) between Mac and iPhone; unsaved typing wins over an incoming version, and the other version goes to the archive. The watch talks only to the iPhone (WatchConnectivity); the iPhone is its source of truth.

## Working on Penns

- **Relaunch the Mac app after every build**, or the user sees an old build.
- **Never simulate keystrokes** (osascript / System Events): they land in the terminal. **Don't use the iOS Simulator.** Verify with `xcodebuild`, PennsKit tests (`swift test` in `Packages/PennsKit`), logs and `penns://` links; the user checks on device. Don't screenshot while the user is working on the Mac.
- **Change typing rules test-first** in PennsKit; most user-visible bugs were typing rules.
- **Assert every scripted edit** (a silent skip once broke the build far away). In the `.pbxproj`, markers can appear twice and Xcode may re-sort the file: check uniqueness before inserting.
- **Measure layout in screenshots** before claiming it's aligned.
- **Back up the store before touching storage:** SQLite with a WAL (`Penns.store-wal`); old text can often be recovered from it.
- Mac sandbox preferences live in `~/Library/Containers/com.mirzapolat.penns/Data/Library/Preferences/`. The Mac store lives in `~/Library/Group Containers/<TeamID>.com.mirzapolat.penns/`.
- DEBUG launch arguments for on-device screenshots: `-PennsDemoNote`, `-PennsDemoDone`, `-PennsDemoArchive`, `-PennsDemoFormat`.

## Gotchas

**Data**
- SwiftData saves *every* attribute of a changed object: a long-lived context writes stale values back. Read fresh, write narrow: one fresh `ModelContext` per operation (`NoteStore.updateProfile(id:in:)` for Settings).
- Changes are announced with `ChangeSignal`: `NotificationCenter` in-process, a Darwin notification from extensions.
- Debounced saves (0.5 s) must be flushed when the panel closes, the app backgrounds or quits.
- Undo is per editor and cleared whenever the text is replaced in code, or ⌘Z can wipe the note. A one-edit clear of 20+ characters leaves a safety copy in the archive.
- The store location follows the App Group id; `SharedContainer.migrateLegacyStoreIfNeeded` copies the old store (with `-wal`/`-shm`). Keep it.
- **Versioned schema:** `PennsSchemaV1` + `PennsMigrationPlan`. Any change to `Note`/`Profile` needs a new schema version (freeze the old models inside the old version) and a stage, plus a test that an old store opens with its text. CloudKit is additive only: never rename or remove an attribute once the schema is in Production.
- **Backups:** the app (never an extension) copies the store to `Backups/<UTC stamp>/` next to it before opening: at most every 12 h, always when the app version changes; the newest 5 are kept. Unsaved text goes to `Rescue/*.txt` when a save fails.
- **Store won't open:** `SharedContainer.loadFailure` is set and `shared` is an empty in-memory store. Apps show an error instead of the note (Mac alert + quit, iOS `StoreUnavailableView`); extensions call `SharedContainer.requireAvailable()` before writing. Never let the user type into the stand-in.
- **Sync duplicates:** the first profile always gets `Profile.defaultID`, so two devices' defaults merge. Copies with the same id are shown and edited as one (`profiles()` dedupes, `updateProfile` writes to every copy, `reconcile()` aligns counters). Never delete a copy to dedupe: deletion cascades to notes and two devices can delete each other's. `repair` keeps the note with text over a newer blank one.
- Signing: the Team ID lives only in `Config/Local.xcconfig` (gitignored, included by `Config/Signing.xcconfig`); never commit it, and don't set the team in Xcode's Signing tab (that writes it into the project). Identity "Apple Development" (ad-hoc `-` disables the App Group). Mac App Group `<TeamID>.com.mirzapolat.penns`; iOS/watch `group.com.mirzapolat.penns`. Build with `-allowProvisioningUpdates`.
- `Hasher` differs between processes: checklist item ids use FNV-1a.

**Mac (AppKit/SwiftUI, macOS 26)**
- The note is an `NSPanel` (titled, `fullSizeContentView`, non-activating) because `NSPopover` can't be resized. Hide the titlebar container (it swallows clicks) and set `hosting.safeAreaRegions = []` (no `ignoresSafeArea`).
- Closing needs a global mouse-down monitor plus `didResignActive`; a 0.3 s guard stops the status item reopening it. Attached SwiftUI popovers take key focus: don't close for them.
- First click: `acceptsFirstMouse` on the hosting view and text view; the panel becomes key before `NSApp.activate()`.
- Shortcut-only invisible buttons go in `.background`, not in an `HStack` (they add spacing). Keep `MainMenu`, or ⌘C/⌘V/⌘Z and the format shortcuts stop working.
- Crowded pill rows: `fixedSize` + `layoutPriority` for important pills, `ViewThatFits` for compressible ones.
- Checkbox drawing needs TextKit 1. Hidden markers use a clear color plus negative kerning (checklists, measured per marker) or a 0.01 pt font (headings, inline styles). Never restyle during IME composition.
- Services menu items may only appear once the app is in /Applications or after logging in again.

**iOS / watchOS / widgets**
- `UITextView(usingTextLayoutManager:)` skips a Swift subclass's initializers: build the TextKit 1 stack by hand and use `init(frame:textContainer:)`. Bring the checkbox canvas to the front in `layoutSubviews`.
- App Shortcut `systemImageName` must be a literal (use `#if os()` inside the builder). Intent metadata uses `static let`.
- Widgets: do the work synchronously with a fresh `ModelContext`; use semantic SwiftUI styles, not dynamic `NSColor`. Live Activity buttons use `LiveActivityIntent` so they run in the app and can update the activity.
- `WatchSnapshot.applying(_:)` (the watch's instant preview) must match `WatchCommand.apply(to:)` on the iPhone; a test checks this.

## To do

1. **Device checks:** Mac (widget, Services, Focus, formatting), iPhone/iPad (typing rules, formatting, Lock Screen widget and line, Live Activity, Penns Live control, share extension, iPad shortcuts), Apple Watch (pairing, commands while the iPhone app is closed, complications).
2. **iCloud:** add the iCloud capability (container `iCloud.com.mirzapolat.penns`) to `Penns` and `PennsiOS` (+ Push Notifications on Mac, Background Modes → Remote notifications on iOS), then set `CLOUDKIT_CONTAINER_IDENTIFIER`. Verify: one active note per profile after conflicts, the morning reset runs once (`lastResetDay`), widgets refresh after remote changes. Deploy the CloudKit schema to Production before release.
3. **Distribution (App Store, universal purchase: Mac and iOS share `com.mirzapolat.penns`):** version 1.0 and `ITSAppUsesNonExemptEncryption = NO` are set. Still to do: App Store Connect record, privacy policy + support URL, "Data Not Collected" label, age rating, screenshots (iPhone 6.9", iPad 13", Mac, Watch; `-PennsDemo*`), review note that the Mac app lives in the menu bar, archive + upload, TestFlight for 1–2 weeks. Bump `CURRENT_PROJECT_VERSION` for every upload.
4. **CI:** `.github/workflows/ci.yml` runs PennsKit tests and unsigned Mac/iOS builds on `macos-26`.

**Open questions:** is Live Activity auto-renew enough, or a push server later? Is the Lock Screen line right across devices and text sizes? Is WatchConnectivity reliable when the iPhone app has been closed for a long time?
