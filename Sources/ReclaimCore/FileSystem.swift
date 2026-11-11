import Foundation
import CryptoKit
import Darwin

public enum FileSystem {
    public static func info(_ path: String) throws -> stat {
        var value = stat()
        guard lstat(path, &value) == 0 else { throw ReclaimError.refused("Cannot inspect \(path): \(String(cString: strerror(errno)))") }
        return value
    }
    public static func identity(_ s: stat) -> String { "\(s.st_dev):\(s.st_ino):\(s.st_mode):\(s.st_uid)" }
    public static func symlink(_ s: stat) -> Bool { s.st_mode & S_IFMT == S_IFLNK }
    public static func directory(_ s: stat) -> Bool { s.st_mode & S_IFMT == S_IFDIR }
    public static func cloudOnly(_ s: stat) -> Bool { s.st_flags & UInt32(SF_DATALESS) != 0 }
    public static func ancestors(_ path: String) throws -> [String] {
        var url = URL(fileURLWithPath: path).standardized.deletingLastPathComponent()
        var result: [String] = []
        while true {
            let s = try info(url.path)
            guard !symlink(s) else { throw ReclaimError.refused("A parent folder is a symbolic link: \(url.path)") }
            result.append(url.path + ":" + identity(s))
            if url.path == "/" { return result }; url.deleteLastPathComponent()
        }
    }
    public static func measure(_ path: String, token: CancellationToken? = nil, limit: Int = 250_000, progress: (Int) -> Void = { _ in }) -> Measurement {
        var m = Measurement()
        do {
            let root = try info(path)
            guard !symlink(root), !cloudOnly(root) else { throw ReclaimError.refused("Symbolic link or cloud-only placeholder; skipped.") }
            let deadline = Date().addingTimeInterval(60)
            var entries: [(String, stat)] = [(path, root)]
            if directory(root) {
                var walkError: Error?
                guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [], errorHandler: { _, e in walkError = e; return true }) else { throw ReclaimError.refused("Cannot enumerate folder.") }
                for case let url as URL in walker {
                    if token?.isCancelled == true { throw ReclaimError.refused("Cancelled") }
                    guard entries.count < limit && Date() < deadline else { throw ReclaimError.refused("Measurement item/time limit reached.") }
                    let s = try info(url.path)
                    if cloudOnly(s) || s.st_dev != root.st_dev { walker.skipDescendants(); m.complete = false; m.warning = "Skipped cloud placeholder or nested volume."; continue }
                    if symlink(s) { walker.skipDescendants() }
                    entries.append((url.path, s))
                    if entries.count % 512 == 0 { progress(entries.count) }
                }
                if let walkError { throw walkError }
            }
            var seen = Set<String>(), digest = SHA256()
            for (p, s) in entries.sorted(by: { $0.0 < $1.0 }) {
                let modified = Date(timeIntervalSince1970: Double(s.st_mtimespec.tv_sec) + Double(s.st_mtimespec.tv_nsec) / 1_000_000_000)
                m.latestModified = max(m.latestModified ?? modified, modified)
                let signature = "\(p)\u{0}\(identity(s)):\(s.st_size):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec):\(s.st_ctimespec.tv_sec):\(s.st_ctimespec.tv_nsec)\u{0}"
                digest.update(data: Data(signature.utf8))
                if seen.insert("\(s.st_dev):\(s.st_ino)").inserted {
                    m.allocated += Int64(s.st_blocks) * 512
                    if !directory(s) { m.logical += Int64(s.st_size); m.files += 1 }
                }
            }
            m.fingerprint = Fingerprint(identity: identity(root), digest: digest.finalize().map { String(format: "%02x", $0) }.joined(), ancestors: try ancestors(path))
            progress(entries.count)
        } catch { m.complete = false; m.warning = error.localizedDescription }
        return m
    }
    public static func normalized(_ path: String) -> String { URL(fileURLWithPath: path).standardized.path }
    public static func nonoverlapping(_ findings: [Finding]) -> [Finding] {
        var result: [Finding] = []
        for f in findings.sorted(by: { $0.path.count < $1.path.count }) {
            if !result.contains(where: { isWithin(f.path, $0.path) }) { result.append(f) }
        }
        return result
    }
}
public struct PathGuard {
    public var home: String
    public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path) { self.home = home }
    public func validate(_ path: String, allowedRoots: [String], exclusions: [String]) throws {
        let path = FileSystem.normalized(path)
        let forbidden = ["/", home, "/System", "/bin", "/sbin", "/usr", "/private", "/dev", "/Library", "/Applications", "/Volumes", home + "/Library", home + "/Documents", home + "/Desktop", home + "/Downloads", home + "/.Trash"]
        let userTemp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        let privateSystem = isWithin(path, "/private") && !isWithin(path, userTemp)
        guard !forbidden.contains(path), path != userTemp, !privateSystem, !["/System", "/bin", "/sbin", "/usr", "/dev"].contains(where: { isWithin(path, $0) }) else { throw ReclaimError.refused("Protected system or top-level folder.") }
        guard allowedRoots.contains(where: { isWithin(path, $0) }), !exclusions.contains(where: { isWithin(path, $0) }) else { throw ReclaimError.refused("Target is excluded or outside the reviewed scope.") }
        let s = try FileSystem.info(path)
        guard !FileSystem.symlink(s), !FileSystem.cloudOnly(s), s.st_uid == getuid() else { throw ReclaimError.refused("Target is a link, placeholder, or owned by another user.") }
        _ = try FileSystem.ancestors(path)
        if FileSystem.directory(s) {
            let parent = try FileSystem.info(URL(fileURLWithPath: path).deletingLastPathComponent().path)
            guard s.st_dev == parent.st_dev else { throw ReclaimError.refused("Volume roots cannot be removed.") }
        }
    }
}
