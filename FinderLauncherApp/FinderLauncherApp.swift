import AppKit
import Darwin
import FinderSync
import OSLog
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.tharrmeehan.FinderLauncher", category: "ApplicationLauncher")

@MainActor
private final class FinderLauncherApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true else { return }
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            logger.error("Could not enable launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handleLaunchRequest)
    }
}

private struct FinderFeedbackToastView: View {
    let message: String
    let symbol: String
    @State private var visible = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: Capsule())
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.86)
        .offset(y: visible ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                visible = true
            }
        }
    }
}

@MainActor
private enum FinderFeedbackToast {
    private static let panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        return panel
    }()
    private static var dismissal: Task<Void, Never>?
    private static var revision = 0

    static func show(_ message: String, symbol: String) {
        panel.contentView = NSHostingView(
            rootView: FinderFeedbackToastView(message: message, symbol: symbol)
                .frame(width: 320, height: 56)
        )
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 340, y: frame.minY + 20))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        revision += 1
        let currentRevision = revision
        dismissal?.cancel()
        dismissal = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.8))
            } catch {
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    guard currentRevision == revision else { return }
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                }
            })
        }
    }
}

@main
struct FinderLauncherApp: App {
    @NSApplicationDelegateAdaptor(FinderLauncherApplicationDelegate.self) private var applicationDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var applications = SharedConfigurationStore.loadApplications() ?? LaunchApplication.defaults
    @State private var showSaveError = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @State private var launchAtLoginStatus = SMAppService.mainApp.status
    @State private var launchAtLoginError: String?

    var body: some Scene {
        Window("FinderLauncher", id: "main") {
            VStack(alignment: .leading, spacing: 14) {
                Label("FinderLauncher", systemImage: "finder")
                    .font(.title2.weight(.semibold))

                Text("Enable the Finder extension to add FinderLauncher actions to Finder menus.")
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Open With applications")
                        .font(.headline)
                    Spacer()
                    Button("Add Application…", systemImage: "plus", action: addApplications)
                }
                Text("Drag applications to set their order in Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(applications) { application in
                        HStack {
                            Image(systemName: "app")
                                .foregroundStyle(.secondary)
                            Text(application.displayName)
                            Spacer()
                            Button(role: .destructive) {
                                saveApplications(applications.filter { $0.id != application.id })
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(application.displayName)")
                            .accessibilityLabel("Remove \(application.displayName)")
                        }
                    }
                    .onMove(perform: moveApplications)
                }
                .frame(minHeight: 140)

                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)

                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: setLaunchAtLogin
                ))
                Text(launchAtLoginMessage)
                    .font(.caption)
                    .foregroundStyle(launchAtLoginError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                if launchAtLoginStatus == .requiresApproval {
                    Button("Open Login Items Settings") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }

                Button("Open Finder Extensions Settings") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            }
            .padding(24)
            .frame(minWidth: 440, minHeight: 460, alignment: .leading)
            .onAppear {
                if SharedConfigurationStore.loadApplications() == nil {
                    saveApplications(applications)
                }
                refreshLaunchAtLogin()
            }
            .alert("Couldn't Save Applications", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("FinderLauncher couldn't access its shared App Group. Check that both targets are signed with the same team.")
            }
        }
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            Button("Open FinderLauncher") {
                openSettingsWindow()
            }
            Divider()
            Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
            Divider()
            Button("Quit FinderLauncher") {
                NSApp.terminate(nil)
            }
        } label: {
            Label("FinderLauncher", systemImage: "finder")
        }
        .menuBarExtraStyle(.menu)
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private var launchAtLoginMessage: String {
        if let launchAtLoginError { return launchAtLoginError }
        switch launchAtLoginStatus {
        case .enabled:
            return "FinderLauncher will open when you log in."
        case .requiresApproval:
            return "Allow FinderLauncher in System Settings to finish enabling it."
        case .notRegistered:
            return "FinderLauncher won't open automatically."
        case .notFound:
            return "macOS couldn't find FinderLauncher."
        @unknown default:
            return "Login setting status is unavailable."
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLoginStatus = SMAppService.mainApp.status
        if launchAtLogin && launchAtLoginStatus == .notRegistered {
            setLaunchAtLogin(true)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            launchAtLoginStatus = service.status
            launchAtLogin = service.status != .notRegistered
            launchAtLoginError = nil
        } catch {
            launchAtLoginStatus = service.status
            launchAtLoginError = error.localizedDescription
            launchAtLogin = service.status != .notRegistered
        }
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.title = "Choose Applications"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        var updated = applications
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else { continue }
            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            let application = LaunchApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                applicationURL: url.standardizedFileURL
            )
            if let index = updated.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
                updated[index] = application
            } else {
                updated.append(application)
            }
        }
        saveApplications(updated)
    }

    private func moveApplications(from source: IndexSet, to destination: Int) {
        var updated = applications
        updated.move(fromOffsets: source, toOffset: destination)
        saveApplications(updated)
    }

    private func saveApplications(_ updated: [LaunchApplication]) {
        guard SharedConfigurationStore.saveApplications(updated) else {
            showSaveError = true
            return
        }
        applications = updated
    }

}

@MainActor
private func handleLaunchRequest(_ url: URL) {
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard url.scheme == "finderlauncher" else {
        logger.error("FinderLauncher received an invalid request")
        return
    }
    if url.host == "feedback" {
        let actionItems = queryItems.filter { $0.name == "action" }
        guard actionItems.count == 1, actionItems.first?.value == "copied" else {
            logger.error("FinderLauncher received an invalid feedback request")
            return
        }
        FinderFeedbackToast.show("Path copied", symbol: "doc.on.doc")
        return
    }
    if url.host == "new-text-file" {
        let requests = queryItems.filter { $0.name == "request" }
        guard requests.count == 1,
              let requestID = requests.first?.value,
              let directoryURL = SharedConfigurationStore.consumeTextFileRequest(requestID) else {
            logger.error("FinderLauncher received an invalid New Text File request")
            return
        }
        createTextFile(in: directoryURL)
        return
    }

    let bundleItems = queryItems.filter { $0.name == "bundle" }
    let rawTargets = queryItems.filter { $0.name == "target" }.compactMap(\.value)
    guard url.host == "launch",
          bundleItems.count == 1,
          let bundleIdentifier = bundleItems.first?.value,
          (SharedConfigurationStore.loadApplications() ?? LaunchApplication.defaults).contains(where: { $0.bundleIdentifier == bundleIdentifier }),
          !rawTargets.isEmpty else {
        logger.error("FinderLauncher received an invalid launch request")
        return
    }
    let targetURLs = rawTargets.compactMap(URL.init(string:))
    guard targetURLs.count == rawTargets.count, targetURLs.allSatisfy(\.isFileURL) else {
        logger.error("FinderLauncher received invalid target URLs")
        return
    }

    let application = (SharedConfigurationStore.loadApplications() ?? LaunchApplication.defaults)
        .first { $0.bundleIdentifier == bundleIdentifier }
    Task { @MainActor in
        let configuredURL: URL? = application?.applicationURL.flatMap { url -> URL? in
            guard url.isFileURL, Bundle(url: url)?.bundleIdentifier == bundleIdentifier else { return nil }
            return url
        }
        guard let applicationURL = configuredURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            FinderFeedbackToast.show("Application not installed", symbol: "exclamationmark.triangle")
            logger.error("Open With application is not installed: \(bundleIdentifier, privacy: .public)")
            return
        }

        do {
            try await ApplicationLauncher.open(targetURLs, in: applicationURL)
            logger.info("Opened Finder target in \(bundleIdentifier, privacy: .public)")
        } catch {
            FinderFeedbackToast.show("Couldn't open application", symbol: "exclamationmark.triangle")
            logger.error("Could not open Finder target in \(bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
private func createTextFile(in directoryURL: URL) {
    guard directoryURL.isFileURL,
          (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
        logger.error("New Text File target is not a directory")
        FinderFeedbackToast.show("Couldn't create text file", symbol: "exclamationmark.triangle")
        return
    }

    do {
        let fileURL = try createUniqueTextFile(in: directoryURL)
        guard NSWorkspace.shared.open(fileURL) else {
            logger.error("Created text file but could not open it")
            FinderFeedbackToast.show("Created \(fileURL.lastPathComponent)", symbol: "doc.badge.plus")
            return
        }
        FinderFeedbackToast.show("Created \(fileURL.lastPathComponent)", symbol: "doc.badge.plus")
    } catch {
        logger.error("Couldn't create text file: \(error.localizedDescription, privacy: .public)")
        FinderFeedbackToast.show("Couldn't create text file", symbol: "exclamationmark.triangle")
    }
}

private func createUniqueTextFile(in directoryURL: URL) throws -> URL {
    var index = 1
    while true {
        let name = index == 1 ? "New Text File.txt" : "New Text File \(index).txt"
        let fileURL = directoryURL.appendingPathComponent(name)
        let descriptor = Darwin.open(fileURL.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o666))
        if descriptor >= 0 {
            guard Darwin.close(descriptor) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return fileURL
        }
        let errorCode = errno
        guard errorCode == EEXIST else {
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        index += 1
    }
}
