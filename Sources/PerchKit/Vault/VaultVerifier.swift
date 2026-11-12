import Foundation

/// Checks that Perch can read a whole vault without losing anything. It never writes.
public struct VerificationReport: Sendable {
    public struct Issue: Sendable {
        public var path: String
        public var problem: String
    }

    public var counts: [VaultFileKind: Int] = [:]
    public var totalBytes = 0
    public var wikiLinks = 0
    public var unresolvedLinks: [(source: String, target: String)] = []
    public var conflictFiles: [String] = []
    /// Boards NotesHub itself would reformat or trim on its next save.
    public var boardsWithDroppableLines: [(path: String, count: Int)] = []
    public var boardsNotCanonical: [String] = []
    /// Would break the guarantee: Perch must not change these.
    public var failures: [Issue] = []
    /// Files that aren't UTF-8 text, which Perch leaves untouched.
    public var binaryMarkdown: [String] = []
    public var existingTaskFolders: [String] = []

    public var passed: Bool { failures.isEmpty }
}

public enum VaultVerifier {
    public static func verify(_ vault: Vault) throws -> VerificationReport {
        var report = VerificationReport()
        let files = try vault.scan()
        var entries: [(file: VaultFile, text: String?)] = []

        for file in files {
            report.counts[file.kind, default: 0] += 1
            guard let data = try? vault.readData(file.path) else {
                report.failures.append(.init(path: file.path, problem: "can't be read"))
                entries.append((file, nil))
                continue
            }
            report.totalBytes += data.count

            switch file.kind {
            case .note, .task, .board:
                guard let text = String(data: data, encoding: .utf8) else {
                    report.binaryMarkdown.append(file.path)
                    entries.append((file, nil))
                    continue
                }
                entries.append((file, text))
                // Splitting and rejoining must give back identical bytes.
                if Data(MarkdownDocument(text: text).text.utf8) != data {
                    report.failures.append(.init(path: file.path, problem: "frontmatter split changed bytes"))
                }
                if text.contains(":::conflict{") || text.contains("\n<<<<<<< ") { report.conflictFiles.append(file.path) }
                if file.kind == .board {
                    let parsed = KanbanCodec.parse(text)
                    if !parsed.droppedLines.isEmpty {
                        report.boardsWithDroppableLines.append((file.path, parsed.droppedLines.count))
                    }
                    let once = KanbanCodec.serialize(parsed.board)
                    if once != text { report.boardsNotCanonical.append(file.path) }
                    // Saving twice must be stable, like NotesHub's own output.
                    if KanbanCodec.serialize(KanbanCodec.parse(once).board) != once {
                        report.failures.append(.init(path: file.path, problem: "board save is not stable"))
                    }
                }
                if file.kind == .task, MarkdownDocument(text: text).fields["id"] != nil {
                    do {
                        let task = try TaskCodec.decode(path: file.path, text: text)
                        let reencoded = TaskCodec.encode(task)
                        let again = try TaskCodec.decode(path: file.path, text: reencoded)
                        if again != task { report.failures.append(.init(path: file.path, problem: "task didn't round-trip")) }
                    } catch {
                        report.failures.append(.init(path: file.path, problem: "invalid task file: \(error)"))
                    }
                } else if file.kind == .task {
                    report.existingTaskFolders.append(file.folder)
                }
            case .whiteboard:
                entries.append((file, nil))
                let text = String(decoding: data, as: UTF8.self)
                do {
                    let scene = try WhiteboardCodec.sceneJSON(fromFileNamed: file.name, text: text)
                    _ = WhiteboardCodec.elementCount(sceneJSON: scene)
                } catch {
                    report.failures.append(.init(path: file.path, problem: "whiteboard scene unreadable: \(error)"))
                }
            default:
                entries.append((file, nil))
            }
        }

        let index = LinkIndex(entries: entries)
        for (file, text) in entries {
            guard let text else { continue }
            for link in WikiLinks.parse(text) {
                report.wikiLinks += 1
                if case .missing = index.resolve(link.target, from: file.path) {
                    report.unresolvedLinks.append((file.path, link.target))
                }
            }
        }
        report.existingTaskFolders = Array(Set(report.existingTaskFolders)).sorted()
        return report
    }
}
