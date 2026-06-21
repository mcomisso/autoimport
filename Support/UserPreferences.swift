import Foundation

struct UserPreferences {
    private enum Key {
        static let destinationPath = "lastDestinationPath"
        static let organizationMode = "destinationOrganizationMode"
        static let showHelperFiles = "showHelperFiles"
        static let automaticallyImportDetectedMedia = "automaticallyImportDetectedMedia"
    }

    private enum Default {
        static let organizationMode = DestinationOrganizationMode.flat
        static let showHelperFiles = false
        static let automaticallyImportDetectedMedia = false
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
            return Default.organizationMode
        }

        return mode
    }

    func saveOrganizationMode(_ mode: DestinationOrganizationMode) {
        userDefaults.set(mode.rawValue, forKey: Key.organizationMode)
    }

    func showHelperFiles() -> Bool {
        bool(forKey: Key.showHelperFiles, defaultValue: Default.showHelperFiles)
    }

    func saveShowHelperFiles(_ showHelperFiles: Bool) {
        userDefaults.set(showHelperFiles, forKey: Key.showHelperFiles)
    }

    func automaticallyImportDetectedMedia() -> Bool {
        bool(
            forKey: Key.automaticallyImportDetectedMedia,
            defaultValue: Default.automaticallyImportDetectedMedia
        )
    }

    func saveAutomaticallyImportDetectedMedia(_ automaticallyImportDetectedMedia: Bool) {
        userDefaults.set(automaticallyImportDetectedMedia, forKey: Key.automaticallyImportDetectedMedia)
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return userDefaults.bool(forKey: key)
    }
}
