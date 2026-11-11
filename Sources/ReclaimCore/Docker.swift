import Foundation
import CryptoKit

public final class DockerService {
    let executable: String?
    let runner: CommandRunning
    public init(executable: String?, runner: CommandRunning = ProcessRunner()) { self.executable = executable; self.runner = runner }
    func run(_ args: [String], token: CancellationToken?) throws -> CommandResult {
        guard let executable else { throw ReclaimError.refused("Docker CLI is not installed.") }
        let r = try runner.run(executable, args, cwd: "/", timeout: 15, token: token)
        guard r.code == 0 else { throw ReclaimError.refused("Docker is unavailable or refused the operation (\(r.code)). The app does not start its engine.") }
        return r
    }
    func context(_ name: String? = nil, token: CancellationToken?) throws -> (String, String) {
        let selected = try name ?? run(["context", "show"], token: token).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try run(["context", "inspect", selected], token: token).data
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let endpoints = list.first?["Endpoints"] as? [String: Any], let docker = endpoints["docker"] as? [String: Any], let endpoint = docker["Host"] as? String else { throw ReclaimError.refused("Cannot verify Docker context.") }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let allowed = ["unix:///var/run/docker.sock", "unix://" + home + "/.docker/run/docker.sock", "unix://" + home + "/.colima/default/docker.sock", "unix://" + home + "/.orbstack/run/docker.sock"]
        guard allowed.contains(endpoint) else { throw ReclaimError.refused("Remote or unknown Docker endpoint is disabled: \(selected)") }
        return (selected, endpoint)
    }
    func inspect(_ kind: String, _ id: String, context: String, token: CancellationToken?) throws -> [String: Any] {
        let data = try run(["--context", context, kind, "inspect", id], token: token).data
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let object = list.first, list.count == 1 else { throw ReclaimError.refused("Cannot inspect exact Docker object.") }
        return object
    }
    func signature(_ object: [String: Any], kind: String) throws -> String {
        let keys = kind == "volume" ? ["Name", "Driver", "CreatedAt", "Mountpoint", "Labels", "Options", "Scope"] : ["Id", "Created", "Image", "Config"]
        let stable = object.filter { keys.contains($0.key) }
        let data = try JSONSerialization.data(withJSONObject: stable, options: [.sortedKeys])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func inventory(token: CancellationToken? = nil) -> (findings: [Finding], issues: [String]) {
        guard executable != nil else { return ([], ["Docker CLI unavailable; container inventory skipped."]) }
        do {
            let (ctx, endpoint) = try context(token: token)
            _ = try run(["--context", ctx, "info", "--format", "{{.ServerVersion}}"], token: token)
            var findings: [Finding] = []
            for (kind, args, key, action) in [("volume", ["volume", "ls"], "Name", CleanupAction.dockerVolume), ("container", ["container", "ls", "-a", "--no-trunc"], "ID", .dockerContainer), ("image", ["image", "ls", "--no-trunc"], "ID", .dockerImage)] {
                let r = try run(["--context", ctx] + args + ["--format", "{{json .}}"], token: token)
                let lines = r.output.split(separator: "\n")
                guard lines.count <= 1000 else { throw ReclaimError.refused("Docker inventory limit reached.") }
                var seen = Set<String>()
                for line in lines {
                    if token?.isCancelled == true { throw ReclaimError.refused("Cancelled") }
                    guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = obj[key] as? String, seen.insert(id).inserted else { continue }
                    let object = try inspect(kind, id, context: ctx, token: token)
                    var blocked: String?
                    if kind == "container" {
                        let state = object["State"] as? [String: Any]
                        if state?["Status"] as? String != "exited" && state?["Status"] as? String != "created" { blocked = "Only stopped containers can be removed." }
                    }
                    if kind == "volume" {
                        if (object["CreatedAt"] as? String ?? "").isEmpty { blocked = "Volume creation identity is unavailable; inventory only." }
                        let attached = try run(["--context", ctx, "container", "ls", "-aq", "--filter", "volume=" + id], token: token)
                        if !attached.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocked = "Referenced by a container, including stopped containers." }
                    }
                    let target = DockerTarget(executable: executable!, context: ctx, endpoint: endpoint, objectID: id, signature: try signature(object, kind: kind))
                    let label = (obj["Names"] ?? obj["Repository"] ?? id) as? String ?? id
                    let details = "Docker \(kind) · local context \(ctx). \(kind == "volume" ? "May contain databases or irreplaceable data. Unattached does not mean disposable." : "Exact object removal, without force.") Size is not counted: shared/VM allocation is not attributable."
                    findings.append(Finding(path: "docker://\(ctx)/\(kind)/\(id)", name: label, category: .containers, detail: details, action: action, blockedReason: blocked, docker: target))
                }
            }
            return (findings, ["Docker image/cache/VM sizes overlap; object sizes are not added to filesystem totals. Build cache pruning is inventory-only; use Docker's own reviewed maintenance tools."])
        } catch { return ([], [error.localizedDescription]) }
    }
    public func remove(_ target: DockerTarget, action: CleanupAction, token: CancellationToken? = nil) throws {
        let (ctx, endpoint) = try context(target.context, token: token)
        guard endpoint == target.endpoint, executable == target.executable else { throw ReclaimError.refused("Docker endpoint or executable changed.") }
        let kind: String
        switch action { case .dockerVolume: kind = "volume"; case .dockerContainer: kind = "container"; case .dockerImage: kind = "image"; default: throw ReclaimError.refused("Unsupported Docker action") }
        let object = try inspect(kind, target.objectID, context: ctx, token: token)
        guard try signature(object, kind: kind) == target.signature else { throw ReclaimError.refused("Docker object changed or was recreated after review.") }
        if kind == "volume" {
            guard !(object["CreatedAt"] as? String ?? "").isEmpty else { throw ReclaimError.refused("Cannot verify volume creation identity.") }
            let attached = try run(["--context", ctx, "container", "ls", "-aq", "--filter", "volume=" + target.objectID], token: token)
            guard attached.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReclaimError.refused("Volume is referenced by a container.") }
        }
        if kind == "container" {
            let state = object["State"] as? [String: Any]
            guard ["exited", "created"].contains(state?["Status"] as? String ?? "") else { throw ReclaimError.refused("Container is no longer stopped.") }
        }
        _ = try run(["--context", ctx, kind, "rm", target.objectID], token: token)
    }
}
