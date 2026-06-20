import Foundation

struct DirectoryFilter {
    private let ignoredDirectoryNames: Set<String> = [
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
    ]

    func shouldSkipDirectory(named name: String) -> Bool {
        ignoredDirectoryNames.contains(name)
    }
}
