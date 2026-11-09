import Foundation

/// Links into the app: `nasuha://ayah/{ayahSetId}` and `nasuha://allread`.
public enum DeepLink: Equatable, Sendable {
    case ayah(setID: String)
    case allRead

    public static let scheme = "nasuha"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        switch host {
        case "ayah":
            let id = url.pathComponents.filter { $0 != "/" }.first ?? ""
            guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
            self = .ayah(setID: id)
        case "allread":
            self = .allRead
        default:
            return nil
        }
    }

    /// The link for a notification, from its user info.
    public init?(userInfo: [AnyHashable: Any]) {
        switch userInfo[ReminderUserInfo.kind] as? String {
        case "ayah":
            guard let id = userInfo[ReminderUserInfo.ayahSetID] as? String else { return nil }
            self = .ayah(setID: id)
        case "allRead":
            self = .allRead
        default:
            return nil
        }
    }

    public var url: URL {
        switch self {
        case let .ayah(id): URL(string: "\(Self.scheme)://ayah/\(id)")!
        case .allRead: URL(string: "\(Self.scheme)://allread")!
        }
    }
}
