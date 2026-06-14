import SwiftUI
import AppKit
import Signet
import ShelfseerCore

struct ContentView: View {
    @StateObject private var model = LibraryModel()
    @Environment(\.cverTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: CVERSpacing.lg) {
            header
            libraryBar
            askBar
            Divider().overlay(theme.border)
            resultArea
        }
        .padding(CVERSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.ground)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: CVERSpacing.md) {
            Text("shelfseer").cverWordmark(size: 26)
            Text("talk to the library you already own — 100% offline")
                .font(.callout)
                .foregroundStyle(theme.textDim)
            Spacer()
        }
    }

    // MARK: Library picker + index status

    private var libraryBar: some View {
        HStack(spacing: CVERSpacing.md) {
            Button("Choose library folder…") { chooseFolder() }
                .buttonStyle(.cver())
                .disabled(model.isIndexing)

            statusLabel
            Spacer()
        }
        .padding(CVERSpacing.md)
        .liquidGlassCard()
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch model.phase {
        case .empty:
            Text("No library yet. Choose a folder of .txt / .md files.")
                .foregroundStyle(theme.textDim)
        case let .indexing(done, total):
            HStack(spacing: CVERSpacing.sm) {
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    .frame(width: 160)
                Text(total > 0 ? "Indexing \(done)/\(total) passages…" : "Reading folder…")
                    .foregroundStyle(theme.textDim)
            }
        case let .ready(documents, passages):
            Label("\(model.folderName) · \(documents) docs · \(passages) passages",
                  systemImage: "books.vertical.fill")
                .foregroundStyle(theme.positive)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
        }
    }

    // MARK: Question input

    private var askBar: some View {
        HStack(spacing: CVERSpacing.md) {
            TextField("Ask your library a question…", text: $model.question)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(theme.text)
                .padding(CVERSpacing.md)
                .cverPanel(cornerRadius: CVERRadius.control)
                .onSubmit { if model.canAsk { model.ask() } }

            Button("Ask") { model.ask() }
                .buttonStyle(.cver())
                .disabled(!model.canAsk || model.isAnswering)
        }
    }

    // MARK: Answer + sources

    private var resultArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CVERSpacing.lg) {
                if model.isAnswering {
                    HStack(spacing: CVERSpacing.sm) {
                        ProgressView()
                        Text("Searching your library…").foregroundStyle(theme.textDim)
                    }
                } else if let answer = model.answer {
                    answerView(answer)
                } else {
                    CVERGate(
                        wordmark: "shelfseer",
                        message: "Choose a folder of your own documents, then ask a question. Answers are grounded in your texts and never leave this Mac."
                    )
                    .frame(minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func answerView(_ answer: Answer) -> some View {
        VStack(alignment: .leading, spacing: CVERSpacing.lg) {
            Text("Answer")
                .font(.headline)
                .foregroundStyle(theme.highlight)
            Text(answer.text)
                .font(.body)
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
                .padding(CVERSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cverPanel()

            if !answer.sources.isEmpty {
                Text("Sources")
                    .font(.headline)
                    .foregroundStyle(theme.highlight)
                ForEach(answer.sources) { source in
                    sourceRow(source)
                }
            }
        }
    }

    private func sourceRow(_ source: ScoredPassage) -> some View {
        VStack(alignment: .leading, spacing: CVERSpacing.xs) {
            HStack {
                Text(source.passage.documentTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Text(String(format: "%.0f%% match", max(0, source.score) * 100))
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textDim)
            }
            Text(source.passage.text)
                .font(.callout)
                .foregroundStyle(theme.textDim)
                .lineLimit(6)
                .textSelection(.enabled)
        }
        .padding(CVERSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }

    // MARK: Folder picker

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Library"
        if panel.runModal() == .OK, let url = panel.url {
            model.openLibrary(at: url)
        }
    }
}
