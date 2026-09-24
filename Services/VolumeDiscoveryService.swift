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
            .volumeUUIDStringKey,
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
            let persistentVolumeID = values.volumeUUIDString.flatMap { $0.isEmpty ? nil : $0 }
            let subtitle = persistentVolumeID == nil
                ? "Manual import only (no persistent volume ID)"
                : (isEjectable ? "Ejectable volume" : "Mounted volume")
            let sourceID = persistentVolumeID.map { "volume::\($0)" }
                ?? "volume::\(volumeURL.standardizedFileURL.path(percentEncoded: false))"

            return SourceDevice(
                id: sourceID,
                displayName: displayName,
                kind: .mountedVolume,
                rootURL: volumeURL,
                subtitle: subtitle,
                state: .ready,
                persistentVolumeID: persistentVolumeID
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
