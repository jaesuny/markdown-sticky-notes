import Foundation
import CoreGraphics

/// Represents a single sticky note
struct Note: Identifiable, Codable, Equatable {
    /// Unique identifier for the note
    let id: UUID

    /// Markdown content of the note
    var content: String

    /// Window position on screen
    var position: CGPoint

    /// Window size
    var size: CGSize

    /// Whether the window is minimized
    var isMinimized: Bool

    /// Window opacity (0.0 to 1.0)
    var opacity: Double

    /// Color theme name (yellow, pink, blue, green, purple, orange)
    var colorTheme: String

    /// Cursor position (character offset) for restoring on reopen
    var cursorPosition: Int

    /// Scroll position (pixels from top) for restoring on reopen
    var scrollTop: Double

    /// Whether this note should always stay on top of other windows
    var alwaysOnTop: Bool

    /// Creation timestamp
    let createdAt: Date

    /// Last modification timestamp
    var modifiedAt: Date

    /// Initialize a new note with default values
    init(
        id: UUID = UUID(),
        content: String = "",
        position: CGPoint = CGPoint(x: 100, y: 100),
        size: CGSize = CGSize(width: 300, height: 360),
        isMinimized: Bool = false,
        opacity: Double = 0.95,
        colorTheme: String = "yellow",
        cursorPosition: Int = 0,
        scrollTop: Double = 0,
        alwaysOnTop: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.position = position
        self.size = size
        self.isMinimized = isMinimized
        self.opacity = opacity
        self.colorTheme = colorTheme
        self.cursorPosition = cursorPosition
        self.scrollTop = scrollTop
        self.alwaysOnTop = alwaysOnTop
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Update the modification timestamp
    mutating func updateModificationDate() {
        self.modifiedAt = Date()
    }
}

// MARK: - Codable Conformance
extension Note {
    enum CodingKeys: String, CodingKey {
        case id, content, position, size, isMinimized, opacity, colorTheme, cursorPosition, scrollTop, alwaysOnTop, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)

        // Decode CGPoint
        let positionDict = try container.decode([String: Double].self, forKey: .position)
        position = CGPoint(x: positionDict["x"] ?? 100, y: positionDict["y"] ?? 100)

        // Decode CGSize
        let sizeDict = try container.decode([String: Double].self, forKey: .size)
        size = CGSize(width: sizeDict["width"] ?? 300, height: sizeDict["height"] ?? 360)

        isMinimized = try container.decode(Bool.self, forKey: .isMinimized)
        opacity = try container.decode(Double.self, forKey: .opacity)
        colorTheme = try container.decodeIfPresent(String.self, forKey: .colorTheme) ?? "yellow"
        cursorPosition = try container.decodeIfPresent(Int.self, forKey: .cursorPosition) ?? 0
        scrollTop = try container.decodeIfPresent(Double.self, forKey: .scrollTop) ?? 0
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)

        // Encode CGPoint as dictionary
        let positionDict = ["x": position.x, "y": position.y]
        try container.encode(positionDict, forKey: .position)

        // Encode CGSize as dictionary
        let sizeDict = ["width": size.width, "height": size.height]
        try container.encode(sizeDict, forKey: .size)

        try container.encode(isMinimized, forKey: .isMinimized)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(colorTheme, forKey: .colorTheme)
        try container.encode(cursorPosition, forKey: .cursorPosition)
        try container.encode(scrollTop, forKey: .scrollTop)
        try container.encode(alwaysOnTop, forKey: .alwaysOnTop)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
    }
}
