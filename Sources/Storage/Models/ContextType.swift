import Foundation
import GRDB

enum ContextType: String, Codable, DatabaseValueConvertible, CaseIterable {
    case website
    case music
    case design
    case file
    case generic

    var displayName: String {
        switch self {
        case .website: "Website"
        case .music: "Music"
        case .design: "Design"
        case .file: "File"
        case .generic: "Other"
        }
    }

    var iconName: String {
        switch self {
        case .website: "safari"
        case .music: "music.note"
        case .design: "paintpalette"
        case .file: "folder"
        case .generic: "square"
        }
    }
}
