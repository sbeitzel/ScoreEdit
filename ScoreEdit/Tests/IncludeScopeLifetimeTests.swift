import Foundation
import Testing

@testable import ScoreEdit

/// In-memory stand-in for the on-disk bookmark plist.
private final class StubBookmarkStore: SecurityScopedBookmarkStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var bookmarks: [String: Data]

    init(bookmarks: [String: Data] = [:]) {
        self.bookmarks = bookmarks
    }

    func bookmark(for url: URL) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return bookmarks[url.path]
    }

    func setBookmark(_ data: Data, for url: URL) {
        lock.lock()
        bookmarks[url.path] = data
        lock.unlock()
    }
}

/// Counts scope starts and stops so tests can assert the two balance. Bookmark
/// payloads are just the UTF-8 path, standing in for real security-scoped
/// bookmark data (which the test process cannot mint).
private final class SpyScopeAccessor: SecurityScopeAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var starts: [String: Int] = [:]
    private var stops: [String: Int] = [:]
    private var refreshes: [String] = []
    private let unresolvable: Set<String>
    private let reportsStale: Bool

    init(unresolvable: Set<String> = [], reportsStale: Bool = false) {
        self.unresolvable = unresolvable
        self.reportsStale = reportsStale
    }

    static func bookmark(for url: URL) -> Data {
        Data(url.standardizedFileURL.path.utf8)
    }

    func startAccess(bookmark: Data) -> (url: URL, isStale: Bool)? {
        guard let path = String(data: bookmark, encoding: .utf8),
              !unresolvable.contains(path) else { return nil }
        lock.lock()
        starts[path, default: 0] += 1
        lock.unlock()
        return (URL(fileURLWithPath: path), reportsStale)
    }

    func refreshedBookmark(for url: URL) -> Data? {
        lock.lock()
        refreshes.append(url.path)
        lock.unlock()
        return Self.bookmark(for: url)
    }

    func stopAccess(to url: URL) {
        lock.lock()
        stops[url.path, default: 0] += 1
        lock.unlock()
    }

    func startCount(_ url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return starts[url.standardizedFileURL.path] ?? 0
    }

    func stopCount(_ url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return stops[url.standardizedFileURL.path] ?? 0
    }

    var refreshedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return refreshes
    }

    /// The property the leak fix is really about: nothing started stays unstopped.
    var isBalanced: Bool {
        lock.lock()
        defer { lock.unlock() }
        return starts == stops
    }
}

private func makeResolver(
    holding urls: [URL],
    accessor: SpyScopeAccessor
) -> IncludeFileAccessResolver {
    let pairs = urls.map { ($0.standardizedFileURL.path, SpyScopeAccessor.bookmark(for: $0)) }
    return IncludeFileAccessResolver(
        bookmarkStore: StubBookmarkStore(bookmarks: Dictionary(uniqueKeysWithValues: pairs)),
        scopeAccessor: accessor
    )
}

private let fileA = URL(fileURLWithPath: "/tmp/scoreedit-tests/tune-a.abh")
private let fileB = URL(fileURLWithPath: "/tmp/scoreedit-tests/tune-b.abh")

/// Security-scoped resources are a bounded kernel resource, so every scope the
/// resolver starts has to be stopped when the window that owns it goes away (#23).
@Suite("IncludeFileAccessResolver persistent scopes")
struct IncludeScopeLifetimeTests {
    @Test("a fresh resolver holds nothing")
    func freshResolverHoldsNoScopes() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [], accessor: spy)
        #expect(resolver.activeScopePaths.isEmpty)
        #expect(spy.isBalanced)
    }

    @Test("beginning access holds one scope")
    func beginHoldsAScope() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [fileA], accessor: spy)

        #expect(resolver.beginPersistentAccess(to: fileA) != nil)
        #expect(resolver.activeScopePaths == [fileA.path])
        #expect(spy.startCount(fileA) == 1)
        #expect(spy.stopCount(fileA) == 0)
    }

    @Test("beginning access twice for one path starts a single scope")
    func repeatedBeginStartsOneScope() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [fileA], accessor: spy)

        resolver.beginPersistentAccess(to: fileA)
        resolver.beginPersistentAccess(to: fileA)
        resolver.beginPersistentAccess(to: fileA)
        #expect(spy.startCount(fileA) == 1)
        #expect(resolver.activeScopePaths == [fileA.path])

        // One begin, one stop — not three stops for one start.
        resolver.endAllPersistentAccess()
        #expect(spy.stopCount(fileA) == 1)
        #expect(spy.isBalanced)
    }

    @Test("no stored bookmark means no scope is started")
    func missingBookmarkStartsNothing() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [], accessor: spy)

        #expect(resolver.beginPersistentAccess(to: fileA) == nil)
        #expect(resolver.activeScopePaths.isEmpty)
        #expect(spy.startCount(fileA) == 0)
    }

    @Test("an unresolvable bookmark leaves nothing held")
    func unresolvableBookmarkHoldsNothing() {
        let spy = SpyScopeAccessor(unresolvable: [fileA.path])
        let resolver = makeResolver(holding: [fileA], accessor: spy)

        #expect(resolver.beginPersistentAccess(to: fileA) == nil)
        #expect(resolver.activeScopePaths.isEmpty)
        #expect(spy.isBalanced)
    }

    @Test("a stale bookmark is re-minted into the store")
    func staleBookmarkIsRefreshed() {
        let spy = SpyScopeAccessor(reportsStale: true)
        let resolver = makeResolver(holding: [fileA], accessor: spy)

        resolver.beginPersistentAccess(to: fileA)
        #expect(spy.refreshedPaths == [fileA.path])
        #expect(resolver.activeScopePaths == [fileA.path])
    }

    @Test("ending access the resolver never began is a no-op")
    func endingUnheldAccessIsANoOp() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [], accessor: spy)

        resolver.endPersistentAccess(to: fileA)
        resolver.endAllPersistentAccess()
        #expect(resolver.activeScopePaths.isEmpty)
        #expect(spy.stopCount(fileA) == 0)
    }

    @Test("endPersistentAccess releases just that path")
    func endReleasesOnePath() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [fileA, fileB], accessor: spy)
        resolver.beginPersistentAccess(to: fileA)
        resolver.beginPersistentAccess(to: fileB)
        #expect(resolver.activeScopePaths.count == 2)

        resolver.endPersistentAccess(to: fileA)
        #expect(resolver.activeScopePaths == [fileB.path])
        #expect(spy.stopCount(fileA) == 1)
        #expect(spy.stopCount(fileB) == 0)

        // Releasing the same path again must not double-stop or disturb the survivor.
        resolver.endPersistentAccess(to: fileA)
        #expect(spy.stopCount(fileA) == 1)
        #expect(resolver.activeScopePaths == [fileB.path])
    }

    @Test("endAllPersistentAccess drains every held scope")
    func endAllDrainsEverything() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [fileA, fileB], accessor: spy)
        resolver.beginPersistentAccess(to: fileA)
        resolver.beginPersistentAccess(to: fileB)

        resolver.endAllPersistentAccess()
        #expect(resolver.activeScopePaths.isEmpty)
        #expect(spy.isBalanced)

        // Idempotent: a second call must not stop anything again.
        resolver.endAllPersistentAccess()
        #expect(spy.stopCount(fileA) == 1)
        #expect(spy.stopCount(fileB) == 1)
    }

    @Test("a dropped resolver balances its scopes")
    func deinitBalancesScopes() {
        let spy = SpyScopeAccessor()
        var resolver: IncludeFileAccessResolver? = makeResolver(holding: [fileA, fileB], accessor: spy)
        resolver?.beginPersistentAccess(to: fileA)
        resolver?.beginPersistentAccess(to: fileB)
        #expect(spy.stopCount(fileA) == 0)

        // A window torn down without an explicit teardown must not leak.
        resolver = nil
        #expect(spy.isBalanced)
        #expect(spy.stopCount(fileA) == 1)
        #expect(spy.stopCount(fileB) == 1)
    }

    @Test("an explicit teardown leaves deinit nothing to double-stop")
    func explicitTeardownThenDeinitStopsOnce() {
        let spy = SpyScopeAccessor()
        var resolver: IncludeFileAccessResolver? = makeResolver(holding: [fileA], accessor: spy)
        resolver?.beginPersistentAccess(to: fileA)
        resolver?.endAllPersistentAccess()
        resolver = nil
        #expect(spy.stopCount(fileA) == 1)
    }

    @Test("access can be re-established after a full release")
    func accessCanBeReestablished() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [fileA], accessor: spy)

        resolver.beginPersistentAccess(to: fileA)
        resolver.endAllPersistentAccess()
        // A window that disappears and reappears must get its scope back.
        #expect(resolver.beginPersistentAccess(to: fileA) != nil)
        #expect(resolver.activeScopePaths == [fileA.path])
        #expect(spy.startCount(fileA) == 2)
    }

    @Test("an unstandardized URL releases the scope it began")
    func unstandardizedURLReleasesTheSameScope() {
        let spy = SpyScopeAccessor()
        let resolver = makeResolver(holding: [fileA], accessor: spy)
        resolver.beginPersistentAccess(to: fileA)

        // ContentView reconstructs URLs from stored paths when releasing includes
        // that left the document; the round trip must key to the same scope.
        let detoured = fileA
            .deletingLastPathComponent()
            .appendingPathComponent(".")
            .appendingPathComponent(fileA.lastPathComponent)
        resolver.endPersistentAccess(to: detoured)
        #expect(resolver.activeScopePaths.isEmpty)
        #expect(spy.isBalanced)
    }
}
