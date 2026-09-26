import AppKit
import FinderSync
import OSLog

private let logger = Logger(subsystem: "com.tharrmeehan.FinderLauncher", category: "FinderSync")

private func copyPaths(_ urls: [URL]?) {
    guard let urls, !urls.isEmpty, urls.allSatisfy(\.isFileURL) else {
        logger.error("Copy Path has no valid Finder targets")
        return
    }

    Task { @MainActor in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string) else {
            logger.error("Could not copy Finder paths")
            return
        }
        logger.info("Copied \(urls.count) Finder path(s) to the clipboard")
        handoffCopyFeedback()
    }
}

@MainActor
private func handoffCopyFeedback() {
    var components = URLComponents()
    components.scheme = "finderlauncher"
    components.host = "feedback"
    components.queryItems = [URLQueryItem(name: "action", value: "copied")]
    guard let requestURL = components.url else { return }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.open(requestURL, configuration: configuration) { _, error in
        if let error {
            logger.error("Could not hand off copy feedback: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private func selectedItemURLs() -> [URL]? {
    let controller = FIFinderSyncController.default()
    if let selectedURLs = controller.selectedItemURLs(), !selectedURLs.isEmpty {
        return selectedURLs
    }
    return controller.targetedURL().map { [$0] }
}

private func configuredBundleIdentifier(for menuItem: NSMenuItem) -> String? {
    let applications = SharedConfigurationStore.loadApplications() ?? LaunchApplication.defaults
    let index = menuItem.tag - 1
    guard applications.indices.contains(index) else {
        logger.error("Open With action has invalid menu tag: \(menuItem.tag)")
        return nil
    }
    return applications[index].bundleIdentifier
}

private func launch(_ urls: [URL]?, inBundleIdentifier bundleIdentifier: String) {
    guard let urls, !urls.isEmpty else {
        logger.error("Open With has no Finder target")
        return
    }

    Task { @MainActor in
        var components = URLComponents()
        components.scheme = "finderlauncher"
        components.host = "launch"
        components.queryItems = [URLQueryItem(name: "bundle", value: bundleIdentifier)] +
            urls.map { URLQueryItem(name: "target", value: $0.absoluteString) }

        guard let requestURL = components.url else {
            logger.error("Could not hand off Open With request to FinderLauncher")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(requestURL, configuration: configuration) { _, error in
            if let error {
                logger.error("Could not hand off Open With request to FinderLauncher: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.info("Handed Open With request to FinderLauncher for \(bundleIdentifier, privacy: .public)")
            }
        }
    }
}

@MainActor
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    nonisolated(unsafe) private let applicationIconCache = NSCache<NSString, NSImage>()

    nonisolated private func applicationIcon(for application: LaunchApplication) -> NSImage? {
        let cacheKey = application.bundleIdentifier as NSString
        if let cachedIcon = applicationIconCache.object(forKey: cacheKey) { return cachedIcon }

        let configuredURL: URL?
        if let url = application.applicationURL,
           url.isFileURL,
           Bundle(url: url)?.bundleIdentifier == application.bundleIdentifier {
            configuredURL = url
        } else {
            configuredURL = nil
        }
        let applicationURL = configuredURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier)
        guard let applicationURL else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: 16, height: 16)
        applicationIconCache.setObject(icon, forKey: cacheKey)
        return icon
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let applicationAction: Selector
        let copyPathAction: Selector
        let isContainerMenu: Bool

        switch menuKind {
        case .contextualMenuForItems:
            guard FinderTargetResolver.directory(
                for: controller.selectedItemURLs(),
                targetedURL: controller.targetedURL()
            ) != nil else { return nil }
            applicationAction = #selector(openSelectedItemsInApplication(_:))
            copyPathAction = #selector(copySelectedPaths(_:))
            isContainerMenu = false
        case .contextualMenuForContainer:
            guard FinderTargetResolver.directory(for: controller.targetedURL()) != nil else { return nil }
            applicationAction = #selector(openContainerInApplication(_:))
            copyPathAction = #selector(copyContainerPath(_:))
            isContainerMenu = true
        default:
            return nil
        }

        let menu = NSMenu(title: "FinderLauncher")
        let applications = SharedConfigurationStore.loadApplications() ?? LaunchApplication.defaults
        for (index, application) in applications.enumerated() {
            let item = NSMenuItem(title: "Open in \(application.displayName)", action: applicationAction, keyEquivalent: "")
            item.target = self
            item.tag = index + 1
            item.image = applicationIcon(for: application)
            menu.addItem(item)
        }

        let showsCopyPath = NSEvent.modifierFlags.contains(.option)
        if !applications.isEmpty && (isContainerMenu || showsCopyPath) {
            menu.addItem(.separator())
        }
        if isContainerMenu {
            let newTextFileItem = NSMenuItem(title: "New Text File", action: #selector(createTextFileInContainer(_:)), keyEquivalent: "")
            newTextFileItem.target = self
            newTextFileItem.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "New Text File")
            menu.addItem(newTextFileItem)
            if showsCopyPath { menu.addItem(.separator()) }
        }
        if showsCopyPath {
            let copyPathItem = NSMenuItem(title: "Copy Path", action: copyPathAction, keyEquivalent: "")
            copyPathItem.target = self
            copyPathItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy Path")
            menu.addItem(copyPathItem)
        }
        guard !menu.items.isEmpty else { return nil }
        return menu
    }

    @objc nonisolated private func openSelectedItemsInApplication(_ sender: NSMenuItem) {
        guard let bundleIdentifier = configuredBundleIdentifier(for: sender) else { return }
        launch(selectedItemURLs(), inBundleIdentifier: bundleIdentifier)
    }

    @objc nonisolated private func openContainerInApplication(_ sender: NSMenuItem) {
        guard let bundleIdentifier = configuredBundleIdentifier(for: sender) else { return }
        launch(FIFinderSyncController.default().targetedURL().map { [$0] }, inBundleIdentifier: bundleIdentifier)
    }

    @objc nonisolated private func copySelectedPaths(_ sender: NSMenuItem) {
        copyPaths(selectedItemURLs())
    }

    @objc nonisolated private func copyContainerPath(_ sender: NSMenuItem) {
        copyPaths(FIFinderSyncController.default().targetedURL().map { [$0] })
    }

    @objc nonisolated private func createTextFileInContainer(_ sender: NSMenuItem) {
        guard let directoryURL = FinderTargetResolver.directory(for: FIFinderSyncController.default().targetedURL()),
              let requestID = SharedConfigurationStore.saveTextFileRequest(for: directoryURL) else {
            logger.error("New Text File has no valid Finder folder")
            return
        }

        var components = URLComponents()
        components.scheme = "finderlauncher"
        components.host = "new-text-file"
        components.queryItems = [URLQueryItem(name: "request", value: requestID)]
        guard let requestURL = components.url else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(requestURL, configuration: configuration) { _, error in
            if let error {
                logger.error("Could not hand off New Text File request: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

}
