import Foundation
import XCTest

final class ReleasePackagingScriptTests: XCTestCase {
    func testSourceOnlyModeNormalizesTrailingNewlinesInReleaseMetadata() throws {
        let scriptPath = repositoryRoot.appendingPathComponent("package-app.sh").path
        let command = """
        export PACKAGE_APP_SOURCE_ONLY=1
        source "\(scriptPath)"
        printf '%s' "$(normalize_metadata_value $'PUBLIC_KEY\\n')"
        """

        let result = try runShell(command, workingDirectory: repositoryRoot.path)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout, "PUBLIC_KEY")
    }

    func testReleaseAppcastScriptClassifiesSemVerChannels() throws {
        let stable = try runShell(
            "python3 Scripts/release-appcast.py classify-version 1.2.3",
            workingDirectory: repositoryRoot.path
        )
        let beta = try runShell(
            "python3 Scripts/release-appcast.py classify-version 1.2.4-beta.3",
            workingDirectory: repositoryRoot.path
        )
        let rc = try runShell(
            "python3 Scripts/release-appcast.py classify-version 1.2.4-rc.1",
            workingDirectory: repositoryRoot.path
        )
        let invalid = try runShell(
            "python3 Scripts/release-appcast.py classify-version 1.2.4-hotfix",
            workingDirectory: repositoryRoot.path
        )

        XCTAssertEqual(stable.exitCode, 0, stable.stderr)
        XCTAssertEqual(stable.stdout, "prerelease=false\n")
        XCTAssertEqual(beta.exitCode, 0, beta.stderr)
        XCTAssertEqual(beta.stdout, "prerelease=true\n")
        XCTAssertEqual(rc.exitCode, 0, rc.stderr)
        XCTAssertEqual(rc.stdout, "prerelease=true\n")
        XCTAssertNotEqual(invalid.exitCode, 0)
        XCTAssertTrue(invalid.stderr.contains("Unsupported prerelease label"))
    }

    func testReleaseAppcastScriptRewritesUrlsWithActualTagsAndBetaChannel() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let appcast = tempDir.appendingPathComponent("appcast.xml")
        let assetTags = tempDir.appendingPathComponent("asset-tags.tsv")

        try """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <title>Stable</title>
              <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
              <sparkle:channel>beta</sparkle:channel>
              <enclosure url="https://github.com/example/MenuStatus/releases/download/__placeholder__/MenuStatus-1.2.3.dmg" />
            </item>
            <item>
              <title>Beta</title>
              <sparkle:shortVersionString>1.2.4-beta.3</sparkle:shortVersionString>
              <enclosure url="https://github.com/example/MenuStatus/releases/download/__placeholder__/MenuStatus-1.2.4-beta.3.dmg" />
            </item>
          </channel>
        </rss>
        """.write(to: appcast, atomically: true, encoding: .utf8)
        try """
        MenuStatus-1.2.3.dmg	vstable-actual
        MenuStatus-1.2.4-beta.3.dmg	v1.2.4-beta.3
        """.write(to: assetTags, atomically: true, encoding: .utf8)

        let result = try runShell(
            "python3 Scripts/release-appcast.py postprocess --appcast \(appcast.path) --repo example/MenuStatus --asset-tags \(assetTags.path)",
            workingDirectory: repositoryRoot.path
        )
        let output = try String(contentsOf: appcast, encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(output.contains("releases/download/vstable-actual/MenuStatus-1.2.3.dmg"))
        XCTAssertTrue(output.contains("releases/download/v1.2.4-beta.3/MenuStatus-1.2.4-beta.3.dmg"))
        XCTAssertFalse(output.contains("__placeholder__"))
        XCTAssertEqual(output.components(separatedBy: "<sparkle:channel>beta</sparkle:channel>").count - 1, 1)
    }

    func testReleaseAppcastScriptFailsWhenAssetTagMappingIsMissing() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let appcast = tempDir.appendingPathComponent("appcast.xml")
        let assetTags = tempDir.appendingPathComponent("asset-tags.tsv")

        try minimalAppcastXML(filename: "MenuStatus-1.2.3.dmg", version: "1.2.3")
            .write(to: appcast, atomically: true, encoding: .utf8)
        try "".write(to: assetTags, atomically: true, encoding: .utf8)

        let result = try runShell(
            "python3 Scripts/release-appcast.py postprocess --appcast \(appcast.path) --repo example/MenuStatus --asset-tags \(assetTags.path)",
            workingDirectory: repositoryRoot.path
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("No release tag mapping found"))
    }

    func testReleaseAppcastScriptFailsWhenDeltaEntriesRemain() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let appcast = tempDir.appendingPathComponent("appcast.xml")
        let assetTags = tempDir.appendingPathComponent("asset-tags.tsv")

        try """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
              <enclosure url="https://github.com/example/MenuStatus/releases/download/__placeholder__/MenuStatus-1.2.3.dmg" />
              <sparkle:deltas>
                <enclosure url="https://github.com/example/MenuStatus/releases/download/__placeholder__/MenuStatus-1.2.3.delta" />
              </sparkle:deltas>
            </item>
          </channel>
        </rss>
        """.write(to: appcast, atomically: true, encoding: .utf8)
        try "MenuStatus-1.2.3.dmg\tv1.2.3\n".write(to: assetTags, atomically: true, encoding: .utf8)

        let result = try runShell(
            "python3 Scripts/release-appcast.py postprocess --appcast \(appcast.path) --repo example/MenuStatus --asset-tags \(assetTags.path)",
            workingDirectory: repositoryRoot.path
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("delta"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuStatusReleaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func minimalAppcastXML(filename: String, version: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
              <enclosure url="https://github.com/example/MenuStatus/releases/download/__placeholder__/\(filename)" />
            </item>
          </channel>
        </rss>
        """
    }

    private func runShell(_ command: String, workingDirectory: String) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }
}

private struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
