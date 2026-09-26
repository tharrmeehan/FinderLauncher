import Foundation

struct LaunchApplication: Codable, Hashable, Identifiable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL?

    var id: String { bundleIdentifier }

    static let defaults = [
        LaunchApplication(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit", applicationURL: nil),
        LaunchApplication(bundleIdentifier: "com.microsoft.VSCode", displayName: "Visual Studio Code", applicationURL: nil),
        LaunchApplication(bundleIdentifier: "com.apple.dt.Xcode", displayName: "Xcode", applicationURL: nil)
    ]
}

enum SharedConfigurationStore {
    static let appGroupIdentifier = "GZ958LUB42.finderlauncher"
    private static let configurationKey = "configuration"
    private static let textFileRequestKeyPrefix = "newTextFileRequest."

    static func load() -> Data? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil else {
            return nil
        }
        return UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: configurationKey)
    }

    static func loadApplications() -> [LaunchApplication]? {
        guard let data = load() else { return nil }
        return try? JSONDecoder().decode([LaunchApplication].self, from: data)
    }

    static func saveApplications(_ applications: [LaunchApplication]) -> Bool {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil,
              let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(applications) else { return false }
        defaults.set(data, forKey: configurationKey)
        return defaults.data(forKey: configurationKey) == data
    }

    static func saveTextFileRequest(for directoryURL: URL) -> String? {
        guard directoryURL.isFileURL,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil,
              let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return nil }
        let requestID = UUID().uuidString
        defaults.set(directoryURL.absoluteString, forKey: textFileRequestKeyPrefix + requestID)
        return requestID
    }

    static func consumeTextFileRequest(_ requestID: String) -> URL? {
        guard UUID(uuidString: requestID) != nil,
              let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return nil }
        let key = textFileRequestKeyPrefix + requestID
        guard let rawURL = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let url = URL(string: rawURL), url.isFileURL else { return nil }
        return url
    }
}
