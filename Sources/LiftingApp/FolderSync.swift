import Foundation
import SwiftUI
import LiftingCore

struct FolderSyncConfiguration: Codable {
    var bookmark: Data?
    var name = ""
    var automaticBackup = false
    var deviceSync = false
    var deviceID = UUID()
}

enum SyncFolderIO {
    static func resolve(_ configuration: FolderSyncConfiguration) throws -> URL {
        guard let bookmark = configuration.bookmark else { throw TrainingError.invalid("Choose a backup folder.") }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw TrainingError.invalid("Choose the backup folder again to renew access.") }
        return url
    }
    static func coordinated<T>(_ folder: URL, writing: Bool, _ action: (URL) throws -> T) throws -> T {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator(); var error: NSError?, result: Result<T, Error>?
        if writing { coordinator.coordinate(writingItemAt: folder, options: .forMerging, error: &error) { url in result = Result { try action(url) } } }
        else { coordinator.coordinate(readingItemAt: folder, options: [], error: &error) { url in result = Result { try action(url) } } }
        if let error { throw error }
        guard let result else { throw TrainingError.invalid("The backup folder is unavailable.") }
        return try result.get()
    }
    static func read(_ configuration: FolderSyncConfiguration) throws -> [DeviceSyncState] {
        let folder = try resolve(configuration)
        return try coordinated(folder, writing: false) { root in
            let directory = root.appendingPathComponent("Lifting Sync/Devices", isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .ubiquitousItemDownloadingStatusKey], options: [])
            guard files.count <= 100 else { throw TrainingError.invalid("Too many device sync files.") }
            return try files.filter { $0.pathExtension == "json" || $0.lastPathComponent.hasSuffix(".json.icloud") }.map { file in
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .ubiquitousItemDownloadingStatusKey])
                if values.ubiquitousItemDownloadingStatus == .notDownloaded || file.pathExtension == "icloud" {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: file)
                    throw TrainingError.invalid("Waiting for iCloud Drive to download device data.")
                }
                guard (values.fileSize ?? 0) <= 100_000_000 else { throw TrainingError.invalid("Sync file is too large.") }
                return try DeviceSyncState.decode(Data(contentsOf: file))
            }
        }
    }
    static func write(_ configuration: FolderSyncConfiguration, state: Data?, backup: Data?, recovery: Data?) throws {
        let folder = try resolve(configuration)
        try coordinated(folder, writing: true) { root in
            let base = root.appendingPathComponent("Lifting Sync", isDirectory: true)
            func write(_ bytes: Data, _ path: String, onlyIfMissing: Bool = false) throws {
                let file = base.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: file.path) {
                    if onlyIfMissing { return }
                    if (try? Data(contentsOf: file)) == bytes { return }
                }
                try bytes.write(to: file, options: .atomic)
            }
            let id = configuration.deviceID.uuidString
            if let state { try write(state, "Devices/\(id).json") }
            if let backup {
                try write(backup, "Backups/\(id)-latest.json")
                let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
                try write(backup, "Backups/\(id)-daily-\(date).json", onlyIfMissing: true)
                try prune(base.appendingPathComponent("Backups"), prefix: id + "-daily-", keeping: 14)
            }
            if let recovery {
                try write(recovery, "Recovery/\(id)-\(Int64(Date().timeIntervalSince1970 * 1000)).json")
                try prune(base.appendingPathComponent("Recovery"), prefix: id, keeping: 30)
            }
        }
    }
    private static func prune(_ folder: URL, prefix: String, keeping: Int) throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files.dropFirst(keeping) { try FileManager.default.removeItem(at: file) }
    }
}

extension AppStore {
    func scheduleFolderSync() {
        guard syncConfiguration.automaticBackup || syncConfiguration.deviceSync else { return }
        pendingSync?.cancel()
        pendingSync = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await syncNow()
        }
    }
    var syncConfigURL: URL? { repository?.url.deletingLastPathComponent().appendingPathComponent("folder-sync.json") }
    var syncStateURL: URL? { repository?.url.deletingLastPathComponent().appendingPathComponent("sync-revisions.json") }
    func loadSyncConfiguration() {
        guard let url = syncConfigURL else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) { syncConfiguration = try JSONDecoder().decode(FolderSyncConfiguration.self, from: Data(contentsOf: url)) }
            if let stateURL = syncStateURL, FileManager.default.fileExists(atPath: stateURL.path) {
                syncState = try DeviceSyncState.decode(Data(contentsOf: stateURL))
                guard syncState?.deviceID == syncConfiguration.deviceID else { throw TrainingError.invalid("Sync device identity mismatch.") }
            }
        } catch { syncConfiguration.automaticBackup = false; syncConfiguration.deviceSync = false; syncStatus = "Sync paused: \(error.localizedDescription)" }
    }
    func configureSync(_ change: (inout FolderSyncConfiguration) -> Void) {
        var next = syncConfiguration; change(&next)
        guard let url = syncConfigURL else { syncStatus = "Use a saved library to enable backup and sync."; return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            syncConfiguration = next; syncGeneration += 1
            if !next.automaticBackup && !next.deviceSync { syncStatus = "Off" }
            else { Task { await syncNow() } }
        } catch { syncStatus = error.localizedDescription }
    }
    func chooseSyncFolder(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            #if os(macOS)
            let options: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            configureSync { $0.bookmark = bookmark; $0.name = url.lastPathComponent }
        } catch { syncStatus = error.localizedDescription }
    }
    func runSyncLoop() async {
        if !syncConfigurationLoaded { loadSyncConfiguration(); syncConfigurationLoaded = true }
        while !Task.isCancelled {
            await syncNow()
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }
    func syncNow() async {
        let configuration = syncConfiguration, generation = syncGeneration
        guard !syncing, !storageBlocked, repository != nil, configuration.bookmark != nil,
              configuration.automaticBackup || configuration.deviceSync else { return }
        syncing = true; defer { syncing = false }
        do {
            let pull = configuration.deviceSync && data.activeSession == nil
            let remote = try await Task.detached(priority: .utility) { pull ? try SyncFolderIO.read(configuration) : [] }.value
            guard generation == syncGeneration else { return }
            var state = syncState ?? DeviceSyncState(deviceID: configuration.deviceID)
            try state.capture(data)
            var recovery: Data?
            if pull && data.activeSession == nil {
                let merged = try state.merge(remote, into: data)
                if merged != data {
                    // The shared folder may be iCloud Drive, so its copies leave out Apple Health values.
                    recovery = try LocalRepository.encode(data.withoutHealthData)
                    if let repository {
                        try LocalRepository.encode(data).write(to: repository.url.appendingPathExtension("before-sync"), options: .atomic)
                        try repository.save(merged)
                    }
                    data = merged
                }
            }
            syncState = state
            let stateBytes = try state.encoded()
            if let url = syncStateURL { try stateBytes.write(to: url, options: .atomic) }
            let backup = configuration.automaticBackup ? try LocalRepository.encode(data.withoutHealthData) : nil
            let replica = configuration.deviceSync ? stateBytes : nil
            try await Task.detached(priority: .utility) { try SyncFolderIO.write(configuration, state: replica, backup: backup, recovery: recovery) }.value
            guard generation == syncGeneration else { return }
            lastFolderSync = Date()
            syncStatus = data.activeSession != nil && configuration.deviceSync ? "Device merge waits until the workout ends." : "Saved to selected folder"
        } catch {
            guard generation == syncGeneration else { return }
            let message = error.localizedDescription
            if configuration.automaticBackup, let backup = try? LocalRepository.encode(data.withoutHealthData) {
                do {
                    try await Task.detached(priority: .utility) { try SyncFolderIO.write(configuration, state: nil, backup: backup, recovery: nil) }.value
                    syncStatus = "Backup saved. Sync: \(message)"
                } catch { syncStatus = "\(message) Backup: \(error.localizedDescription)" }
            } else { syncStatus = message }
        }
    }
}
