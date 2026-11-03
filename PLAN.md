# Penns — Remaining Plan

Penns is one note, always one glance away. The macOS app is built. It has:
- a menu bar glass panel
- an editor with checklists, Markdown headings and indentation, whose typing rules are unit-tested in `EditorRules`
- the archive, with a safety copy when a note is wiped
- lifespans, custom expiry and a morning fresh start
- profiles and Focus filters
- a desktop widget, Shortcuts, a Services menu item, a share button and a welcome window

This file holds three things: **how the app should look and behave** (§1), **what we learned the hard way** (§2), and **what isn't built yet** (§3 onward).

---

## 1. Preferences: design and behavior

These are settled decisions. Follow them for every new surface, including iOS and watchOS.

### 1.1 Product
- **Name:** Penns.
- **One active note per profile.** No lists, folders or search. Archive or delete leaves a blank note.
- **Everything is free.** There is no paid plan, Pro tier or paywall. Profiles, Focus filters and pinned widgets are available to everyone.
- **Feature filter:** a feature must make the note easier to *see*, faster to *capture*, or easier to *let go of*. It must not add something to manage or nag the user.
- **The note must be safe.** Losing text is the worst possible bug: save often, keep safety copies, and migrate data whenever storage moves.
- **README:** short, original and philosophical. It's not a feature list.

### 1.2 Look
- **Native Apple first.** Use system components wherever they exist: native `DatePicker`, system menus, the system share menu, `Form` in Settings. Don't hand-build a control the system already provides.
- **Liquid Glass:** the surface is system glass, with no opaque backgrounds behind it. Controls float as **glass pills** in a `GlassEffectContainer`.
- **Typography:** SF Pro, sans-serif, at Apple Notes sizes.
  - **One body style for the whole note** (14 pt Mac, 17 pt iOS by default). No separate title or first-line style.
  - **The user picks the font and size in Settings:** SF Pro, Rounded, Serif (New York), Monospaced, or any installed font family; 11–24 pt. Stored in the App Group defaults (`NoteStyle`), so the editor, widget, peek and archive all follow it.
  - The only exception is Markdown headings typed explicitly: `#` 22 pt bold, `##` 18 pt bold, `###` 15 pt semibold.
  - Heading marks are **hidden** once applied. Backspace at the start of a heading removes the heading.
- **Color:** system semantic colors. The accent color is the only highlight, plus a small dot per profile.
- **Spacing:** one 16 pt margin on every side. Left and right must be **symmetric**, and the text, pills and headers all line up on that margin.
- **Panel arrow:** a small, soft glass arrow (not spiky) points from the panel to the menu bar item and follows it when the panel is pushed in from a screen edge.
- **Checkboxes:** Notes-style circles that are **clearly visible on glass**: a soft fill plus a stroke when empty, and an accent fill with a white check when ticked. Ticked text is crossed out but **stays readable** (80% label color, not grey).
- **Archive call to action:** when every item is ticked, no extra button appears. The archive button itself **expands into a tinted "Archive" pill**. It must never look cramped: important pills keep their full size, and less important ones (lifespan) shrink to an icon.

### 1.3 Behavior
- **The panel opens ready.** It has focus instantly, the cursor is in the note, and the **first click counts**.
- **The panel closes like a popover:** on a click anywhere outside, on Esc, or when switching apps. The menu bar item toggles it.
- **The panel can be resized** by dragging any edge, and it remembers its size.
- **Menu bar item:** choose the icon from a set and its **size** (11–20 pt, default 16), or show the **first line as text only** with no icon. The icon stays choosable in text-only mode, because it returns while the note is empty.
- **Deep links:** `penns://note` opens the note, `penns://archive` opens the archive. The widget, Shortcuts and screenshot checks all use them.
- **Checklist editing:**
  - `- ` + space starts an item.
  - Return continues it.
  - **Return on an empty item removes the checkbox.**
  - **Backspace at the start of an item removes the whole checkbox in one keystroke**, not character by character.
- **Indentation:** Tab and Shift-Tab, for the current line or every selected line.
- **Expiry:** presets plus a **custom date and time**, chosen with the native picker.
- **Share button** in the toolbar pill, sharing clean text.
- **Onboarding:** in its **own window**, never inside the note.
- **Settings:** profile rows open on a click anywhere in the row (with a chevron), and their details are normal aligned rows.

---

## 2. Lessons learned (errors found and how to avoid them)

### Working practice
- **Relaunch after every build.** The user once saw an old build and reported a fix as missing.
- **Never simulate keystrokes (`osascript` / System Events) to test.** They went into the terminal instead of the app. Verify with screenshots, URL schemes (`penns://note`, `penns://archive`), logs and unit tests.
- **Check that scripted edits actually applied.** A multi-step edit once silently skipped a block, and the build failed in a confusing place. Assert every replacement, and build right after.
- **Measure layout in screenshots before claiming it's aligned.** The "16 pt" top margin was really about 6 pt until it was measured.
- **Back up user data before touching storage.** The store is SQLite with a write-ahead log (`Penns.store-wal`). Older text can often be recovered from the log with `strings` or a small parser.
- **Change editor rules test-first.** Most user-visible bugs were typing rules (checklist Backspace and Return, hidden markers). They now live in `EditorRules` with tests; extend those tests before changing behavior. Tests already caught a click-versus-arrow bug once.
- Sandboxed app preferences live at `~/Library/Containers/com.mirzapolat.penns/Data/Library/Preferences/`, not in `~/Library/Preferences`.

### Data and storage
- **Without a development team, the App Group container doesn't work.** The app quietly falls back to its own container, so the **app and the widget end up with separate stores**. Set a team early.
- **The store's location changes when the App Group ID changes** (`<TeamID>.com.mirzapolat.penns`). `SharedContainer.migrateLegacyStoreIfNeeded` copies the old store over, including the `-wal` and `-shm` files. Keep it.
- **Debounced saves (0.5 s) need flushing** when the panel closes and when the app quits.
- **A note was wiped by a single edit** (text set to empty at 01:39 on 3 Nov), and the cause is unknown. Undo after a programmatic `textView.string` change is one suspect. Mitigation: when one edit clears 20 or more characters, a copy goes to the archive. **The root cause is still open** (§3.1).
- **Suspected stale-context overwrite:** an archived note existed while `clearedCount` was 0. Settings (`ProfilesModel`) and the panel use separate `ModelContext`s, and saving a stale `Profile` may overwrite newer values. **To investigate** (§3.1).
- **Read fresh, write narrow:** every process (app, widget, intents) opens a fresh `ModelContext` per operation. Cross-process changes are announced with a Darwin notification; in-process changes use `NotificationCenter`.

### AppKit and SwiftUI on macOS 26
- **`NSPopover` can't be resized by the user**, so the note is an `NSPanel`: titled + `fullSizeContentView` + `nonactivatingPanel`, with a transparent titlebar and hidden window buttons.
- **The invisible titlebar strip of a `fullSizeContentView` panel swallows clicks** along the top edge, which made the archive back button and first-line clicks flaky. Hide the titlebar container view; edge resizing keeps working.
- **The hidden titlebar still reports a safe area.** With `.ignoresSafeArea()`, content slid up into the arrow's space, leaving the top margin at about 6 pt instead of 16 pt. Set `hosting.safeAreaRegions = []` on the panel's hosting view and don't use `ignoresSafeArea` inside it.
- **"Closing on resign key" isn't reliable for a menu bar app.** It also needs a global mouse-down monitor and `didResignActive`. Clicking the status item first closes the panel and then toggles it, so a 0.3 s guard prevents an instant reopen.
- **SwiftUI popovers inside the panel take key focus.** Don't close the panel when the new key window is an attached popover.
- **First click:** use `acceptsFirstMouse` on the hosting view and the text view, plus a non-activating panel that becomes key before `NSApp.activate()`.
- **Invisible shortcut-only buttons inside an `HStack` add spacing**, which caused the asymmetric margins. Put them in `.background`.
- **Floating cards inside a small panel get clipped.** Separate windows suit multi-step content such as onboarding.
- **Liquid Glass needs macOS 26 / iOS 26.** The deployment target was raised for `glassEffect`, `GlassEffectContainer`, `.glass` and `.glassProminent`. Glass in a custom shape (rounded panel with arrow) uses `glassEffect(_:in:)` on the SwiftUI root, not `NSGlassEffectView`.
- **Crowded pill rows:** use `fixedSize` + `layoutPriority` for important pills and `ViewThatFits` (full label, then icon) for compressible ones.
- **The custom checklist drawing needs TextKit 1** (`NSLayoutManager`) for glyph geometry. Markers are hidden with a clear color and negative kerning. Heading marks use a clear color and a 0.01 pt font. **The cursor must be kept out of hidden markers.** Only a one-step move left counts as leaving a marker; clicks land after it.
- **Never restyle text while IME composition is active** (`hasMarkedText`).
- **Without a main menu, ⌘C, ⌘V and ⌘Z don't work** in a menu bar app. Keep `MainMenu` even though it's never shown.
- **Services menu items** may only appear once the app is in /Applications or after logging in again.

### Swift 6 / frameworks
- **Hand-written `project.pbxproj` with file-system synchronized groups works.** New files and folders are picked up automatically. Info.plists and entitlements live outside synchronized folders, in `Config/`.
- **Widgets and intents:** do the work synchronously with a fresh `ModelContext` (no actor hops), use `AppIntentTimelineProvider` for async timelines, and use `static let` for intent metadata.
- **Widgets can't archive dynamic `NSColor` closures.** Use semantic SwiftUI styles (`.primary`, `.secondary`, `.tint`).
- **`Hasher` differs between processes.** Checklist item IDs use FNV-1a so a widget button toggles the right item.

---

## 3. macOS: still to build

### 3.1 Hardening (do first)
- **Set the development team** on both targets. This gives the app and widget the shared App Group store; the migration carries the existing note over.
- **Find the root cause of the note wipe.** Reproduce with undo after reload, the panel reopening with `textView.string` resets, and the `.id(note.id)` editor rebuild. Consider resetting or limiting undo when the text is replaced programmatically.
- **Investigate the stale-context overwrite** (`clearedCount`). Settings should save only the fields it changed, or re-fetch before writing.
- **Hands-on check:** desktop widget (profile picker, checklist buttons, Archive pill, clearing at expiry, chosen font), Services → Add to Penns, Focus filter switching, panel resizing, the native date picker inside the panel, the share menu, the cleared-note safety toast, the archive back button, Settings (font picker speed with many installed fonts, size and icon-size sliders).
- **If the font list is slow to open:** show the four system styles plus a "More Fonts…" entry that opens the full list.
- **Git:** initialize the repository and make the first commit.

### 3.2 iCloud sync (code ready, switched off)
- **Needs:** a paid developer team, the iCloud capability with a container (for example `iCloud.com.mirzapolat.penns`), and `CLOUDKIT_CONTAINER_IDENTIFIER` set.
- **Then verify:**
  - Two Macs, or a Mac and the future iPhone app.
  - Conflict repair keeps exactly one active note per profile.
  - The morning reset runs only once across devices (`lastResetDay`).
  - The widget refreshes after a remote change.
- **Option:** when last-writer-wins drops an edit, keep the losing text as an archived note.

### 3.3 Distribution
- Release build with Developer ID signing and notarization, or Mac App Store submission.
- App Store assets, a privacy manifest and localization scaffolding.

### 3.4 Later (needs the iPhone app)
- **Handoff:** keep `NSUserActivity` current while editing.
- **Share-sheet extension:** optional, in addition to the Services menu item.

---

## 4. iOS / iPadOS app (not started)

Same core, same preferences (§1). The editor is a `UITextView` that applies `EditorRules`, just like the Mac editor.

| Surface | What it does |
|---|---|
| **Editor** | Full screen with the cursor ready and a floating glass toolbar (lifespan, archive, share, archive list). Swipe up to archive, swipe down for the archive, undo toasts. |
| **Lock Screen fold line** | A faint line in the editor where the Lock Screen widget cuts the text off. Measured per device class and Dynamic Type size. |
| **Home Screen widget** | Small, medium and large (plus extra large on iPad). Interactive checklist circles and the tinted Archive pill. Tinted and clear rendering modes. StandBy support. |
| **Lock Screen widgets** | `accessoryRectangular` (first lines) and `accessoryInline` (first line). |
| **Live Activity** | Lock Screen banner and Dynamic Island, with checklist and Archive buttons. Handles the ~8-hour limit with a "Go Live again" prompt, a morning automation template and auto-renew. One activity per profile. Push-to-start (needs a server) is out of scope. |
| **Control Center / Action Button** | A `ControlWidget` that runs "Create & Go Live". |
| **Intents** | Reuse the Mac intents and add `GoLiveIntent` / `EndLiveIntent`. Add automation templates to onboarding ("7:00 → Go Live", "Arrive at supermarket → Groceries profile"). |
| **Share extension** | Shared text or URLs are added to the note. |
| **Onboarding** | Separate screens, never inside the note, plus a step showing how to add the widget (iOS can't add widgets for you). |
| **iPad** | Readable width, keyboard shortcuts (⇧⌘A archive, ⌘L go live, ⌘1…⌘9 profiles, Tab and Shift-Tab), Stage Manager and multiple windows. Check whether ActivityKit is supported on iPad and hide Go Live if not. |

---

## 5. watchOS app (not started)
- Complications and Smart Stack showing the first line of the note, plus the lifespan label.
- The note as one scrollable screen with tappable checklist items, a dictate button (append or replace) and Archive.
- Its own SwiftData + CloudKit store, with WatchConnectivity as a fallback if sync is too slow.

---

## 6. Open questions
1. What wiped the note at 01:39 on 3 Nov? (§3.1)
2. Is a full installed-font list in Settings fast enough, or is "More Fonts…" better?
3. Live Activity expiry: is auto-renew plus the morning automation enough, or is a small APNs push server worth it later?
4. Is the Lock Screen fold line accurate enough across devices and Dynamic Type sizes?
5. How fast does Watch sync through CloudKit, compared with WatchConnectivity?

## 7. Suggested order
1. macOS hardening (3.1)
2. iOS editor and widgets
3. Live Activity and Control Center
4. iCloud sync across Mac and iPhone (3.2)
5. watchOS
6. Distribution (3.3)
