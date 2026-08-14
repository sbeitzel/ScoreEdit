import AppKit
import Foundation

enum IncludeAccessError: Error, LocalizedError {
    case notYetGranted(URL)

    var errorDescription: String? {
        switch self {
        case .notYetGranted(let url):
            return "ScoreEdit needs permission to read \"\(url.lastPathComponent)\""
        }
    }
}

protocol SecurityScopedBookmarkStoring: Sendable {
    func bookmark(for url: URL) -> Data?
    func setBookmark(_ data: Data, for url: URL)
}

final class SecurityScopedBookmarkStore: SecurityScopedBookmarkStoring, @unchecked Sendable {
    private let storeURL: URL
    private let lock = NSLock()
    private var cache: [String: Data]

    init(storeURL: URL? = nil) {
        let url = storeURL ?? Self.defaultStoreURL()
        self.storeURL = url
        self.cache = Self.load(from: url)
    }

    func bookmark(for url: URL) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return cache[url.path]
    }

    func setBookmark(_ data: Data, for url: URL) {
        lock.lock()
        cache[url.path] = data
        let snapshot = cache
        lock.unlock()
        Self.save(snapshot, to: storeURL)
    }

    private static func defaultStoreURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("ScoreEdit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("file-bookmarks.plist")
    }

    private static func load(from url: URL) -> [String: Data] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Data]
        else { return [:] }
        return plist
    }

    private static func save(_ dict: [String: Data], to url: URL) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Resolving a security-scoped bookmark and holding its scope, behind a seam so
/// tests can verify that every start is balanced by a stop (#23). Minting a real
/// security-scoped bookmark needs sandbox entitlements the test process does not
/// have, so the live behaviour is not directly testable.
protocol SecurityScopeAccessing: Sendable {
    /// Resolves `bookmark` and starts access to it. Returns the resolved URL and
    /// whether the bookmark needs re-minting, or nil when it is unusable.
    func startAccess(bookmark: Data) -> (url: URL, isStale: Bool)?
    func refreshedBookmark(for url: URL) -> Data?
    func stopAccess(to url: URL)
}

struct SecurityScopeAccessor: SecurityScopeAccessing {
    func startAccess(bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), resolved.startAccessingSecurityScopedResource() else { return nil }
        return (resolved, isStale)
    }

    func refreshedBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope)
    }

    func stopAccess(to url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

/// Identifies a single render pass, so the set of files still awaiting access is
/// scoped to the text that pass rendered rather than accumulating across
/// keystrokes (#25).
struct IncludeRenderPass: Sendable, Equatable {
    fileprivate let id: Int
}

/// Supplies CeolKit's `fileResolver` for `I:abc-include` targets, working within
/// App Sandbox by consulting/minting security-scoped bookmarks. Reading (`resolve`)
/// runs off the main thread from the render pipeline; granting access (`grantAccess`)
/// must run on the main thread because it presents `NSOpenPanel`.
final class IncludeFileAccessResolver: @unchecked Sendable {
    private let bookmarkStore: SecurityScopedBookmarkStoring
    private let scopeAccessor: SecurityScopeAccessing
    private let lock = NSLock()
    private var pending: Set<URL> = []
    private var currentPass = IncludeRenderPass(id: 0)
    private var activeScopes: [String: URL] = [:]

    init(
        bookmarkStore: SecurityScopedBookmarkStoring = SecurityScopedBookmarkStore(),
        scopeAccessor: SecurityScopeAccessing = SecurityScopeAccessor()
    ) {
        self.bookmarkStore = bookmarkStore
        self.scopeAccessor = scopeAccessor
    }

    /// Every scope this resolver is currently holding, by standardized path.
    var activeScopePaths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(activeScopes.keys)
    }

    deinit {
        // Backstop: a resolver dropped without an explicit teardown must still
        // balance its scopes (#23).
        endAllPersistentAccess()
    }

    var pendingURLs: Set<URL> {
        lock.lock()
        defer { lock.unlock() }
        return pending
    }

    /// Opens a new render pass, discarding what earlier passes recorded as
    /// pending. A partially-typed include target ("comm" on the way to
    /// "common.abc") is only pending for the pass that saw it, so the access
    /// banner follows the document instead of accumulating a row per keystroke
    /// (#25). Renders of superseded text keep their own token, and their
    /// bookkeeping is ignored once a newer pass has opened.
    func beginRenderPass() -> IncludeRenderPass {
        lock.lock()
        defer { lock.unlock() }
        currentPass = IncludeRenderPass(id: currentPass.id + 1)
        pending.removeAll()
        return currentPass
    }

    /// Reads `url` on behalf of the newest render pass. Prefer
    /// `resolve(_:in:)` from a render, which cannot leave stale pending state
    /// behind when the render it belongs to is superseded.
    func resolve(_ url: URL) throws -> Data {
        lock.lock()
        let pass = currentPass
        lock.unlock()
        return try resolve(url, in: pass)
    }

    func resolve(_ url: URL, in pass: IncludeRenderPass) throws -> Data {
        let standardized = url.standardizedFileURL

        if let bookmark = bookmarkStore.bookmark(for: standardized) {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let didStart = resolved.startAccessingSecurityScopedResource()
                defer { if didStart { resolved.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: resolved) {
                    if isStale, let refreshed = try? resolved.bookmarkData(options: .withSecurityScope) {
                        bookmarkStore.setBookmark(refreshed, for: standardized)
                    }
                    clearPending(standardized, in: pass)
                    return data
                }
            }
        }

        // Already-permitted files (e.g. within a directory the user granted via
        // NSOpenPanel for the main document) can be read directly without a bookmark.
        if let data = try? Data(contentsOf: standardized) {
            clearPending(standardized, in: pass)
            return data
        }

        markPending(standardized, in: pass)
        throw IncludeAccessError.notYetGranted(standardized)
    }

    /// Resolves the stored bookmark for `url` and starts security-scoped access,
    /// keeping it active until `endPersistentAccess(to:)` or
    /// `endAllPersistentAccess()` (idempotent per path). Needed so programmatic
    /// document opening, saves from an include-file window, and the include file
    /// watcher can all touch the file (#20, #21).
    ///
    /// The scope belongs to the window that opened it, not to the process: the
    /// kernel tracks a bounded number of security-scoped resources, and leaking
    /// them makes later `startAccessingSecurityScopedResource()` calls fail (#23).
    ///
    /// Returns the bookmark-resolved URL, or nil when no usable bookmark exists.
    @discardableResult
    func beginPersistentAccess(to url: URL) -> URL? {
        let standardized = url.standardizedFileURL

        lock.lock()
        if let active = activeScopes[standardized.path] {
            lock.unlock()
            return active
        }
        lock.unlock()

        guard let bookmark = bookmarkStore.bookmark(for: standardized),
              let started = scopeAccessor.startAccess(bookmark: bookmark) else { return nil }

        if started.isStale, let refreshed = scopeAccessor.refreshedBookmark(for: started.url) {
            bookmarkStore.setBookmark(refreshed, for: standardized)
        }

        lock.lock()
        // Lost a race: another thread already holds the scope; release ours.
        if let active = activeScopes[standardized.path] {
            lock.unlock()
            scopeAccessor.stopAccess(to: started.url)
            return active
        }
        activeScopes[standardized.path] = started.url
        lock.unlock()
        return started.url
    }

    /// Balances `beginPersistentAccess(to:)` for a single URL. A no-op when no
    /// scope is held for that path, so callers need not track what they began.
    func endPersistentAccess(to url: URL) {
        let standardized = url.standardizedFileURL
        lock.lock()
        let scope = activeScopes.removeValue(forKey: standardized.path)
        lock.unlock()
        // Outside the lock: stopping access is a syscall, and nothing here needs
        // the map held while it runs.
        if let scope {
            scopeAccessor.stopAccess(to: scope)
        }
    }

    /// Releases every scope this resolver holds. Idempotent, so it is safe from
    /// both `onDisappear` (which SwiftUI may call more than once, and for
    /// reasons other than teardown) and `deinit`.
    func endAllPersistentAccess() {
        lock.lock()
        let scopes = activeScopes
        activeScopes.removeAll()
        lock.unlock()
        for scope in scopes.values {
            scopeAccessor.stopAccess(to: scope)
        }
    }

    @discardableResult
    @MainActor
    func grantAccess(to url: URL) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.message = "Grant access to \u{201C}\(url.lastPathComponent)\u{201D} so ScoreEdit can read this include file."

        guard panel.runModal() == .OK, let chosen = panel.url,
              let bookmark = try? chosen.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
              )
        else { return false }

        bookmarkStore.setBookmark(bookmark, for: url.standardizedFileURL)
        clearPending(url.standardizedFileURL)
        return true
    }

    // A render pass that has been superseded may still be inside CeolKit when the
    // next one opens — cancellation does not reach it — so its late reads must
    // not touch the newer pass's pending set.
    private func markPending(_ url: URL, in pass: IncludeRenderPass) {
        lock.lock()
        if pass == currentPass { pending.insert(url) }
        lock.unlock()
    }

    private func clearPending(_ url: URL, in pass: IncludeRenderPass) {
        lock.lock()
        if pass == currentPass { pending.remove(url) }
        lock.unlock()
    }

    /// Unconditional counterpart for access granted outside a render, where the
    /// banner row must go away whichever pass put it there.
    private func clearPending(_ url: URL) {
        lock.lock()
        pending.remove(url)
        lock.unlock()
    }
}
