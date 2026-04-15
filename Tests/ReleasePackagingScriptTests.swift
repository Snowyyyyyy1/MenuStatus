import Foundation
import XCTest

final class ReleasePackagingScriptTests: XCTestCase {
    func testSourceOnlyModeNormalizesTrailingNewlinesInReleaseMetadata() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
