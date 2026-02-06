import AppKit

/// Color definitions for sticky note themes — same pastel colors in both light and dark mode
enum NoteColor: String, CaseIterable {
    case yellow, pink, blue, green, purple, orange

    var displayName: String {
        rawValue.capitalized
    }

    var color: NSColor {
        switch self {
        case .yellow: return NSColor(red: 1.0, green: 0.976, blue: 0.769, alpha: 1.0)   // #FFF9C4
        case .pink:   return NSColor(red: 0.988, green: 0.894, blue: 0.925, alpha: 1.0)  // #FCE4EC
        case .blue:   return NSColor(red: 0.891, green: 0.949, blue: 0.992, alpha: 1.0)  // #E3F2FD
        case .green:  return NSColor(red: 0.910, green: 0.961, blue: 0.914, alpha: 1.0)  // #E8F5E9
        case .purple: return NSColor(red: 0.953, green: 0.898, blue: 0.961, alpha: 1.0)  // #F3E5F5
        case .orange: return NSColor(red: 1.0, green: 0.953, blue: 0.878, alpha: 1.0)    // #FFF3E0
        }
    }

    var hex: String {
        switch self {
        case .yellow: return "#FFF9C4"
        case .pink:   return "#FCE4EC"
        case .blue:   return "#E3F2FD"
        case .green:  return "#E8F5E9"
        case .purple: return "#F3E5F5"
        case .orange: return "#FFF3E0"
        }
    }

    static func from(_ name: String) -> NoteColor {
        NoteColor(rawValue: name) ?? .yellow
    }
}
