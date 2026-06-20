import Foundation

struct UserPreferences {
    private enum Key {
        static let destinationPath = "lastDestinationPath"
        static let organizationMode = "destinationOrganizationMode"
        static let showHelperFiles = "showHelperFiles"
        static let automaticallyImportDetectedMedia = "automaticallyImportDetectedMedia"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func destinationURL() -> URL? {
        guard let path = userDefaults.string(forKey: Key.destinationPath), !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    func saveDestinationURL(_ url: URL?) {
        if let url {
            userDefaults.set(url.path(percentEncoded: false), forKey: Key.destinationPath)
        } else {
            userDefaults.removeObject(forKey: Key.destinationPath)
        }
    }

    func organizationMode() -> DestinationOrganizationMode {
        guard
            let rawValue = userDefaults.string(forKey: Key.organizationMode),
            let mode = DestinationOrganizationMode(rawValue: rawValue)
        else {
            return .flat
        }

        return mode
    }

    func saveOrganizationMode(_ mode: DestinationOrganizationMode) {
        userDefaults.set(mode.rawValue, forKey: Key.organizationMode)
    }

    func showHelperFiles() -> Bool {
        userDefaults.bool(forKey: Key.showHelperFiles)
    }

    func saveShowHelperFiles(_ showHelperFiles: Bool) {
        userDefaults.set(showHelperFiles, forKey: Key.showHelperFiles)
    }

    func automaticallyImportDetectedMedia() -> Bool {
        userDefaults.bool(forKey: Key.automaticallyImportDetectedMedia)
    }

    func saveAutomaticallyImportDetectedMedia(_ automaticallyImportDetectedMedia: Bool) {
        userDefaults.set(automaticallyImportDetectedMedia, forKey: Key.automaticallyImportDetectedMedia)
    }
}
