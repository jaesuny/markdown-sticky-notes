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

    /// Creation timestamp
    let createdAt: Date

    /// Last modification timestamp
    var modifiedAt: Date

    /// Initialize a new note with default values
    init(
        id: UUID = UUID(),
        content: String = "",
        position: CGPoint = CGPoint(x: 100, y: 100),
        size: CGSize = CGSize(width: 400, height: 500),
        isMinimized: Bool = false,
        opacity: Double = 0.95,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.position = position
        self.size = size
        self.isMinimized = isMinimized
        self.opacity = opacity
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
        case id, content, position, size, isMinimized, opacity, createdAt, modifiedAt
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
        size = CGSize(width: sizeDict["width"] ?? 400, height: sizeDict["height"] ?? 500)

        isMinimized = try container.decode(Bool.self, forKey: .isMinimized)
        opacity = try container.decode(Double.self, forKey: .opacity)
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
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
    }
}
