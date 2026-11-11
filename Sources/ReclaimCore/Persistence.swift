import Foundation

public struct AppIdentity {
    public static var development: Bool { Bundle.main.bundleIdentifier != "io.github.swlittles.Reclaim" }
    public static var name: String { development ? "Reclaim Dev" : "Reclaim" }
    public static var dataURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/" + name) }
}
public final class LocalStore {
    public let directory: URL
    private let lock = NSRecursiveLock()
    public init(directory: URL = AppIdentity.dataURL) { self.directory = directory }
    public func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    public func write<T: Encodable>(_ value: T, to name: String) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directory.appendingPathComponent(name)
        try encoder.encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
