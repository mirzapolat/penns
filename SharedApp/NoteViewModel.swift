#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreData
import Observation
import os
import PennsKit
import SwiftData
import SwiftUI
import WidgetKit

/// Lets menus outside the editor (the "…" menu, the iOS "Aa" button) format
/// the editor's current selection. The editor sets `perform`.
@MainActor
final class FormatBridge {
    var perform: ((TextFormat) -> Void)?
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let actionTitle: String?
    let action: (@MainActor () -> Void)?
}

/// Owns the note shown in the menu bar panel and every action on it.
@MainActor
@Observable
final class NoteViewModel {
    private(set) var profile: Profile
    private(set) var profiles: [Profile] = []
    private(set) var note: Note
    var showingArchive = false {
        didSet { if showingArchive { refreshArchive() } }
    }
    private(set) var toast: Toast?
    private(set) var controlsVisible = true
    private(set) var focusToken = 0
    private(set) var now = Date()
    private(set) var archived: [Note] = []

    /// Called whenever the note's text or identity changes (menu bar title).
    @ObservationIgnored var onNoteChange: (() -> Void)?
    @ObservationIgnored let formatBridge = FormatBridge()

    func format(_ format: TextFormat) {
        formatBridge.perform?(format)
    }

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var store: NoteStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var controlsTask: Task<Void, Never>?
    @ObservationIgnored private var typingBurstStart: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let logger = Logger(subsystem: "com.mirzapolat.penns", category: "note")

    init(container: ModelContainer) {
        self.container = container
        let store = NoteStore(context: ModelContext(container))
        store.applyDueTransitions()
        let profile = store.currentProfile(preferredID: ProfileSelection.preferredID)
        self.store = store
        self.profile = profile
        self.note = store.activeNote(in: profile)
        persist()
        refreshArchive()
        observeExternalChanges()
    }

    // MARK: Derived state

    var text: String {
        get { note.text }
        set {
            guard newValue != note.text else { return }
            if store.setText(newValue, of: note) != nil {
                // A whole note was wiped in one edit: a copy went to the archive.
                persist()
                refreshArchive()
                showToast("Cleared note kept in Archive", actionTitle: "Show") { [weak self] in
                    self?.showingArchive = true
                }
            } else {
                scheduleSave()
            }
            onNoteChange?()
        }
    }

    var placeholder: String {
        profile.morningResetEnabled ? NoteTypography.freshStartPlaceholder : NoteTypography.placeholder
    }

    var clearedCount: Int { profile.clearedCount }

    /// The note as clean text for sharing: checkboxes as ○ / ✓, no heading marks.
    var shareText: String {
        Checklist.displayText(note.text).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var hasMultipleProfiles: Bool { profiles.count > 1 }
    var isStale: Bool { Lifecycle.isStale(note, now: now) }
    var allChecked: Bool { Checklist.allChecked(note.text) }

    var lifespanChipText: String {
        guard let expiresAt = note.expiresAt else { return "until done" }
        return Lifecycle.expiryLabel(expiresAt, now: now)
    }

    /// First line for the menu bar, truncated, plus a lifespan hint.
    var menuBarTitle: String {
        var line = note.firstLine
        if line.count > 28 { line = String(line.prefix(27)).trimmingCharacters(in: .whitespaces) + "…" }
        guard !line.isEmpty else { return "" }
        if let expiresAt = note.expiresAt {
            return line + " · " + Lifecycle.expiryLabel(expiresAt, now: now)
        }
        return line
    }

    // MARK: Panel lifecycle

    func prepareForDisplay() {
        reload()
        tick()
        controlsVisible = true
        focusToken &+= 1
    }

    func tick() {
        now = Date()
        let expired = store.applyExpiries()
        let reset = store.applyMorningResets()
        guard !expired.isEmpty || !reset.isEmpty else { return }
        animate { note = store.activeNote(in: profile) }
        commit()
        if let first = expired.first(where: { $0.profile?.id == profile.id }) {
            showToast("Your note expired", actionTitle: "Restore") { [weak self] in self?.restore(first) }
        } else if let first = reset.first(where: { $0.profile?.id == profile.id }) {
            showToast("Fresh start — yesterday's note archived", actionTitle: "Restore") { [weak self] in self?.restore(first) }
        }
    }

    /// Reads the store fresh, e.g. after a widget button, Shortcut, Focus change
    /// or iCloud sync changed it.
    func reload() {
        reload(fromSync: false)
    }

    /// `fromSync`: iCloud brought in changes from another device. If this
    /// device has unsaved typing, saving it first would silently replace the
    /// other device's version (or vice versa). Instead, the typing stays the
    /// note and the other version goes to the archive.
    private func reload(fromSync: Bool) {
        let unsaved: (noteID: UUID, text: String)? = fromSync && saveTask != nil ? (note.id, note.text) : nil
        if unsaved == nil {
            flushPendingSave()
        } else {
            saveTask?.cancel()
            saveTask = nil
        }
        store = NoteStore(context: ModelContext(container))
        store.applyDueTransitions()
        profile = store.currentProfile(preferredID: ProfileSelection.preferredID)
        note = store.activeNote(in: profile)

        var kept: Note?
        if let unsaved {
            if note.id == unsaved.noteID {
                if note.text != unsaved.text {
                    kept = store.keepConflictCopy(note.text, of: note)
                    store.setText(unsaved.text, of: note)
                }
            } else {
                // The note was archived or replaced elsewhere: keep the typing.
                kept = store.keepConflictCopy(unsaved.text, of: note)
            }
        }
        persist(notify: kept != nil)
        refreshArchive()
        onNoteChange?()
        if kept != nil {
            showToast("Edited on another device — other version in Archive", actionTitle: "Show") { [weak self] in
                self?.showingArchive = true
            }
        }
    }

    /// Writes any pending edit to disk now (panel closing, app quitting).
    func flush() {
        flushPendingSave()
    }

    // MARK: Actions

    func archive() {
        guard !note.isBlank else { return }
        let old = note
        animate { note = store.archive(old) }
        commit()
        showToast("Archived", actionTitle: "Undo") { [weak self] in
            guard let self else { return }
            animate { self.note = self.store.restore(old, isUndo: true) }
            commit()
        }
    }

    func deleteNote() {
        guard !note.isBlank else { return }
        let (snapshot, blank) = store.delete(note)
        animate { note = blank }
        commit()
        showToast("Deleted", actionTitle: "Undo") { [weak self] in
            guard let self else { return }
            animate { self.note = self.store.undoDelete(snapshot) }
            commit()
        }
    }

    func restore(_ archivedNote: Note) {
        animate {
            note = store.restore(archivedNote)
            showingArchive = false
        }
        commit()
    }

    func deleteArchived(_ archivedNote: Note) {
        store.deleteArchived(archivedNote)
        commit()
    }

    func setLifespan(_ lifespan: Lifespan) {
        store.setLifespan(lifespan, of: note)
        commit()
    }

    func setExpiry(_ date: Date?) {
        store.setExpiry(date, of: note)
        commit()
    }

    func keepStale() {
        store.dismissStale(note)
        commit()
    }

    /// Switching by hand wins over a Focus filter until the Focus changes again.
    func switchProfile(to target: Profile) {
        guard target.id != profile.id else { return }
        flushPendingSave()
        ProfileSelection.setFocus(nil)
        ProfileSelection.setCurrent(target.id)
        animate {
            profile = target
            note = store.activeNote(in: target)
            showingArchive = false
        }
        commit()
        focusToken &+= 1
    }

    func switchProfile(at index: Int) {
        guard profiles.indices.contains(index) else { return }
        switchProfile(to: profiles[index])
    }

    func performToastAction() {
        let action = toast?.action
        toast = nil
        action?()
    }

    func appendFromService(_ text: String) {
        store.append(text, in: profile)
        commit()
    }

    // MARK: Controls fade while typing

    func noteTyping() {
        let moment = Date()
        if typingBurstStart == nil { typingBurstStart = moment }
        if let start = typingBurstStart, moment.timeIntervalSince(start) > 1.5, controlsVisible {
            withAnimation(.easeOut(duration: 0.3)) { controlsVisible = false }
        }
        controlsTask?.cancel()
        controlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.showControls()
        }
    }

    func showControls() {
        typingBurstStart = nil
        guard !controlsVisible else { return }
        withAnimation(.easeIn(duration: 0.25)) { controlsVisible = true }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func flushPendingSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        persist()
    }

    /// Saves now, refreshes derived state and tells everyone else.
    private func commit() {
        saveTask?.cancel()
        persist()
        refreshArchive()
        onNoteChange?()
    }

    private func persist(notify: Bool = true) {
        saveTask = nil
        do {
            guard store.context.hasChanges else { return }
            try store.save()
        } catch {
            logger.error("Saving failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard notify else { return }
        ChangeSignal.post(sender: self)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshArchive() {
        profiles = store.profiles()
        archived = store.archivedNotes(in: profile)
    }

    private func observeExternalChanges() {
        // Intents, Settings and the Focus filter inside this process.
        observers.append(NotificationCenter.default.addObserver(
            forName: ChangeSignal.didChange, object: nil, queue: .main
        ) { [weak self] notification in
            let fromSelf = notification.object as AnyObject? === self
            guard !fromSelf else { return }
            MainActor.assumeIsolated { self?.reload() }
        })
        // iCloud sync imported changes from another device.
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload(fromSync: true)
                WidgetCenter.shared.reloadAllTimelines()
            }
        })
        // Widget buttons (separate process).
        ChangeSignal.observeExtensionChanges { [weak self] in
            self?.reload()
        }
    }

    // MARK: Helpers

    func showToast(_ message: String, actionTitle: String?, action: (@MainActor () -> Void)?) {
        toast = Toast(message: message, actionTitle: actionTitle, action: action)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func animate(_ body: () -> Void) {
        #if os(macOS)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        #endif
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2), body)
        } else {
            withAnimation(.spring(duration: 0.35, bounce: 0.15), body)
        }
    }
}
