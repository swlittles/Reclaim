import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CryptoKit

func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "ReclaimReleaseVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
final class EnclosureParser: NSObject, XMLParserDelegate {
    var enclosure: [String: String]?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "enclosure" { enclosure = attributeDict }
    }
}
do {
    let args = CommandLine.arguments
    try require(args.count == 4, "Usage: verify-update.swift PUBLIC_KEY_FILE APPCAST_XML DMG")
    let keyText = try String(contentsOfFile: args[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keyData = Data(base64Encoded: keyText) else { throw NSError(domain: "Invalid public key", code: 1) }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let feed = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    guard let start = feed.range(of: prefix, options: .backwards), let end = feed.range(of: Data("-->".utf8), in: start.upperBound..<feed.endIndex) else { throw NSError(domain: "Missing signed-feed block", code: 1) }
    let body = Data(feed[..<start.lowerBound])
    let signingBlock = String(decoding: feed[start.upperBound..<end.lowerBound], as: UTF8.self)
    var values: [String: String] = [:]
    for line in signingBlock.split(separator: "\n") {
        let parts = line.split(separator: ":", maxSplits: 1)
        if parts.count == 2 { values[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
    }
    guard let signature = Data(base64Encoded: values["edSignature"] ?? "") else { throw NSError(domain: "Missing feed signature", code: 1) }
    try require(Int(values["length"] ?? "") == body.count, "Signed feed length does not match")
    try require(key.isValidSignature(signature, for: body), "Feed signature verification failed")
    let delegate = EnclosureParser(), parser = XMLParser(data: body)
    parser.delegate = delegate
    try require(parser.parse(), "Appcast XML is malformed")
    guard let enclosure = delegate.enclosure, let archiveSignature = Data(base64Encoded: enclosure["sparkle:edSignature"] ?? "") else { throw NSError(domain: "Missing archive signature", code: 1) }
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
    try require(Int(enclosure["length"] ?? "") == archive.count, "Archive length does not match")
    try require(key.isValidSignature(archiveSignature, for: archive), "Archive signature verification failed")
    print("Verified appcast and archive Ed25519 signatures using only Reclaim's committed public key.")
} catch { fputs("Verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
