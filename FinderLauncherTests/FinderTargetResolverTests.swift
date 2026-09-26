import Foundation
import XCTest

final class FinderTargetResolverTests: XCTestCase {
    func testSelectedFolderResolvesToItself() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertEqual(FinderTargetResolver.directory(for: folder), folder)
    }

    func testSelectedFileResolvesToParentDirectory() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sample.txt")
        try Data().write(to: file)

        XCTAssertEqual(FinderTargetResolver.directory(for: file), folder)
    }

    func testBackgroundUsesTargetedDirectory() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertEqual(FinderTargetResolver.directory(for: nil, targetedURL: folder), folder)
    }

    func testLaunchRequestPreservesPathsLiterally() throws {
        let paths = ["My Project", "john's project", "$(touch hacked)", "hello;rm", "äöü", "日本語"]
        let request = ApplicationLaunchRequest(
            id: UUID(),
            bundleIdentifier: "com.apple.TextEdit",
            targetURLs: paths.map { URL(fileURLWithPath: "/tmp/\($0)") }
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ApplicationLaunchRequest.self, from: data)
        XCTAssertEqual(decoded.targetURLs, request.targetURLs)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
