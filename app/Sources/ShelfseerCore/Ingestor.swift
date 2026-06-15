import Foundation

// Reads a folder of the user's own text into Documents. Today it handles plain
// text and markdown; everything else is skipped. The pipeline never reaches out
// to the network — it only reads files the user pointed it at.

public protocol Ingestor {
    /// Read all supported files under `folder` (recursively) into Documents.
    func ingest(folder: URL) throws -> [Document]
}

public struct FileIngestor: Ingestor {
    /// File extensions we read as plain text today.
    public static let textExtensions: Set<String> = ["txt", "md", "markdown", "text"]

    // EPUB ingestion now lives in EpubIngestor (see EpubIngestor.swift): it
    // unzips the container, parses the OPF spine, strips XHTML to plain text and
    // emits one Document per chapter behind this same `Ingestor` protocol —
    // dependency-free (it shells to /usr/bin/unzip, mirroring reepub's own zip).

    public init() {}

    public func ingest(folder: URL) throws -> [Document] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var documents: [Document] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard Self.textExtensions.contains(ext) else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            documents.append(Document(
                id: url.path,
                title: Self.title(for: url),
                text: text
            ))
        }
        // Stable ordering so re-ingests and tests are deterministic.
        documents.sort { $0.id < $1.id }
        return documents
    }

    /// A human-readable title for a file. Uses the file stem, but degrades
    /// gracefully on edge cases the naive `deletingPathExtension().lastPathComponent`
    /// gets wrong: a dotfile like `.md` (whose stem is empty) keeps its full
    /// name; an extensionless file keeps its name; trailing slashes are ignored.
    public static func title(for url: URL) -> String {
        let full = url.standardizedFileURL.lastPathComponent          // e.g. "notes.md", ".md", "README"
        let stem = url.deletingPathExtension().lastPathComponent      // e.g. "notes", "",   "README"
        let trimmedStem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStem.isEmpty { return trimmedStem }
        // Stem is empty (e.g. a dotfile ".md") — fall back to the full name,
        // then to the path, so a Document always carries a non-empty title.
        let trimmedFull = full.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFull.isEmpty ? url.path : trimmedFull
    }
}
