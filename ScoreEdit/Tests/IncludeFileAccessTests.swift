import Foundation
import Testing
@testable import ScoreEdit

private final class FakeBookmarkStore: SecurityScopedBookmarkStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func bookmark(for url: URL) -> Data? { storage[url.path] }
    func setBookmark(_ data: Data, for url: URL) { storage[url.path] = data }
}

struct SecurityScopedBookmarkStoreTests {

    @Test func bookmarkPersistsAcrossFreshStoreInstances() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let plistURL = dir.appendingPathComponent("bookmarks.plist")
        let targetFile = dir.appendingPathComponent("target.txt")
        try "hello".write(to: targetFile, atomically: true, encoding: .utf8)
        let bookmark = try targetFile.bookmarkData()

        let first = SecurityScopedBookmarkStore(storeURL: plistURL)
        first.setBookmark(bookmark, for: targetFile)

        let second = SecurityScopedBookmarkStore(storeURL: plistURL)
        #expect(second.bookmark(for: targetFile) == bookmark)
    }

    @Test func unknownURLReturnsNil() {
        let store = SecurityScopedBookmarkStore(storeURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).plist"))
        #expect(store.bookmark(for: URL(fileURLWithPath: "/no/such/file")) == nil)
    }
}

struct IncludeFileAccessResolverTests {

    @Test func resolveReadsDirectlyWhenAlreadyAccessibleAndNoBookmarkStored() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("visible.abh")
        try "C:Some Composer\n".write(to: file, atomically: true, encoding: .utf8)

        let resolver = IncludeFileAccessResolver(bookmarkStore: FakeBookmarkStore())
        let data = try resolver.resolve(file)

        #expect(String(data: data, encoding: .utf8) == "C:Some Composer\n")
        #expect(resolver.pendingURLs.isEmpty)
    }

    @Test func resolveThrowsAndMarksPendingWhenFileIsInaccessible() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).abh")
        let resolver = IncludeFileAccessResolver(bookmarkStore: FakeBookmarkStore())

        #expect(throws: IncludeAccessError.self) {
            try resolver.resolve(missing)
        }
        #expect(resolver.pendingURLs.contains(missing.standardizedFileURL))
    }

    @Test func resolveUsesStoredBookmarkBeforeFallingBackToDirectRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("bookmarked.abh")
        try "T:Subtitle\n".write(to: file, atomically: true, encoding: .utf8)

        let store = FakeBookmarkStore()
        store.setBookmark(try file.bookmarkData(), for: file.standardizedFileURL)

        let resolver = IncludeFileAccessResolver(bookmarkStore: store)
        let data = try resolver.resolve(file)

        #expect(String(data: data, encoding: .utf8) == "T:Subtitle\n")
        #expect(resolver.pendingURLs.isEmpty)
    }

    @Test func repeatedFailuresKeepURLMarkedPendingOnlyOnce() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).abh")
        let resolver = IncludeFileAccessResolver(bookmarkStore: FakeBookmarkStore())

        _ = try? resolver.resolve(missing)
        _ = try? resolver.resolve(missing)

        #expect(resolver.pendingURLs == [missing.standardizedFileURL])
    }

    /// The partially-typed include target of an earlier keystroke must not keep
    /// an access banner alive once the directive names something else (#25).
    @Test func renderPassDropsPendingURLsTheNewPassNoLongerAsksFor() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let partial = dir.appendingPathComponent("comm")
        let complete = dir.appendingPathComponent("common.abh")
        try "K:D\n".write(to: complete, atomically: true, encoding: .utf8)

        let resolver = IncludeFileAccessResolver(bookmarkStore: FakeBookmarkStore())

        let firstPass = resolver.beginRenderPass()
        _ = try? resolver.resolve(partial, in: firstPass)
        #expect(resolver.pendingURLs == [partial.standardizedFileURL])

        let secondPass = resolver.beginRenderPass()
        _ = try resolver.resolve(complete, in: secondPass)

        #expect(resolver.pendingURLs.isEmpty)
    }

    /// A superseded render can still be inside CeolKit when the next pass opens;
    /// its late failure must not raise a banner for text that is already gone.
    @Test func supersededRenderPassCannotMarkPendingForTheNewPass() {
        let stale = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).abh")
        let resolver = IncludeFileAccessResolver(bookmarkStore: FakeBookmarkStore())

        let firstPass = resolver.beginRenderPass()
        _ = resolver.beginRenderPass()
        _ = try? resolver.resolve(stale, in: firstPass)

        #expect(resolver.pendingURLs.isEmpty)
    }

    /// The pending set belongs to the newest pass, so a still-unreadable include
    /// keeps its banner across re-renders.
    @Test func pendingURLSurvivesARenderPassThatStillCannotReadIt() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).abh")
        let resolver = IncludeFileAccessResolver(bookmarkStore: FakeBookmarkStore())

        let firstPass = resolver.beginRenderPass()
        _ = try? resolver.resolve(missing, in: firstPass)

        let secondPass = resolver.beginRenderPass()
        _ = try? resolver.resolve(missing, in: secondPass)

        #expect(resolver.pendingURLs == [missing.standardizedFileURL])
    }
}
