import Foundation
import Testing
@testable import ScoreEdit

@MainActor
struct IncludeFileWatcherTests {

    /// Waits up to `timeout` for the watcher to report a change.
    private func awaitChange(
        _ watcher: IncludeFileWatcher,
        timeout: Duration = .seconds(3),
        while work: () throws -> Void
    ) async rethrows -> Bool {
        var fired = false
        watcher.onChange = { fired = true }
        try work()
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if fired { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return fired
    }

    private func makeTempFile(_ contents: String = "Q:1/4=120\n") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("frag.abh")
        try contents.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    @Test func firesOnInPlaceWrite() async throws {
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let watcher = IncludeFileWatcher()
        watcher.setWatchedURLs([url])
        defer { watcher.cancelAll() }

        let fired = try await awaitChange(watcher) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("K:C\n".utf8))
            try handle.close()
        }
        #expect(fired)
    }

    @Test func firesOnAtomicReplace() async throws {
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let watcher = IncludeFileWatcher()
        watcher.setWatchedURLs([url])
        defer { watcher.cancelAll() }

        // How macOS document saves land: the file is replaced, not rewritten.
        let fired = try await awaitChange(watcher) {
            try "Q:1/4=90\n".write(to: url, atomically: true, encoding: .utf8)
        }
        #expect(fired)
    }

    @Test func rearmsAfterAtomicReplace() async throws {
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let watcher = IncludeFileWatcher()
        watcher.setWatchedURLs([url])
        defer { watcher.cancelAll() }

        _ = try await awaitChange(watcher) {
            try "Q:1/4=90\n".write(to: url, atomically: true, encoding: .utf8)
        }
        // Give the re-arm delay time to elapse, then change the new file.
        try await Task.sleep(for: .milliseconds(400))
        let firedAgain = try await awaitChange(watcher) {
            try "Q:1/4=60\n".write(to: url, atomically: true, encoding: .utf8)
        }
        #expect(firedAgain)
    }

    @Test func ignoresUnwatchedFiles() async throws {
        let watched = try makeTempFile()
        let other = try makeTempFile()
        defer {
            try? FileManager.default.removeItem(at: watched.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: other.deletingLastPathComponent())
        }
        let watcher = IncludeFileWatcher()
        watcher.setWatchedURLs([watched])
        defer { watcher.cancelAll() }

        let fired = try await awaitChange(watcher, timeout: .milliseconds(600)) {
            try "K:D\n".write(to: other, atomically: true, encoding: .utf8)
        }
        #expect(!fired)
    }

    @Test func stopsReportingAfterCancel() async throws {
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let watcher = IncludeFileWatcher()
        watcher.setWatchedURLs([url])
        watcher.cancelAll()

        let fired = try await awaitChange(watcher, timeout: .milliseconds(600)) {
            try "K:D\n".write(to: url, atomically: true, encoding: .utf8)
        }
        #expect(!fired)
    }
}
