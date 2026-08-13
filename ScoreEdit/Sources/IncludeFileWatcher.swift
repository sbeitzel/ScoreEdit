import Foundation

/// Watches the files an ABC document includes so the preview can re-render when
/// one of them is edited in its own window (#21).
///
/// Each watched path gets a `DispatchSource` file-system source. A save from
/// another window usually arrives as an atomic replace — the old inode is
/// renamed or unlinked rather than rewritten — so rename/delete events re-arm
/// the source on the new file instead of going deaf. Callers must already hold
/// read access to the URLs (see `IncludeFileAccessResolver.beginPersistentAccess`).
@MainActor
final class IncludeFileWatcher {
    /// Called on the main actor after a watched file changes, coalesced.
    var onChange: (() -> Void)?

    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var wantedPaths: Set<String> = []
    private var changeTask: Task<Void, Never>?

    private static let rearmDelay = Duration.milliseconds(200)
    private static let coalesceDelay = Duration.milliseconds(150)

    deinit {
        for source in sources.values {
            source.cancel()
        }
    }

    /// Watches exactly `urls`, arming and cancelling sources as the set changes.
    func setWatchedURLs(_ urls: [URL]) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        guard paths != wantedPaths else { return }
        wantedPaths = paths
        for path in sources.keys where !paths.contains(path) {
            stopWatching(path)
        }
        for path in paths where sources[path] == nil {
            startWatching(path)
        }
    }

    func cancelAll() {
        wantedPaths.removeAll()
        for path in sources.keys {
            stopWatching(path)
        }
        changeTask?.cancel()
        changeTask = nil
    }

    private func startWatching(_ path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                if !source.data.intersection([.rename, .delete]).isEmpty {
                    self.rearm(path)
                }
                self.scheduleChange()
            }
        }
        source.setCancelHandler { close(descriptor) }
        sources[path] = source
        source.resume()
    }

    private func stopWatching(_ path: String) {
        sources.removeValue(forKey: path)?.cancel()
    }

    /// The watched file was replaced; re-open the path once the writer has
    /// finished putting the new file in place.
    private func rearm(_ path: String) {
        stopWatching(path)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.rearmDelay)
            guard let self, self.wantedPaths.contains(path), self.sources[path] == nil else { return }
            self.startWatching(path)
        }
    }

    private func scheduleChange() {
        changeTask?.cancel()
        changeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.coalesceDelay)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
