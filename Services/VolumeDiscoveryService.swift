import Foundation

struct VolumeDiscoveryService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func discover() -> [SourceDevice] {
        let resourceKeys: [URLResourceKey] = [
            .isVolumeKey,
            .nameKey,
            .volumeLocalizedNameKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
        ]

        guard let mountedURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        return mountedURLs.compactMap { volumeURL in
            guard let values = try? volumeURL.resourceValues(forKeys: Set(resourceKeys)) else {
                return nil
            }

            let isInternal = values.volumeIsInternal ?? false
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false

            guard isRemovable || isEjectable || !isInternal else {
                return nil
            }

            let displayName = values.volumeLocalizedName
                ?? values.name
                ?? volumeURL.lastPathComponent
            let subtitle = isEjectable ? "Ejectable volume" : "Mounted volume"

            return SourceDevice(
                id: "volume::\(volumeURL.standardizedFileURL.path(percentEncoded: false))",
                displayName: displayName,
                kind: .mountedVolume,
                rootURL: volumeURL,
                subtitle: subtitle,
                state: .ready
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
