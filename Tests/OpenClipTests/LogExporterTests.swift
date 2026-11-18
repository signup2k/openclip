// LogExporterTests.swift
// OpenClipTests
//
// Tests for log exporting, archiving, and Finder discovery.

import XCTest
@testable import Core
@testable import OpenClip

final class LogExporterTests: XCTestCase {
    private var tempDirectory: URL!
    private var previousSharedSink: RotatingFileLogSink?

    override func setUp() async throws {
        try await super.setUp()
        let sink = await MainActor.run {
            TestIsolation.reset()
            return RotatingFileLogSink.shared
        }
        previousSharedSink = sink
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClipLogExporterTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        let prev = previousSharedSink
        await MainActor.run {
            RotatingFileLogSink.shared = prev
        }
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testExportLogsCreatesZipArchiveWithLogFiles() async throws {
        let file1 = tempDirectory.appendingPathComponent("openclip.log")
        let file2 = tempDirectory.appendingPathComponent("openclip.1.log")
        let file3 = tempDirectory.appendingPathComponent("openclip.2.log")

        try "Log file 1 content".write(to: file1, atomically: true, encoding: .utf8)
        try "Log file 2 content".write(to: file2, atomically: true, encoding: .utf8)
        try "Log file 3 content".write(to: file3, atomically: true, encoding: .utf8)

        let testDate = Date(timeIntervalSince1970: 1718000000)
        let archiveURL = try await LogExporter.exportLogs(from: tempDirectory, date: testDate)

        defer {
            try? FileManager.default.removeItem(at: archiveURL)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertTrue(archiveURL.lastPathComponent.hasPrefix("OpenClip-Logs-"))
        XCTAssertTrue(archiveURL.lastPathComponent.hasSuffix(".zip"))

        // Verify zip contents using unzip -l
        let unzipOutput = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-l", archiveURL.path]
        ))

        XCTAssertTrue(unzipOutput.stdout.contains("openclip.log"))
        XCTAssertTrue(unzipOutput.stdout.contains("openclip.1.log"))
        XCTAssertTrue(unzipOutput.stdout.contains("openclip.2.log"))
    }
}
