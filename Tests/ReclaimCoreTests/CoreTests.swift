import Foundation
import ReclaimCore

final class Fixture {
    let root: URL
    init() throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/test-fixtures/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func path(_ p: String) -> String { root.appendingPathComponent(p).path }
    func file(_ p: String, _ content: String = "test content") throws {
        let url = root.appendingPathComponent(p)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }
    @discardableResult func git(_ args: [String], at relative: String = "repo") throws -> CommandResult {
        let r = try ProcessRunner().run("/usr/bin/git", args, cwd: path(relative), timeout: 10, token: nil)
        if r.code != 0 { throw ReclaimError.refused(r.error) }; return r
    }
    func repository() throws {
        try file("repo/README", "committed work")
        try git(["init", "-b", "main"])
        try git(["config", "user.name", "Fixture"]); try git(["config", "user.email", "fixture@example.invalid"])
        try git(["add", "."]); try git(["commit", "-m", "fixture"])
    }
    func worktree(_ name: String = "outside/linked") throws {
        try git(["worktree", "add", "-b", "feature-" + UUID().uuidString, path(name)])
    }
}
final class FakeTrash: TrashManaging {
    let directory: String
    init(_ directory: String) { self.directory = directory }
    func trash(_ path: String) throws -> String {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let dest = directory + "/" + UUID().uuidString
        try FileManager.default.moveItem(atPath: path, toPath: dest); return dest
    }
    func restore(_ from: String, to: String) throws { try FileManager.default.moveItem(atPath: from, toPath: to) }
}
final class CoreTests {
    let quiet = ActivitySnapshot(paths: [])
    func testNULParserPreservesUnusualPaths() throws {
        let path = "/Users/test/with tabs\tand\nnewlines café"
        let data = Data("worktree /main\0HEAD abc\0branch refs/heads/main\0\0worktree \(path)\0HEAD def\0detached\0locked keep\0\0".utf8)
        let w = try WorktreeParser.parse(data, commonDirectory: "/main/.git")
        XCTAssertEqual(w.count, 2); XCTAssertTrue(w[0].main); XCTAssertFalse(w[1].main); XCTAssertEqual(w[1].path, path); XCTAssertEqual(w[1].locked, "keep")
        XCTAssertThrowsError(try WorktreeParser.parse(Data("worktree /broken".utf8), commonDirectory: "/"))
        XCTAssertThrowsError(try WorktreeParser.parse(Data("HEAD abc\0\0".utf8), commonDirectory: "/"))
    }
    func testWorktreeFamilyExpandsBeyondRootAndKeepsBranchOnRemoval() throws {
        let f = try Fixture(); try f.repository(); try f.worktree("far away/linked\nwith newline")
        let git = GitService()
        let family = try git.family(at: f.path("repo"))
        XCTAssertEqual(family.count, 2)
        let input = try XCTUnwrap(family.first { !$0.main })
        let checked = git.inspect(input, activity: quiet)
        XCTAssertTrue(checked.canRemove, checked.blockers.joined(separator: ";"))
        let branch = try XCTUnwrap(checked.branch)
        let ref = try git.remove(checked, activity: quiet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checked.path))
        XCTAssertEqual(try f.git(["rev-parse", branch]).output.trimmingCharacters(in: .newlines), checked.head)
        XCTAssertEqual(try f.git(["rev-parse", ref]).output.trimmingCharacters(in: .newlines), checked.head)
        XCTAssertEqual(try git.family(at: f.path("repo")).count, 1)
    }
    func testMainDirtyIgnoredLockedAndChangedHEADAreProtected() throws {
        let f = try Fixture(); try f.repository(); try f.worktree()
        let git = GitService(), family = try git.family(at: f.path("repo"))
        let input = try XCTUnwrap(family.first { !$0.main })
        XCTAssertFalse(git.inspect(family[0], activity: quiet).canRemove)
        try f.file("outside/linked/untracked")
        XCTAssertFalse(git.inspect(input, activity: quiet).canRemove)
        try FileManager.default.removeItem(atPath: f.path("outside/linked/untracked"))
        try f.file("outside/linked/.gitignore", ".env\n"); try f.git(["add", ".gitignore"], at: "outside/linked"); try f.git(["commit", "-m", "ignore"], at: "outside/linked")
        let fresh = try XCTUnwrap(git.family(at: f.path("repo")).first { !$0.main })
        try f.file("outside/linked/.env", "local valuable data")
        XCTAssertTrue(git.inspect(fresh, activity: quiet).blockers.contains { $0.contains("ignored") })
        XCTAssertThrowsError(try git.remove(fresh, activity: quiet))
        try FileManager.default.removeItem(atPath: f.path("outside/linked/.env"))
        try f.git(["worktree", "lock", f.path("outside/linked"), "--reason", "keep it"])
        let locked = try XCTUnwrap(git.family(at: f.path("repo")).first { !$0.main })
        XCTAssertFalse(git.inspect(locked, activity: quiet).canRemove)
        XCTAssertThrowsError(try git.remove(input, activity: quiet))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }
    func testDetachedUniqueCommitAndActivityBlockRemoval() throws {
        let f = try Fixture(); try f.repository(); try f.worktree()
        try f.git(["checkout", "--detach"], at: "outside/linked")
        try f.file("outside/linked/README", "unique detached content")
        try f.git(["add", "."], at: "outside/linked"); try f.git(["commit", "-m", "unique"], at: "outside/linked")
        let git = GitService(), w = try XCTUnwrap(git.family(at: f.path("repo")).first { !$0.main })
        XCTAssertTrue(git.inspect(w, activity: quiet).blockers.contains { $0.contains("durable") })
        XCTAssertFalse(git.inspect(w, activity: ActivitySnapshot(paths: [w.path])).canRemove)
        XCTAssertFalse(git.inspect(w, activity: ActivitySnapshot(paths: [], known: false)).canRemove)
    }
    func testScannerFindsExternalWorktreeAndArtifacts() throws {
        let f = try Fixture(); try f.repository(); try f.worktree()
        try f.file("repo/package.json", "{}"); try f.file("repo/node_modules/pkg/index.js")
        try f.file("outside/linked/Cargo.toml", "[package]\nname = \"fixture\""); try f.file("outside/linked/target/debug/output")
        try f.file("repo/venv/precious.txt") // Name alone must not classify an environment.
        let scan = StorageScanner().scan(ScanOptions(home: f.root.path, roots: [f.path("repo")], includeSystemLocations: false, largeFileThreshold: 1))
        XCTAssertEqual(scan.findings.filter { $0.category == .worktrees }.count, 2)
        XCTAssertTrue(scan.findings.contains { $0.path == f.path("repo/node_modules") && $0.category == .developer })
        XCTAssertFalse(scan.findings.contains { $0.path == f.path("repo/venv") && $0.category == .developer })
        XCTAssertTrue(scan.findings.contains { $0.path == f.path("outside/linked") })
        XCTAssertTrue(scan.findings.contains { $0.path == f.path("outside/linked/target") && $0.category == .developer })
    }
    func testMeasurementCountsHardLinksOnceAndDoesNotFollowSymlinks() throws {
        let f = try Fixture(); try f.file("tree/a", String(repeating: "a", count: 10000))
        try FileManager.default.linkItem(atPath: f.path("tree/a"), toPath: f.path("tree/b"))
        let before = FileSystem.measure(f.path("tree"))
        XCTAssertTrue(before.complete); XCTAssertEqual(before.logical, 10000)
        try f.file("outside/secret", String(repeating: "x", count: 100000))
        try FileManager.default.createSymbolicLink(atPath: f.path("tree/link"), withDestinationPath: f.path("outside"))
        let after = FileSystem.measure(f.path("tree"))
        XCTAssertTrue(after.complete); XCTAssertLessThan(after.logical, 20000)
        XCTAssertFalse(FileSystem.measure(f.path("tree/link")).complete)
    }
    func testTrashRestoreCollisionAndExclusionRevalidation() throws {
        let f = try Fixture(); try f.file("cache/item")
        let store = LocalStore(directory: f.root.appendingPathComponent("journal"))
        let executor = CleanupExecutor(store: store, trash: FakeTrash(f.path("fake-trash")))
        let finding = Finding(path: f.path("cache/item"), category: .caches, detail: "fixture", measurement: FileSystem.measure(f.path("cache/item")))
        let plan = try CleanupPlan(findings: [finding], exclusions: [])
        let blocked = executor.execute(plan, exclusions: { [f.path("cache")] }, token: CancellationToken(), activity: { self.quiet })
        XCTAssertEqual(blocked[0].status, "Skipped or failed"); XCTAssertTrue(FileManager.default.fileExists(atPath: finding.path))
        let entries = executor.execute(plan, exclusions: { [] }, token: CancellationToken(), activity: { self.quiet })
        let entry = try XCTUnwrap(entries.first); XCTAssertEqual(entry.status, "Completed", entry.detail)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finding.path))
        try f.file("cache/item", "replacement")
        XCTAssertThrowsError(try executor.restore(entry, exclusions: []))
        try FileManager.default.removeItem(atPath: finding.path)
        try executor.restore(entry, exclusions: [])
        XCTAssertEqual(try String(contentsOfFile: finding.path), "test content")
    }
    func testChangedChildAndSymlinkParentAreRejected() throws {
        let f = try Fixture(); try f.file("cache/folder/file")
        let executor = CleanupExecutor(store: LocalStore(directory: f.root.appendingPathComponent("journal")), trash: FakeTrash(f.path("trash")))
        let finding = Finding(path: f.path("cache/folder"), category: .caches, detail: "fixture", measurement: FileSystem.measure(f.path("cache/folder")))
        let plan = try CleanupPlan(findings: [finding], exclusions: [])
        try f.file("cache/folder/file", "new work")
        let result = executor.execute(plan, exclusions: { [] }, token: CancellationToken(), activity: { self.quiet })
        XCTAssertEqual(result[0].status, "Skipped or failed"); XCTAssertTrue(result[0].detail.contains("changed"))
        try FileManager.default.createSymbolicLink(atPath: f.path("alias"), withDestinationPath: f.path("cache"))
        XCTAssertThrowsError(try PathGuard().validate(f.path("alias/folder"), allowedRoots: [f.root.path], exclusions: []))
        XCTAssertThrowsError(try PathGuard().validate("/", allowedRoots: ["/"], exclusions: []))
        XCTAssertFalse(isWithin("/foo/barley", "/foo/bar"))
    }
    func testOverlappingSelectionAndCancellation() throws {
        let f = try Fixture(); try f.file("cache/folder/a")
        let a = Finding(path: f.path("cache"), category: .caches, detail: "fixture", measurement: FileSystem.measure(f.path("cache")))
        let b = Finding(path: f.path("cache/folder"), category: .developer, detail: "fixture", measurement: FileSystem.measure(f.path("cache/folder")))
        XCTAssertThrowsError(try CleanupPlan(findings: [a, b], exclusions: []))
        let token = CancellationToken(); token.cancel()
        let result = StorageScanner(token: token).scan(ScanOptions(home: f.root.path, roots: [f.root.path], includeSystemLocations: false))
        XCTAssertFalse(result.complete)
    }
    func testDuplicateHashingUsesContentAndSkipsHardlinks() throws {
        let f = try Fixture(); try f.file("a", "identical"); try f.file("b", "identical"); try f.file("c", "different")
        try FileManager.default.linkItem(atPath: f.path("a"), toPath: f.path("hardlink"))
        let groups = DuplicateScanner.scan(roots: [f.root.path], exclusions: [], token: CancellationToken())
        XCTAssertEqual(groups.count, 1); XCTAssertEqual(groups[0].paths.count, 2)
        XCTAssertFalse(groups[0].paths.contains(f.path("c")))
    }
    func testJournalMarksInterruptedAndDataIsPrivate() throws {
        let f = try Fixture(), store = LocalStore(directory: f.root.appendingPathComponent("journal"))
        let entry = HistoryEntry(path: f.path("a"), action: .trash, status: "Started", detail: "fixture")
        try store.write([entry], to: "history.json")
        XCTAssertTrue(CleanupExecutor(store: store).history()[0].status.hasPrefix("Interrupted"))
        let attrs = try FileManager.default.attributesOfItem(atPath: store.directory.appendingPathComponent("history.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testDockerRechecksReferencesContextAndObjectIdentity() throws {
        let fake = MockDocker()
        let docker = DockerService(executable: "/trusted/docker", runner: fake)
        let inventory = docker.inventory()
        XCTAssertEqual(inventory.findings.count, 1, inventory.issues.joined(separator: ";"))
        let target = try XCTUnwrap(inventory.findings.first?.docker)
        fake.attached = true
        XCTAssertThrowsError(try docker.remove(target, action: .dockerVolume))
        XCTAssertEqual(fake.removals, 0)
        fake.attached = false; fake.created = "recreated"
        XCTAssertThrowsError(try docker.remove(target, action: .dockerVolume))
        XCTAssertEqual(fake.removals, 0)
        fake.created = "original"; fake.endpoint = "ssh://remote"
        XCTAssertThrowsError(try docker.remove(target, action: .dockerVolume))
        XCTAssertEqual(fake.removals, 0)
        fake.endpoint = "unix:///var/run/docker.sock"
        try docker.remove(target, action: .dockerVolume)
        XCTAssertEqual(fake.removals, 1)
        XCTAssertFalse(fake.calls.contains { $0.contains("--force") || $0.contains("prune") })
        XCTAssertTrue(fake.calls.contains { $0 == ["--context", "default", "volume", "rm", "fixture-data"] })
    }
    func testBareAndSubmoduleWorktreesAreProtected() throws {
        let f = try Fixture(); try f.repository(); try f.worktree()
        try f.file("outside/linked/.gitmodules", "[submodule \"child\"]\npath = child\nurl = https://example.invalid/repo")
        try f.git(["add", "."] , at: "outside/linked"); try f.git(["commit", "-m", "submodule marker"], at: "outside/linked")
        let git = GitService(), w = try XCTUnwrap(git.family(at: f.path("repo")).first { !$0.main })
        XCTAssertTrue(git.inspect(w, activity: quiet).blockers.contains { $0.contains("submodules") })
        try FileManager.default.createDirectory(atPath: f.path("bare"), withIntermediateDirectories: true)
        try f.git(["init", "--bare"], at: "bare")
        let bare = try XCTUnwrap(git.family(at: f.path("bare")).first)
        XCTAssertTrue(bare.bare); XCTAssertFalse(git.inspect(bare, activity: quiet).canRemove)
    }
    func testActiveProjectRootProtectsBuildArtifacts() {
        let snapshot = ActivitySnapshot(paths: ["/Users/fixture/project"])
        XCTAssertTrue(snapshot.blocker(for: "/Users/fixture/project/.build") != nil)
        XCTAssertTrue(snapshot.blocker(for: "/Users/fixture/project/node_modules") != nil)
        XCTAssertTrue(snapshot.blocker(for: "/Users/fixture/project/target") != nil)
        XCTAssertTrue(snapshot.blocker(for: "/Users/fixture/project/venv") != nil)
        XCTAssertTrue(snapshot.blocker(for: "/Users/fixture/project/cache") == nil)
    }
    func testProcessTimeoutAndLiteralArguments() throws {
        let runner = ProcessRunner()
        let result = try runner.run("/usr/bin/printf", ["%s", "$(no-shell); `literal`"], cwd: "/", timeout: 5, token: nil)
        XCTAssertEqual(result.output, "$(no-shell); `literal`")
        XCTAssertThrowsError(try runner.run("/bin/sleep", ["3"], cwd: "/", timeout: 0.05, token: nil))
    }
}

private var failures = 0
func XCTAssertTrue(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !value() { failures += 1; print("FAIL \(file):\(line) \(message)") }
}
func XCTAssertFalse(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(!value(), message, file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(a == b, "\(a) != \(b) " + message, file: file, line: line) }
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(a < b, "Expected \(a) < \(b)", file: file, line: line) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try expression(); XCTAssertTrue(false, "Expected an error", file: file, line: line) } catch {} }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw ReclaimError.refused("Expected non-nil fixture value") }; return value }

@main struct TestRunner {
    static func main() {
        let suite = CoreTests()
        let tests: [(String, () throws -> Void)] = [
            ("testNULParserPreservesUnusualPaths", suite.testNULParserPreservesUnusualPaths),
            ("testWorktreeFamilyExpandsBeyondRootAndKeepsBranchOnRemoval", suite.testWorktreeFamilyExpandsBeyondRootAndKeepsBranchOnRemoval),
            ("testMainDirtyIgnoredLockedAndChangedHEADAreProtected", suite.testMainDirtyIgnoredLockedAndChangedHEADAreProtected),
            ("testDetachedUniqueCommitAndActivityBlockRemoval", suite.testDetachedUniqueCommitAndActivityBlockRemoval),
            ("testScannerFindsExternalWorktreeAndArtifacts", suite.testScannerFindsExternalWorktreeAndArtifacts),
            ("testMeasurementCountsHardLinksOnceAndDoesNotFollowSymlinks", suite.testMeasurementCountsHardLinksOnceAndDoesNotFollowSymlinks),
            ("testTrashRestoreCollisionAndExclusionRevalidation", suite.testTrashRestoreCollisionAndExclusionRevalidation),
            ("testChangedChildAndSymlinkParentAreRejected", suite.testChangedChildAndSymlinkParentAreRejected),
            ("testOverlappingSelectionAndCancellation", suite.testOverlappingSelectionAndCancellation),
            ("testDuplicateHashingUsesContentAndSkipsHardlinks", suite.testDuplicateHashingUsesContentAndSkipsHardlinks),
            ("testJournalMarksInterruptedAndDataIsPrivate", suite.testJournalMarksInterruptedAndDataIsPrivate),
            ("testDockerRechecksReferencesContextAndObjectIdentity", suite.testDockerRechecksReferencesContextAndObjectIdentity),
            ("testBareAndSubmoduleWorktreesAreProtected", suite.testBareAndSubmoduleWorktreesAreProtected),
            ("testActiveProjectRootProtectsBuildArtifacts", suite.testActiveProjectRootProtectsBuildArtifacts),
            ("testProcessTimeoutAndLiteralArguments", suite.testProcessTimeoutAndLiteralArguments)
        ]
        for (name, run) in tests {
            let before = failures
            do { try run() } catch { failures += 1; print("FAIL \(name): \(error)") }
            print("\(failures == before ? "PASS" : "FAIL") \(name)")
        }
        print("\(tests.count) tests; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}

final class MockDocker: CommandRunning {
    var endpoint = "unix:///var/run/docker.sock"
    var attached = false
    var created = "original"
    var removals = 0
    var calls: [[String]] = []
    func run(_ executable: String, _ arguments: [String], cwd: String?, timeout: TimeInterval, token: CancellationToken?) throws -> CommandResult {
        calls.append(arguments)
        func json(_ value: Any) throws -> CommandResult { CommandResult(data: try JSONSerialization.data(withJSONObject: value)) }
        if arguments == ["context", "show"] { return CommandResult(data: Data("default\n".utf8)) }
        if arguments.starts(with: ["context", "inspect"]) { return try json([["Endpoints": ["docker": ["Host": endpoint]]]]) }
        let args = Array(arguments.dropFirst(2))
        if args.starts(with: ["info"]) { return CommandResult(data: Data("27.0".utf8)) }
        if args.starts(with: ["volume", "ls"]) { return try json(["Name": "fixture-data"]) }
        if args.starts(with: ["volume", "inspect"]) { return try json([["Name": "fixture-data", "Driver": "local", "CreatedAt": created, "Mountpoint": "/local/fixture"]]) }
        if args.contains("--filter") { return CommandResult(data: Data((attached ? "container123\n" : "").utf8)) }
        if args.starts(with: ["volume", "rm"]) { removals += 1; return CommandResult(data: Data()) }
        return CommandResult(data: Data())
    }
}
