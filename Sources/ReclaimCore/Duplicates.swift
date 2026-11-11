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
    public static func scan(roots: [String], exclusions: [String], token: CancellationToken, progress: (String) -> Void = { _ in }, issue: @escaping (String) -> Void = { _ in }) -> [DuplicateGroup] {
        var candidates: [Int64: [String]] = [:], identities = Set<String>(), count = 0
        let deadline = Date().addingTimeInterval(600)
        for root in roots {
            guard let rootInfo = try? FileSystem.info(root), !FileSystem.symlink(rootInfo), !FileSystem.cloudOnly(rootInfo) else { issue("Unavailable or linked duplicate root: " + root); continue }
            guard let walk = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil, options: [], errorHandler: { url, error in issue("Skipped \(url.path): \(error.localizedDescription)"); return true }) else { issue("Cannot enumerate " + root); continue }
            for case let url as URL in walk {
                if token.isCancelled { break }; if count > 200_000 || Date() > deadline { issue("Duplicate enumeration budget reached. Add narrower roots."); break }; count += 1
                guard !exclusions.contains(where: { isWithin(url.path, $0) }), let s = try? FileSystem.info(url.path), !FileSystem.symlink(s), !FileSystem.cloudOnly(s), s.st_dev == rootInfo.st_dev else { walk.skipDescendants(); continue }
                if FileSystem.directory(s) {
                    if [".git", "node_modules", ".build", "target", "Library", ".Trash"].contains(url.lastPathComponent) || url.pathExtension == "app" { walk.skipDescendants() }; continue
                }
                guard s.st_mode & S_IFMT == S_IFREG, s.st_size > 0, identities.insert(FileSystem.identity(s)).inserted else { continue }
                candidates[Int64(s.st_size), default: []].append(url.path)
            }
        }
        var groups: [DuplicateGroup] = []
        for (size, paths) in candidates where paths.count > 1 {
            if token.isCancelled { break }
            var hashes: [String: [String]] = [:]
            for path in paths {
                if token.isCancelled { break }; if Date() > deadline { issue("Hashing time budget reached; results are partial."); return groups }; progress(path)
                guard let before = try? FileSystem.info(path), !FileSystem.cloudOnly(before) else { continue }
                // O_NOFOLLOW closes the final-component symlink race before reading content.
                let fd = open(path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { continue }
                var opened = stat()
                guard fstat(fd, &opened) == 0, FileSystem.identity(opened) == FileSystem.identity(before), !FileSystem.cloudOnly(opened) else { close(fd); continue }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                var digest = SHA256(), valid = true
                do {
                    while !token.isCancelled {
                        let data = try handle.read(upToCount: 1_048_576) ?? Data()
                        if data.isEmpty { break }; digest.update(data: data)
                    }
                    let after = try FileSystem.info(path)
                    valid = !token.isCancelled && FileSystem.identity(before) == FileSystem.identity(after) && before.st_size == after.st_size && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
                } catch { valid = false }
                try? handle.close()
                if valid { hashes[digest.finalize().map { String(format: "%02x", $0) }.joined(), default: []].append(path) }
            }
            for (digest, matches) in hashes where matches.count > 1 { groups.append(DuplicateGroup(digest: digest, paths: matches.sorted(), size: size)) }
        }
        return groups.sorted { $0.size * Int64($0.paths.count - 1) > $1.size * Int64($1.paths.count - 1) }
    }
}
