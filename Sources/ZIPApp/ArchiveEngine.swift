import Foundation

struct ArchiveEntry: Identifiable, Hashable, Sendable {
    let path: String
    let isDirectory: Bool
    let size: Int64?
    var id: String { path }
}

struct ArchiveNode: Identifiable, Hashable, Sendable {
    let entry: ArchiveEntry
    let children: [ArchiveNode]?
    var id: String { entry.id }
}

enum ArchiveTree {
    static func make(_ entries: [ArchiveEntry]) -> [ArchiveNode] {
        let entriesByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        var paths = Set(entries.map(\.path))
        for entry in entries {
            var parent = parentPath(of: entry.path)
            while let current = parent {
                paths.insert(current)
                parent = parentPath(of: current)
            }
        }

        func node(for path: String) -> ArchiveNode {
            let childPaths = paths.filter { parentPath(of: $0) == path }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let entry = entriesByPath[path] ?? ArchiveEntry(path: path, isDirectory: true, size: nil)
            let children = childPaths.map(node(for:))
            return ArchiveNode(entry: entry, children: children.isEmpty ? nil : children)
        }

        return paths.filter { parentPath(of: $0) == nil }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map(node(for:))
    }

    private static func parentPath(of path: String) -> String? {
        guard let slash = path.lastIndex(of: "/") else { return nil }
        return String(path[..<slash])
    }
}

enum ArchiveError: LocalizedError, Sendable {
    case engineNotFound
    case commandFailed(String)
    case unsafePath(String)
    case passwordRequired

    var errorDescription: String? {
        switch self {
        case .engineNotFound: L("engine.notFound")
        case .commandFailed(let message): message
        case .unsafePath(let path): String(format: L("unsafe.path"), path)
        case .passwordRequired: L("password.required")
        }
    }
}

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

enum ArchivePath {
    static func isSafe(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.hasPrefix("\\") &&
            !value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..")
    }
}

enum ArchiveVolume {
    static func isFirstPart(_ url: URL) -> Bool {
        let part = url.pathExtension
        guard part.count == 3, Int(part) == 1 else { return false }
        let archiveName = url.deletingPathExtension().lastPathComponent.lowercased()
        return archiveName.hasSuffix(".7z") || archiveName.hasSuffix(".zip") || archiveName.hasSuffix(".rar")
    }
}

final class ArchiveOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func attach(_ process: Process) {
        lock.withLock {
            self.process = process
            if cancelled { process.terminate() }
        }
    }

    func finish(_ process: Process) {
        lock.withLock {
            if self.process === process { self.process = nil }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            process?.terminate()
        }
    }
}

struct ArchiveEngine: Sendable {
    static let shared = ArchiveEngine()
    private let candidates = [
        Bundle.main.resourceURL?.appending(path: "ThirdParty/7-Zip/7zz").path,
        "/opt/homebrew/opt/sevenzip/bin/7zz",
        "/usr/local/bin/7zz",
        "/usr/bin/7zz"
    ].compactMap { $0 }

    func list(_ archive: URL, password: String? = nil, operation: ArchiveOperation? = nil) throws -> [ArchiveEntry] {
        let result = try run(["l", "-slt"] + passwordSwitch(password) + [archive.path], operation: operation)
        var fields: [String: String] = [:]
        var entries: [ArchiveEntry] = []

        func flush() {
            guard let path = fields["Path"], ArchivePath.isSafe(path), fields["Type"] == nil else {
                fields.removeAll(); return
            }
            let isDirectory = fields["Folder"] == "+"
            let size = fields["Size"].flatMap(Int64.init)
            entries.append(ArchiveEntry(path: path, isDirectory: isDirectory, size: size))
            fields.removeAll()
        }

        for line in result.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { flush(); continue }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        flush()
        return entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func extract(_ paths: [String], from archive: URL, to destination: URL, password: String? = nil, operation: ArchiveOperation? = nil) throws {
        for path in paths where !ArchivePath.isSafe(path) { throw ArchiveError.unsafePath(path) }
        guard !paths.isEmpty else { return }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try run(["x", "-aos"] + passwordSwitch(password) + [archive.path, "-o\(destination.path)", "--"] + paths, operation: operation)
    }

    private func passwordSwitch(_ password: String?) -> [String] {
        // An explicit empty password keeps 7zz from presenting its own prompt.
        // ZIP can then show the native password sheet instead.
        let value = password ?? ""
        return ["-p\(value)"]
    }

    private func run(_ arguments: [String], operation: ArchiveOperation?) throws -> String {
        if operation?.isCancelled == true { throw CancellationError() }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ArchiveError.engineNotFound
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        operation?.attach(process)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        operation?.finish(process)
        if operation?.isCancelled == true { throw CancellationError() }
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let lowercased = text.lowercased()
            if lowercased.contains("wrong password") || lowercased.contains("encrypted archive") {
                throw ArchiveError.passwordRequired
            }
            throw ArchiveError.commandFailed(text)
        }
        return text
    }
}
