import AppKit

@MainActor
enum ApplicationLauncher {
    static func open(_ urls: [URL], in applicationURL: URL) async throws {
        try await NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
