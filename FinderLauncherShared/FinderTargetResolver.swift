import Foundation

enum FinderTargetResolver {
    static func directory(for itemURL: URL?) -> URL? {
        guard let itemURL, itemURL.isFileURL else { return nil }

        let isDirectory = itemURL.hasDirectoryPath
            || (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

        return isDirectory ? itemURL : itemURL.deletingLastPathComponent()
    }

    static func directory(for selectedURLs: [URL]?, targetedURL: URL?) -> URL? {
        if let selectedURL = selectedURLs?.first {
            return directory(for: selectedURL) ?? directory(for: targetedURL)
        }
        return directory(for: targetedURL)
    }
}
