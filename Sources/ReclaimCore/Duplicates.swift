import Foundation
import CryptoKit
import Darwin

public struct DuplicateGroup: Identifiable {
    public var id: String { digest }
    public var digest: String
    public var paths: [String]
    public var size: Int64
}
public enum DuplicateScanner {
    public static func scan(roots: [String], exclusions: [String], token: CancellationToken, progress: (String) -> Void = { _ in }, activityProgress: (ScanProgress) -> Void = { _ in }, issue: @escaping (String) -> Void = { _ in }) -> [DuplicateGroup] {
        var candidates: [Int64: [String]] = [:], identities = Set<String>(), count = 0
        let deadline = Date().addingTimeInterval(600)
        for root in roots {
            activityProgress(ScanProgress("Discovering duplicate candidates", completed: Double(count), unit: "entries", path: root))
            guard let rootInfo = try? FileSystem.info(root), !FileSystem.symlink(rootInfo), !FileSystem.cloudOnly(rootInfo) else { issue("Unavailable or linked duplicate root: " + root); continue }
            guard let walk = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil, options: [], errorHandler: { url, error in issue("Skipped \(url.path): \(error.localizedDescription)"); return true }) else { issue("Cannot enumerate " + root); continue }
            for case let url as URL in walk {
                if token.isCancelled { break }; if count > 200_000 || Date() > deadline { issue("Duplicate enumeration budget reached. Add narrower roots."); break }; count += 1
                if count % 1000 == 0 { activityProgress(ScanProgress("Discovering duplicate candidates", completed: Double(count), unit: "entries", path: url.path)) }
                guard !exclusions.contains(where: { isWithin(url.path, $0) }), let s = try? FileSystem.info(url.path), !FileSystem.symlink(s), !FileSystem.cloudOnly(s), s.st_dev == rootInfo.st_dev else { walk.skipDescendants(); continue }
                if FileSystem.directory(s) {
                    if [".git", "node_modules", ".build", "target", "Library", ".Trash"].contains(url.lastPathComponent) || url.pathExtension == "app" { walk.skipDescendants() }; continue
                }
                guard s.st_mode & S_IFMT == S_IFREG, s.st_size > 0, identities.insert(FileSystem.identity(s)).inserted else { continue }
                candidates[Int64(s.st_size), default: []].append(url.path)
            }
        }
        var groups: [DuplicateGroup] = []
        let hashCandidates = candidates.filter { $0.value.count > 1 }
        let totalBytes = hashCandidates.reduce(0.0) { $0 + Double($1.key) * Double($1.value.count) }
        var processedBytes = 0.0
        activityProgress(ScanProgress("Hashing duplicate candidates", total: totalBytes, unit: "bytes"))
        for (size, paths) in hashCandidates.sorted(by: { $0.key < $1.key }) {
            if token.isCancelled { break }
            var hashes: [String: [String]] = [:]
            for path in paths {
                if token.isCancelled { break }; if Date() > deadline { issue("Hashing time budget reached; results are partial."); return groups }; progress(path)
                let start = processedBytes
                defer {
                    processedBytes += Double(size)
                    if !token.isCancelled { activityProgress(ScanProgress("Hashing duplicate candidates", completed: processedBytes, total: totalBytes, unit: "bytes checked or skipped", path: path)) }
                }
                guard let before = try? FileSystem.info(path), !FileSystem.cloudOnly(before) else { issue("Duplicate candidate changed or became unavailable: " + path); continue }
                // O_NOFOLLOW closes the final-component symlink race before reading content.
                let fd = open(path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { issue("Cannot read duplicate candidate: " + path); continue }
                var opened = stat()
                guard fstat(fd, &opened) == 0, FileSystem.identity(opened) == FileSystem.identity(before), !FileSystem.cloudOnly(opened) else { close(fd); issue("Duplicate candidate identity changed: " + path); continue }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                var digest = SHA256(), valid = true
                var readBytes = 0.0, lastReport = Date.distantPast
                do {
                    while !token.isCancelled {
                        let data = try handle.read(upToCount: 1_048_576) ?? Data()
                        if data.isEmpty { break }; digest.update(data: data)
                        readBytes += Double(data.count)
                        if Date().timeIntervalSince(lastReport) >= 0.15 {
                            activityProgress(ScanProgress("Hashing duplicate candidates", completed: min(start + Double(size), start + readBytes), total: totalBytes, unit: "bytes checked or skipped", path: path)); lastReport = Date()
                        }
                    }
                    let after = try FileSystem.info(path)
                    valid = !token.isCancelled && FileSystem.identity(before) == FileSystem.identity(after) && before.st_size == after.st_size && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
                } catch { valid = false }
                try? handle.close()
                if valid { hashes[digest.finalize().map { String(format: "%02x", $0) }.joined(), default: []].append(path) }
                else if !token.isCancelled { issue("Duplicate candidate changed or could not be hashed: " + path) }
            }
            for (digest, matches) in hashes where matches.count > 1 { groups.append(DuplicateGroup(digest: digest, paths: matches.sorted(), size: size)) }
        }
        return groups.sorted { $0.size * Int64($0.paths.count - 1) > $1.size * Int64($1.paths.count - 1) }
    }
}
