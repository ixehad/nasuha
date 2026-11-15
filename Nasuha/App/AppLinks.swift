import Foundation
import NasuhaCore

/// Addresses the app links to.
enum AppLinks {
    static let repository = URL(string: "https://github.com/ixehad/nasuha")!
    static let issues = URL(string: "https://github.com/ixehad/nasuha/issues")!
    /// The privacy text as a web page (required by the App Store).
    static let privacyPage = URL(string: "https://github.com/ixehad/nasuha/blob/main/PRIVACY.md")!
    /// Address for "Report a mistake" and "Contact us". While it is empty, both open the issue page instead.
    static let contactEmail = ""

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static func mistakeReport(ayahKey: String? = nil, setID: String? = nil, contentVersion: String) -> URL? {
        MistakeReport.url(
            MistakeReport.Details(ayahKey: ayahKey, setID: setID, contentVersion: contentVersion, appVersion: appVersion),
            email: contactEmail, issuesURL: issues)
    }

    /// Where "Contact us" goes.
    static var contact: URL {
        contactEmail.isEmpty ? issues : (URL(string: "mailto:\(contactEmail)") ?? issues)
    }
}
