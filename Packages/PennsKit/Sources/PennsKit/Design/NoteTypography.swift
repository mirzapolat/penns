import CoreGraphics
import SwiftUI

/// One text style for the whole note: SF Pro, regular, one size. No headings.
public enum NoteTypography {
    #if os(macOS)
    public static let size: CGFloat = 14
    #else
    public static let size: CGFloat = 17
    #endif

    public static let placeholder = "What's on your mind?"
    public static let freshStartPlaceholder = "What matters today?"

    public static var font: Font { .system(size: size) }
}

#if canImport(AppKit)
import AppKit

public extension NoteTypography {
    static var nsFont: NSFont { NSFont.systemFont(ofSize: size) }
}
#endif
