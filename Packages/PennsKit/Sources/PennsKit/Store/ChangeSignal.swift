import Foundation
import notify

/// Tells other parts of Penns that the store changed.
///
/// In-process listeners get a `NotificationCenter` notification. Writes from an
/// extension (widget buttons) also post a Darwin notification so the running
/// app can reload.
public enum ChangeSignal {
    public static let didChange = Notification.Name("PennsStoreDidChange")
    static let darwinName = "com.mirzapolat.penns.store-changed"

    public static func post(sender: AnyObject? = nil) {
        NotificationCenter.default.post(name: didChange, object: sender)
        if Bundle.main.bundleURL.pathExtension == "appex" {
            notify_post(darwinName)
        }
    }

    /// Calls `handler` on the main queue whenever an extension changed the store.
    @discardableResult
    public static func observeExtensionChanges(_ handler: @escaping @MainActor () -> Void) -> Int32 {
        var token: Int32 = 0
        notify_register_dispatch(darwinName, &token, DispatchQueue.main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        return token
    }
}
