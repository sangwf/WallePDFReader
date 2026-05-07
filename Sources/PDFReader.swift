import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@main
struct WallePDFReaderApp: App {
    @StateObject private var model = TabsModel()

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in ReadingStore.shared.flush() }
    }

    var body: some Scene {
        // Single window — additional file opens route to the existing window
        // via onOpenURL, so they become new tabs instead of new windows.
        Window("WallePDFReader", id: "main") {
            ContentView()
                .environmentObject(model)
                .onOpenURL { model.open($0) }
                .navigationTitle(model.selectedTab?.url.lastPathComponent ?? "WallePDFReader")
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    if let url = pickPDF() { model.open(url) }
                }
                .keyboardShortcut("o")

                Button("Close Tab") {
                    if let id = model.selectedID { model.close(id) }
                }
                .keyboardShortcut("w")
                .disabled(model.selectedID == nil)
            }
        }
    }
}

func pickPDF() -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pdf]
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
}

struct PDFTab: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}

final class TabsModel: ObservableObject {
    @Published var tabs: [PDFTab] = []
    @Published var selectedID: UUID?

    var selectedTab: PDFTab? { tabs.first { $0.id == selectedID } }

    func open(_ url: URL) {
        if let existing = tabs.first(where: { $0.url == url }) {
            selectedID = existing.id
            return
        }
        let tab = PDFTab(url: url)
        tabs.append(tab)
        selectedID = tab.id
    }

    func close(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if selectedID == id {
            selectedID = tabs.isEmpty ? nil : tabs[min(idx, tabs.count - 1)].id
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: TabsModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.tabs.isEmpty {
                TabBar()
                Divider()
            }

            if let tab = model.selectedTab {
                PDFKitView(url: tab.url)
                    .id(tab.id)
            } else {
                DropZone { if let url = pickPDF() { model.open(url) } }
            }
        }
        .frame(minWidth: 700, minHeight: 700)
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            for u in pdfs { model.open(u) }
            return !pdfs.isEmpty
        }
    }
}

struct TabBar: View {
    @EnvironmentObject var model: TabsModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.tabs) { tab in
                    TabChip(tab: tab, isSelected: tab.id == model.selectedID)
                }

                Button {
                    if let url = pickPDF() { model.open(url) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Open another PDF")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

struct TabChip: View {
    let tab: PDFTab
    let isSelected: Bool
    @EnvironmentObject var model: TabsModel
    @State private var hovering = false
    @State private var hoveringClose = false

    private var title: String {
        tab.url.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            Text(title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .leading)

            Button {
                model.close(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(hoveringClose ? Color.secondary.opacity(0.25) : Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .onHover { hoveringClose = $0 }
            .help("Close tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = tab.id }
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if hovering { return Color.secondary.opacity(0.10) }
        return .clear
    }
}

struct DropZone: View {
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text("Click to choose a PDF")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("or drop one here · ⌘O")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(hovering ? Color.accentColor.opacity(0.08) : Color.clear)
        .onHover { hovering = $0 }
        .onTapGesture { onTap() }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .windowBackgroundColor
        v.document = PDFDocument(url: url)
        context.coordinator.bind(view: v, url: url)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url {
            v.document = PDFDocument(url: url)
            context.coordinator.bind(view: v, url: url)
        }
    }

    static func dismantleNSView(_ v: PDFView, coordinator: Coordinator) {
        coordinator.saveNow()
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        private var url: URL?
        private var observers: [NSObjectProtocol] = []
        private var saveItem: DispatchWorkItem?

        func bind(view: PDFView, url: URL) {
            teardown()
            pdfView = view
            self.url = url

            let center = NotificationCenter.default
            for name: Notification.Name in [.PDFViewVisiblePagesChanged, .PDFViewPageChanged] {
                let token = center.addObserver(forName: name, object: view, queue: .main) { [weak self] _ in
                    self?.scheduleSave()
                }
                observers.append(token)
            }

            // Restore after layout settles so PDFView can scroll to the destination.
            DispatchQueue.main.async { [weak self] in self?.restore() }
        }

        private func restore() {
            guard let view = pdfView, let url, let doc = view.document else { return }
            guard let state = ReadingStore.shared.get(url),
                  state.page >= 0, state.page < doc.pageCount,
                  let page = doc.page(at: state.page) else { return }
            view.go(to: PDFDestination(page: page, at: CGPoint(x: state.x, y: state.y)))
        }

        private func scheduleSave() {
            saveItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.saveNow() }
            saveItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        }

        func saveNow() {
            guard let view = pdfView, let url,
                  let dest = view.currentDestination,
                  let page = dest.page,
                  let idx = view.document?.index(for: page) else { return }
            ReadingStore.shared.set(
                ReadingState(page: idx, x: Double(dest.point.x), y: Double(dest.point.y)),
                for: url
            )
        }

        private func teardown() {
            for token in observers { NotificationCenter.default.removeObserver(token) }
            observers.removeAll()
            saveItem?.cancel()
            saveItem = nil
        }

        deinit { teardown() }
    }
}

// MARK: - Reading state persistence

struct ReadingState: Codable {
    var page: Int
    var x: Double
    var y: Double
}

final class ReadingStore {
    static let shared = ReadingStore()

    private let fileURL: URL
    private var states: [String: ReadingState]
    private var flushItem: DispatchWorkItem?

    private init() {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("WallePDFReader", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("reading-state.json")

        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([String: ReadingState].self, from: data) {
            states = dict
        } else {
            states = [:]
        }
    }

    func get(_ url: URL) -> ReadingState? { states[url.path] }

    func set(_ state: ReadingState, for url: URL) {
        states[url.path] = state
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        flushItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func flush() {
        flushItem?.cancel()
        flushItem = nil
        guard let data = try? JSONEncoder().encode(states) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
