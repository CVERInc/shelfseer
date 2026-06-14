import Foundation

// Ingests EPUB3 files — the format shelfseer's sister tool reepub produces from
// the paper you own — into Documents, one per spine item (chapter). This closes
// the reepub → shelfseer loop entirely on-device: nothing leaves the machine,
// no third-party dependency is added. An EPUB is just a ZIP, so we unzip with
// /usr/bin/unzip (the same tool reepub shells to on the producing side), parse
// META-INF/container.xml → the OPF, walk the OPF <spine> in reading order, and
// strip each XHTML content document to plain text.
//
// It conforms to the same `Ingestor` protocol as FileIngestor, so the rest of
// Core (chunk → embed → index → retrieve) needs no changes.

/// Errors thrown when an EPUB can't be read. Surfaced to the user as a clear
/// message rather than crashing the pipeline.
public enum EpubError: Error, CustomStringConvertible {
    case notAFile(URL)
    case unzipFailed(String)
    case missingContainer
    case missingOPF(String)
    case malformedOPF(String)

    public var description: String {
        switch self {
        case .notAFile(let url):
            return "Not a readable EPUB file: \(url.path)"
        case .unzipFailed(let detail):
            return "Could not unzip the EPUB (\(detail))."
        case .missingContainer:
            return "EPUB is missing META-INF/container.xml."
        case .missingOPF(let detail):
            return "EPUB package document (OPF) could not be located: \(detail)."
        case .malformedOPF(let detail):
            return "EPUB package document (OPF) is malformed: \(detail)."
        }
    }
}

/// Reads a single EPUB file into one Document per spine item.
///
/// Because the `Ingestor` protocol is folder-oriented, `ingest(folder:)` walks
/// the folder (recursively) for `.epub` files and ingests each — so an EPUB
/// library drops in behind the same seam the App already uses. To ingest one
/// file directly, call `ingest(epub:)`.
public struct EpubIngestor: Ingestor {
    public init() {}

    /// File extension we recognise as an EPUB.
    public static let epubExtension = "epub"

    /// Ingest every `.epub` under `folder` (recursively). Unreadable books are
    /// skipped (logged to stderr) rather than failing the whole batch.
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
        var epubPaths: [URL] = []
        for case let url as URL in enumerator
        where url.pathExtension.lowercased() == Self.epubExtension {
            epubPaths.append(url)
        }
        // Stable ordering so re-ingests and tests are deterministic.
        epubPaths.sort { $0.path < $1.path }

        for url in epubPaths {
            do {
                documents.append(contentsOf: try ingest(epub: url))
            } catch {
                FileHandle.standardError.write(
                    Data("shelfseer: skipping \(url.lastPathComponent): \(error)\n".utf8))
            }
        }
        return documents
    }

    /// Ingest a single EPUB file into one Document per spine item, in reading
    /// order. The document id is "<epubPath>#<spineIndex>" so passages cite the
    /// exact chapter; the title comes from the XHTML <title>/<h1>, falling back
    /// to the book filename plus chapter number.
    public func ingest(epub url: URL) throws -> [Document] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              !isDir.boolValue else {
            throw EpubError.notAFile(url)
        }

        let workDir = try Self.unzip(url)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let opfURL = try Self.locateOPF(in: workDir)
        let opfData = try Data(contentsOf: opfURL)
        let spine = try Self.parseOPF(opfData, opfURL: opfURL)

        let bookStem = url.deletingPathExtension().lastPathComponent
        var documents: [Document] = []
        for (i, href) in spine.enumerated() {
            let contentURL = opfURL.deletingLastPathComponent()
                .appendingPathComponent(href).standardizedFileURL
            guard let xhtml = try? String(contentsOf: contentURL, encoding: .utf8) else {
                continue
            }
            let parsed = Self.xhtmlToText(xhtml)
            let body = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let title = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let chapterTitle = (title?.isEmpty == false) ? title! : "\(bookStem) — \(i + 1)"
            documents.append(Document(
                id: "\(url.path)#\(i)",
                title: chapterTitle,
                text: body
            ))
        }
        return documents
    }

    // MARK: - Unzip

    /// Unzip `epub` into a fresh temp directory and return that directory.
    /// Uses /usr/bin/unzip so we add no SPM dependency (ZIPFoundation et al.).
    static func unzip(_ epub: URL) throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelfseer-epub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // -o overwrite, -qq quiet, -d destination.
        process.arguments = ["-o", "-qq", epub.path, "-d", temp.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw EpubError.unzipFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        // unzip exit code 1 is "warning" (some files skipped) — tolerate it.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            try? FileManager.default.removeItem(at: temp)
            throw EpubError.unzipFailed(detail.isEmpty ? "exit \(process.terminationStatus)" : detail)
        }
        return temp
    }

    // MARK: - OPF discovery + spine parsing

    /// Read META-INF/container.xml and resolve the OPF package document's URL.
    static func locateOPF(in root: URL) throws -> URL {
        let containerURL = root
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        guard let data = try? Data(contentsOf: containerURL) else {
            throw EpubError.missingContainer
        }
        guard let fullPath = ContainerParser.opfPath(from: data) else {
            throw EpubError.missingOPF("no rootfile full-path in container.xml")
        }
        let opfURL = root.appendingPathComponent(fullPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: opfURL.path) else {
            throw EpubError.missingOPF("rootfile \(fullPath) not found")
        }
        return opfURL
    }

    /// Parse an OPF package document into an ordered list of content hrefs (the
    /// spine), resolved from `<spine>` idrefs through the `<manifest>`.
    /// Returned hrefs are relative to the OPF's directory.
    public static func parseOPF(_ data: Data, opfURL: URL) throws -> [String] {
        let parser = OPFParser()
        guard parser.parse(data) else {
            throw EpubError.malformedOPF("XML parse failed")
        }
        var hrefs: [String] = []
        for idref in parser.spineOrder {
            if let href = parser.manifest[idref] {
                hrefs.append(href)
            }
        }
        guard !hrefs.isEmpty else {
            throw EpubError.malformedOPF("spine is empty or references unknown manifest items")
        }
        return hrefs
    }

    // MARK: - XHTML → plain text

    /// Strip XHTML to plain text, preserving paragraph breaks (so the paragraph
    /// chunker downstream still has boundaries to split on) and extracting a
    /// title from <title> or the first heading. Lightweight and on the calling
    /// thread — no NSAttributedString(html:), which is heavy and main-thread-fussy.
    public static func xhtmlToText(_ xhtml: String) -> (title: String?, text: String) {
        let stripper = XHTMLTextExtractor()
        stripper.parse(xhtml)
        if !stripper.parsedOK {
            // Fall back to a regex-free tag strip for non-well-formed XHTML.
            return (regexlessTitle(xhtml), stripTags(xhtml))
        }
        return (stripper.title ?? stripper.firstHeading, stripper.text)
    }

    /// Crude tag strip used only when XMLParser rejects the document. Replaces
    /// block-level closers with blank lines so paragraphs survive.
    static func stripTags(_ html: String) -> String {
        var s = html
        for block in ["</p>", "</div>", "</h1>", "</h2>", "</h3>", "</h4>", "</li>", "<br>", "<br/>", "<br />"] {
            s = s.replacingOccurrences(of: block, with: "\n\n", options: .caseInsensitive)
        }
        var out = ""
        var inTag = false
        for ch in s {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { out.append(ch) }
        }
        return Self.collapseBlankLines(decodeEntities(out))
    }

    static func regexlessTitle(_ html: String) -> String? {
        guard let open = html.range(of: "<title>", options: .caseInsensitive),
              let close = html.range(of: "</title>", options: .caseInsensitive),
              open.upperBound <= close.lowerBound else { return nil }
        let raw = String(html[open.upperBound..<close.lowerBound])
        let t = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Collapse runs of 3+ newlines down to a paragraph break, and trim trailing
    /// whitespace on each line.
    static func collapseBlankLines(_ s: String) -> String {
        let lines = s.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        var blanks = 0
        for line in lines {
            if line.isEmpty {
                blanks += 1
                if blanks <= 1 { out.append("") }
            } else {
                blanks = 0
                out.append(line)
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode the handful of XML/HTML entities a stripped document is likely to
    /// carry. (XMLParser already decodes entities in element text; this is for
    /// the regex-free fallback path.)
    static func decodeEntities(_ s: String) -> String {
        var r = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                   "&apos;": "'", "&#39;": "'", "&nbsp;": " "]
        for (k, v) in map { r = r.replacingOccurrences(of: k, with: v) }
        return r
    }
}

// MARK: - container.xml parser

/// Minimal XMLParser delegate that pulls the OPF path out of container.xml:
/// <rootfiles><rootfile full-path="OEBPS/content.opf" .../></rootfiles>.
private final class ContainerParser: NSObject, XMLParserDelegate {
    private var path: String?

    static func opfPath(from data: Data) -> String? {
        let c = ContainerParser()
        let parser = XMLParser(data: data)
        parser.delegate = c
        parser.parse()
        return c.path
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        if path == nil, elementName.lowercased() == "rootfile",
           let full = attributeDict["full-path"], !full.isEmpty {
            path = full
        }
    }
}

// MARK: - OPF parser

/// XMLParser delegate that records the manifest (id → href) and the spine
/// order (list of idrefs) from an OPF package document.
private final class OPFParser: NSObject, XMLParserDelegate {
    var manifest: [String: String] = [:]
    var spineOrder: [String] = []
    private var ok = true

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        let result = parser.parse()
        return result && ok
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attr: [String: String]) {
        switch elementName.lowercased() {
        case "item":
            // A manifest entry: id + href (+ media-type). We keep them all; the
            // spine decides which are reading-order content.
            if let id = attr["id"], let href = attr["href"], !href.isEmpty {
                manifest[id] = href.removingPercentEncoding ?? href
            }
        case "itemref":
            // A spine entry. linear="no" items are auxiliary (e.g. notes pages);
            // skip them so the reading order stays clean.
            if let idref = attr["idref"], attr["linear"]?.lowercased() != "no" {
                spineOrder.append(idref)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        ok = false
    }
}

// MARK: - XHTML text extractor

/// XMLParser delegate that flattens an XHTML content document into plain text.
/// Skips <script>/<style> bodies, inserts blank lines around block elements so
/// paragraph boundaries survive for the chunker, and captures <title> and the
/// first heading for use as a chapter title.
private final class XHTMLTextExtractor: NSObject, XMLParserDelegate {
    private(set) var title: String?
    private(set) var firstHeading: String?
    private(set) var parsedOK = false

    private var buffer = ""
    private var skipDepth = 0          // inside <script>/<style>
    private var inTitle = false
    private var captureHeading = false
    private var headingBuffer = ""

    private static let blockElements: Set<String> = [
        "p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6",
        "section", "article", "blockquote", "tr", "header", "footer",
    ]
    private static let skipElements: Set<String> = ["script", "style"]
    private static let headingElements: Set<String> = ["h1", "h2", "h3"]

    var text: String { EpubIngestor.collapseBlankLines(buffer) }

    func parse(_ xhtml: String) {
        // XMLParser wants UTF-8 data; XHTML is XML so it should parse cleanly.
        guard let data = xhtml.data(using: .utf8) else { return }
        let parser = XMLParser(data: data)
        // Tolerate XHTML that declares HTML entities (&nbsp; etc.).
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        parsedOK = parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let name = elementName.lowercased()
        if Self.skipElements.contains(name) { skipDepth += 1; return }
        if name == "title" { inTitle = true; return }
        if Self.headingElements.contains(name), firstHeading == nil {
            captureHeading = true
            headingBuffer = ""
        }
        if Self.blockElements.contains(name), !buffer.isEmpty {
            buffer += "\n\n"
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if Self.skipElements.contains(name) { skipDepth = max(0, skipDepth - 1); return }
        if name == "title" { inTitle = false; return }
        if Self.headingElements.contains(name), captureHeading {
            captureHeading = false
            let h = headingBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if firstHeading == nil, !h.isEmpty { firstHeading = h }
        }
        if Self.blockElements.contains(name) { buffer += "\n\n" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipDepth > 0 { return }
        if inTitle {
            let t = (title ?? "") + string
            title = t
            return
        }
        if captureHeading { headingBuffer += string }
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        // Ignore CDATA (usually script/style); never content text.
    }
}
