import Foundation

enum AppVersion {
    private static let developmentInfoPlistURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("scripts/Info.plist")

    static var current: String {
        resolve(
            bundleVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            developmentInfoPlistURL: developmentInfoPlistURL)
    }

    static func resolve(bundleVersion: String?, developmentInfoPlistURL: URL?) -> String {
        if let bundleVersion, !bundleVersion.isEmpty {
            return bundleVersion
        }
        guard let developmentInfoPlistURL,
              let data = try? Data(contentsOf: developmentInfoPlistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = info["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            return "-"
        }
        return version
    }
}
