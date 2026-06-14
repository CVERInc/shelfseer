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

    // TODO(EPUB seam): shelfseer's sister tool reepub produces EPUB3 from the
    // paper you own. The natural next ingestion source is those EPUBs: unzip the
    // container, parse the OPF spine, strip XHTML to plain text, and emit one
    // Document per chapter (id = "<epubPath>#<spineIndex>", title = chapter
    // title). It plugs in here behind the same `Ingestor` protocol — Core needs
    // no other changes. Kept out of this scaffold to avoid an unzip/XML dep now.

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
                title: url.deletingPathExtension().lastPathComponent,
                text: text
            ))
        }
        // Stable ordering so re-ingests and tests are deterministic.
        documents.sort { $0.id < $1.id }
        return documents
    }
}
