import CoreGraphics
import SwiftUI

/// The font family the note is set in. Chosen in Settings.
public enum NoteFont: Hashable, Sendable {
    case system
    case rounded
    case serif
    case monospaced
    /// Any installed font family, by name.
    case family(String)

    public static let builtIn: [NoteFont] = [.system, .rounded, .serif, .monospaced]

    public init(storageValue: String) {
        switch storageValue {
        case "rounded": self = .rounded
        case "serif": self = .serif
        case "monospaced": self = .monospaced
        case let value where value.hasPrefix("family:"): self = .family(String(value.dropFirst(7)))
        default: self = .system
        }
    }

    public var storageValue: String {
        switch self {
        case .system: "system"
        case .rounded: "rounded"
        case .serif: "serif"
        case .monospaced: "monospaced"
        case .family(let name): "family:" + name
        }
    }

    public var displayName: String {
        switch self {
        case .system: "Default (SF Pro)"
        case .rounded: "Rounded"
        case .serif: "Serif (New York)"
        case .monospaced: "Monospaced"
        case .family(let name): name
        }
    }
}

/// Font and size of the note, shared by the editor, widget, peek and archive.
/// Stored in the App Group defaults so the widget follows the app.
public struct NoteStyle: Equatable, Sendable {
    public static let fontKey = "noteFont"
    public static let sizeKey = "noteFontSize"
    public static let sizeRange: ClosedRange<Double> = 11...24
    #if os(macOS)
    public static let defaultSize: Double = 14
    #else
    public static let defaultSize: Double = 17
    #endif

    public var font: NoteFont
    public var size: CGFloat

    public init(font: NoteFont = .system, size: CGFloat = CGFloat(NoteStyle.defaultSize)) {
        self.font = font
        self.size = min(max(size, CGFloat(Self.sizeRange.lowerBound)), CGFloat(Self.sizeRange.upperBound))
    }

    public init(fontValue: String, size: Double) {
        self.init(font: NoteFont(storageValue: fontValue), size: CGFloat(size))
    }

    public static var current: NoteStyle {
        let defaults = ProfileSelection.defaults
        let size = defaults.object(forKey: sizeKey) as? Double ?? defaultSize
        return NoteStyle(fontValue: defaults.string(forKey: fontKey) ?? "system", size: size)
    }

    /// Heading sizes relative to the body: `#` 22, `##` 18, `###` 15 at a 14 pt body.
    public static func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: 22.0 / 14
        case 2: 18.0 / 14
        default: 15.0 / 14
        }
    }

    public func swiftUIFont(scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
        let size = size * scale
        switch font {
        case .system: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        case .family(let name): return .custom(name, size: size).weight(weight)
        }
    }
}

public enum NoteTypography {
    public static let placeholder = "What's on your mind?"
    public static let freshStartPlaceholder = "What matters today?"

    /// The current body size and font.
    public static var size: CGFloat { NoteStyle.current.size }
    public static var font: Font { NoteStyle.current.swiftUIFont() }
}

#if canImport(AppKit)
import AppKit

public extension NoteStyle {
    func nsFont(scale: CGFloat = 1, weight: NSFont.Weight = .regular) -> NSFont {
        let size = size * scale
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign?
        switch font {
        case .system: return base
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .monospaced: design = .monospaced
        case .family(let name):
            let traits: NSFontTraitMask = weight.rawValue >= NSFont.Weight.semibold.rawValue ? .boldFontMask : []
            return NSFontManager.shared.font(withFamily: name, traits: traits, weight: 5, size: size) ?? base
        }
        if let design, let descriptor = base.fontDescriptor.withDesign(design),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }
}

public extension NoteTypography {
    static var nsFont: NSFont { NoteStyle.current.nsFont() }
}
#endif
