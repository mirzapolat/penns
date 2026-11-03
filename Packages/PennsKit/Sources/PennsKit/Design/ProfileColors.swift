import SwiftUI

/// The only color in Penns besides the system accent: a small dot per profile.
public enum ProfileColors {
    /// Apple system colors (dark-mode variants read well on glass in both modes).
    public static let all = ["#8E8E93", "#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#BF5AF2", "#FFD60A", "#40C8E0"]

    public static func color(_ hex: String) -> Color {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Which profile is shown. Stored in the App Group defaults so the app,
/// widgets and intents agree. A Focus filter overrides the user's choice.
public enum ProfileSelection {
    static let currentKey = "currentProfileID"
    static let focusKey = "focusProfileID"

    public static var defaults: UserDefaults {
        if let group = Bundle.main.object(forInfoDictionaryKey: SharedContainer.appGroupInfoKey) as? String,
           !group.isEmpty,
           let shared = UserDefaults(suiteName: group) {
            return shared
        }
        return .standard
    }

    public static var preferredID: UUID? {
        focusID ?? currentID
    }

    public static var currentID: UUID? {
        defaults.string(forKey: currentKey).flatMap(UUID.init(uuidString:))
    }

    public static var focusID: UUID? {
        defaults.string(forKey: focusKey).flatMap(UUID.init(uuidString:))
    }

    public static func setCurrent(_ id: UUID?) {
        defaults.set(id?.uuidString, forKey: currentKey)
    }

    public static func setFocus(_ id: UUID?) {
        defaults.set(id?.uuidString, forKey: focusKey)
    }
}
