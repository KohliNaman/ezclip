import Foundation

enum TagSymbolKind: String, Codable, Sendable {
    case phosphor
    case emoji
}

struct TagSymbol: Codable, Hashable, Sendable {
    static let fallbackEmoji = "#"

    var kind: TagSymbolKind
    var value: String

    var storageValue: String {
        "\(kind.rawValue):\(value)"
    }

    init(kind: TagSymbolKind, value: String) {
        self.kind = kind
        self.value = value
    }

    init?(storageValue: String?) {
        guard let storageValue, !storageValue.isEmpty else { return nil }
        let parts = storageValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let kind = TagSymbolKind(rawValue: parts[0]),
              !parts[1].isEmpty else {
            if storageValue.count <= 4 {
                self.kind = .emoji
                self.value = storageValue
                return
            }
            return nil
        }
        self.kind = kind
        self.value = parts[1]
    }

    static func normalizedStorageValue(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return TagSymbol(storageValue: value)?.storageValue
    }
}

enum PhosphorTagIcon: String, CaseIterable, Identifiable, Sendable {
    case briefcase
    case code
    case database
    case folder
    case wrench
    case key
    case paintBrush
    case image
    case palette
    case gridFour
    case magicWand
    case cursorClick
    case tag
    case stack
    case puzzlePiece
    case lightbulb
    case bookOpen
    case envelope
    case megaphone
    case chatCircle
    case musicNote
    case heart
    case mapPin
    case leaf
    case flame
    case moon
    case lock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paintBrush: "Paint"
        case .gridFour: "Grid"
        case .magicWand: "Magic"
        case .cursorClick: "Click"
        case .puzzlePiece: "Puzzle"
        case .bookOpen: "Book"
        case .chatCircle: "Chat"
        case .musicNote: "Music"
        case .mapPin: "Pin"
        default:
            rawValue.replacingOccurrences(
                of: #"([a-z])([A-Z])"#,
                with: "$1 $2",
                options: .regularExpression
            ).capitalized
        }
    }

    static let groups: [(title: String, icons: [PhosphorTagIcon])] = [
        ("Work", [.briefcase, .code, .database, .folder, .wrench, .key]),
        ("Design", [.paintBrush, .image, .palette, .gridFour, .magicWand]),
        ("Product", [.cursorClick, .tag, .stack, .puzzlePiece, .lightbulb]),
        ("Content", [.bookOpen, .envelope, .megaphone, .chatCircle, .musicNote]),
        ("Life", [.heart, .mapPin, .leaf, .flame, .moon, .lock])
    ]
}
