# Penns — Remaining Plan

Penns is one note, always one glance away. The macOS app is built: menu bar glass panel, editor with checklists, headings and indentation, archive, lifespans and custom expiry, morning fresh start, profiles and Focus filters, desktop widget, Shortcuts, the Services menu item and the welcome window. `README.md` describes how to use it. This file lists only what is **not built yet**.

## Ground rules (keep for everything below)

- **One active note per profile.** No lists, folders or search. Archive or delete leaves a blank note.
- **Design:**
  - Native Liquid Glass with floating glass pills for controls.
  - SF Pro in a single body style (14 pt Mac, 17 pt iOS). The only exception is Markdown headings (`#`, `##`, `###`), whose marks are hidden once applied.
  - System colors. The accent color is the only highlight, plus a small dot per profile.
- **Feature filter:** every feature must make the note easier to *see*, faster to *capture*, or easier to *let go of*. It must not add something to manage or nag the user.
- **Shared core:** reuse `Packages/PennsKit` for the model, `NoteStore`, lifecycle, checklists, Markdown and profiles. Write new logic there, with tests.

---

## 1. macOS: still to build

### 1.1 Hardening (do first)
- **Editor tests:** move the editor's text rules out of `NoteEditor.swift` into PennsKit as pure functions on string + selection, with unit tests:
  - `- ` + space starts a checklist item.
  - Return continues an item or indentation, and ends it on an empty line.
  - Backspace removes the whole checklist or heading marker.
  - Tab / Shift-Tab indent and outdent.
  - The cursor never rests inside hidden markers.
- **Hands-on check:** run through everything not yet tried manually:
  - Desktop widget: profile picker, checklist buttons, Archive button, clearing at expiry.
  - Services → Add to Penns (needs the app in /Applications).
  - Focus filter switching.
  - Resizing the panel.
  - Native date picker inside the panel.
  - Share menu.
- **Git:** initialize the repo and make a first commit.

### 1.2 Pro (StoreKit 2)
- **Decide first:** lifetime unlock or subscription, and the price.
- **Free:** one profile, every surface, lifespans, morning reset, widget, Shortcuts.
- **Pro:** more than one profile, Focus filters, and widgets pinned to a profile.
- **How:**
  - Entitlement from `Transaction.currentEntitlements`, cached in the App Group so the widget and intents can read it.
  - A local `.storekit` configuration for testing.
  - A quiet upgrade sheet when adding a second profile.

### 1.3 iCloud sync (code ready, switched off)
- **Needs:** a paid developer team, the iCloud capability with a container (for example `iCloud.com.mirzapolat.penns`), and `CLOUDKIT_CONTAINER_IDENTIFIER` set.
- **Then verify:**
  - Two Macs, or a Mac and the future iPhone app.
  - Conflict repair keeps exactly one active note per profile.
  - The morning reset runs only once across devices (`lastResetDay`).
  - The widget refreshes after a remote change.
- **Option:** when last-writer-wins drops an edit, keep the losing text as an archived note instead.

### 1.4 Distribution
- Release build with Developer ID signing and notarization, or Mac App Store submission.
- App Store assets, a privacy manifest and localization scaffolding.

### 1.5 Later (needs the iPhone app)
- **Handoff:** keep `NSUserActivity` current while editing, so you can continue on another device.
- **Share-sheet extension:** optional, in addition to the Services menu item.

---

## 2. iOS / iPadOS app (not started)

Same core, same design rules. The editor is a `UITextView` port of the Mac editor rules from 1.1.

| Surface | What it does |
|---|---|
| **Editor** | Full screen with the cursor ready and a floating glass toolbar (lifespan, archive, share, archive list). Swipe up to archive, swipe down for the archive, undo toasts. |
| **Lock Screen fold line** | A faint line in the editor where the Lock Screen widget cuts the text off. Measured per device class and Dynamic Type size. |
| **Home Screen widget** | Small, medium and large (plus extra large on iPad). Interactive checklist circles and an Archive button. Tinted and clear rendering modes. StandBy support. |
| **Lock Screen widgets** | `accessoryRectangular` (first lines) and `accessoryInline` (first line). |
| **Live Activity** | Lock Screen banner and Dynamic Island, with checklist and Archive buttons. Handles the ~8-hour limit with a "Go Live again" prompt, a morning automation template and auto-renew. One activity per profile. Push-to-start (needs a server) is out of scope. |
| **Control Center / Action Button** | A `ControlWidget` that runs "Create & Go Live". |
| **Intents** | Reuse the Mac intents and add `GoLiveIntent` / `EndLiveIntent`. Add automation templates to onboarding ("7:00 → Go Live", "Arrive at supermarket → Groceries profile"). |
| **Share extension** | Shared text or URLs are added to the note. |
| **Onboarding** | A welcome screen plus a step showing how to add the widget (iOS can't add widgets for you). |
| **iPad** | Readable width, keyboard shortcuts (⇧⌘A archive, ⌘L go live, ⌘1…⌘9 profiles), Stage Manager and multiple windows. Check whether ActivityKit is supported on iPad and hide Go Live if not. |

---

## 3. watchOS app (not started)
- Complications and Smart Stack showing the first line of the note, plus the lifespan label.
- The note as one scrollable screen with tappable checklist items, a dictate button (append or replace) and Archive.
- Its own SwiftData + CloudKit store, with WatchConnectivity as a fallback if sync is too slow.

---

## 4. Open questions
1. Pro pricing: lifetime unlock or subscription.
2. Live Activity expiry: is auto-renew plus the morning automation enough, or is a small APNs push server worth it later?
3. Is the Lock Screen fold line accurate enough across devices and Dynamic Type sizes?
4. How fast does Watch sync through CloudKit, compared with WatchConnectivity?

## 5. Suggested order
1. macOS hardening (1.1)
2. Pro decision and StoreKit (1.2)
3. iOS editor and widgets
4. Live Activity and Control Center
5. iCloud sync across Mac and iPhone (1.3)
6. watchOS
7. Distribution (1.4)
