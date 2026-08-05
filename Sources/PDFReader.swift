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
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Capture Region") {
                    NotificationCenter.default.post(name: .captureRegion, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.selectedID == nil)
            }
        }
    }
}

extension Notification.Name {
    static let captureRegion = Notification.Name("WallePDFReader.captureRegion")
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

    func makeNSView(context: Context) -> PDFContainerView {
        let pdf = PDFView()
        pdf.autoScales = true
        pdf.displayMode = .singlePageContinuous
        pdf.displayDirection = .vertical
        pdf.backgroundColor = .windowBackgroundColor
        pdf.document = PDFDocument(url: url)

        let container = PDFContainerView(pdfView: pdf)
        context.coordinator.bind(view: pdf, url: url)
        return container
    }

    func updateNSView(_ container: PDFContainerView, context: Context) {
        let pdf = container.pdfView
        if pdf.document?.documentURL != url {
            pdf.document = PDFDocument(url: url)
            container.resetSlides()
            context.coordinator.bind(view: pdf, url: url)
        }
    }

    static func dismantleNSView(_ container: PDFContainerView, coordinator: Coordinator) {
        coordinator.saveNow()
        container.stopKeyMonitor()
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

// MARK: - Presentation slide layer

/// Blits a pre-rendered page bitmap over the PDF view while presenting.
///
/// PDFKit rasterises a page progressively — a low-resolution proxy goes up first
/// and gets refined on a background queue — which reads as the slide sharpening up
/// after every turn. There is no API to opt out, and pre-rendering through PDFKit
/// buys nothing: re-rendering the same page costs ~90% of the first pass, so no
/// page-level cache exists to warm. Rendering each slide ourselves at exactly the
/// backing resolution and swapping the finished bitmap in is the only way to make
/// a turn land sharp in one frame.
final class SlideView: NSView {
    private var image: CGImage?
    private var pageRect: CGRect = .zero
    var fill: NSColor = .windowBackgroundColor

    // Never take mouse events: scroll-to-turn and text selection belong to the
    // PDF view underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ image: CGImage, in rect: CGRect) {
        self.image = image
        self.pageRect = rect
        isHidden = false
        needsDisplay = true
    }

    /// Step aside and let PDFKit draw — used whenever our bitmap would be stale or
    /// is not ready yet, so the worst case is exactly the old behaviour.
    func stepAside() {
        image = nil
        isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let ctx = NSGraphicsContext.current?.cgContext else { return }
        fill.setFill()
        bounds.fill()
        ctx.interpolationQuality = .high
        ctx.draw(image, in: pageRect)
    }
}

// MARK: - Region capture (screenshot)

final class PDFContainerView: NSView {
    let pdfView: PDFView
    let overlay: ScreenshotOverlayView
    private var observers: [NSObjectProtocol] = []
    private var keyMonitor: Any?

    private let slide = SlideView()
    // Slides render off a private document instance, so a background draw can
    // never touch the one pdfView is rendering from — PDFKit is not thread safe.
    private var slideDoc: PDFDocument?
    private var slideCache: [Int: CGImage] = [:]
    private var slideWork: [Int: DispatchWorkItem] = [:]
    private var slidePixelSize: CGSize = .zero
    private var slideGeneration = 0
    private var switchingMode = false
    private let slideQueue = DispatchQueue(label: "WallePDFReader.slides", qos: .userInitiated)

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        self.overlay = ScreenshotOverlayView()
        super.init(frame: .zero)

        pdfView.autoresizingMask = [.width, .height]
        slide.autoresizingMask = [.width, .height]
        overlay.autoresizingMask = [.width, .height]
        overlay.pdfView = pdfView
        slide.fill = pdfView.backgroundColor
        slide.isHidden = true

        addSubview(pdfView)
        addSubview(slide)
        addSubview(overlay)

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .captureRegion, object: nil, queue: .main
        ) { [weak self] _ in
            self?.overlay.activate()
        })

        for name in [NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            observers.append(center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, let win = note.object as? NSWindow, win === self.window else { return }
                self.syncPresentationMode()
            })
        }

        for name: Notification.Name in [.PDFViewPageChanged, .PDFViewScaleChanged] {
            observers.append(center.addObserver(
                forName: name, object: pdfView, queue: .main
            ) { [weak self] _ in
                self?.updateSlide()
            })
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // Also catches switching tabs while already fullscreen — a fresh container
    // starts in the default mode and has to be brought in line.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncPresentationMode()
        if window != nil { startKeyMonitor() }
    }

    override func layout() {
        super.layout()
        pdfView.frame = bounds
        slide.frame = bounds
        overlay.frame = bounds
        // A resize changes the render size out from under every cached bitmap.
        updateSlide()
    }

    /// Fullscreen is presentation mode: exactly one page on screen, scaled to
    /// fit whole, with no bleed from the neighbouring pages.
    private func syncPresentationMode() {
        let fullScreen = window?.styleMask.contains(.fullScreen) ?? false
        let mode: PDFDisplayMode = fullScreen ? .singlePage : .singlePageContinuous
        guard pdfView.displayMode != mode else { return }

        let page = pdfView.currentPage
        // setDisplayMode lays out synchronously and posts PDFViewScaleChanged from
        // inside, so hold off slide work until the geometry below has settled —
        // otherwise it renders a bitmap sized for the layout we are leaving.
        switchingMode = true
        pdfView.displayMode = mode
        // Re-fit: .singlePage fits the whole page, continuous fits width — but
        // autoScales only recomputes the factor when it is (re)assigned.
        pdfView.autoScales = false
        pdfView.autoScales = true
        if let page { pdfView.go(to: page) }
        switchingMode = false

        updateSlide()
    }

    // MARK: Slides

    /// Called whenever the page, the scale or the view size changes. Puts the
    /// matching bitmap up if we have one, otherwise steps aside and renders it.
    private func updateSlide() {
        guard !switchingMode,
              pdfView.displayMode == .singlePage,
              let doc = pdfView.document,
              let page = pdfView.currentPage
        else { slide.stepAside(); return }

        let index = doc.index(for: page)
        let rect = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
        let backing = window?.backingScaleFactor ?? 2
        let pixel = CGSize(width: (rect.width * backing).rounded(),
                           height: (rect.height * backing).rounded())
        guard pixel.width > 1, pixel.height > 1 else { slide.stepAside(); return }

        // Geometry moved — every cached bitmap is now the wrong size. Bumping the
        // generation also makes in-flight renders land as no-ops.
        if pixel != slidePixelSize {
            slideCache.removeAll()
            // Cancelled work that has not started yet is skipped by Dispatch, so a
            // multi-second page is never rendered at a size nobody wants any more.
            for work in slideWork.values { work.cancel() }
            slideWork.removeAll()
            slidePixelSize = pixel
            slideGeneration += 1
        }

        if let image = slideCache[index] {
            slide.show(image, in: rect)
        } else {
            slide.stepAside()
        }

        // Weighted forwards: presentations run forwards, and a heavy page needs
        // several turns of lead time — some take seconds to rasterise. Holding 3
        // ahead and 1 back keeps the same 5-bitmap ceiling as a symmetric window
        // while doubling that lead. Nearest first, so the page most likely to be
        // needed next is not queued behind a slow one.
        slideCache = slideCache.filter { (-1...3).contains($0.key - index) }
        for target in [index, index + 1, index + 2, index + 3, index - 1] {
            renderSlide(target, pixel: pixel)
        }
    }

    private func renderSlide(_ index: Int, pixel: CGSize) {
        // slideWork deduplicates: a render in flight is not in the cache yet, so
        // without it every updateSlide re-enqueues the same page. Heavy pages take
        // seconds — duplicates pile up on the serial queue and starve the pages
        // actually being turned to, which is when the fallback blur comes back.
        guard slideCache[index] == nil, slideWork[index] == nil,
              let doc = slideDocument(),
              index >= 0, index < doc.pageCount,
              let page = doc.page(at: index)
        else { return }

        let generation = slideGeneration
        let box = pdfView.displayBox
        let work = DispatchWorkItem {
            let image = autoreleasepool { Self.rasterize(page, pixel: pixel, box: box) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.slideWork[index] = nil
                guard let image, generation == self.slideGeneration else { return }
                self.slideCache[index] = image
                // Landed on the page we are looking at — put it up now.
                if let current = self.pdfView.currentPage,
                   self.pdfView.document?.index(for: current) == index,
                   self.pdfView.displayMode == .singlePage {
                    self.slide.show(image, in: self.pdfView.convert(current.bounds(for: box), from: current))
                }
            }
        }
        slideWork[index] = work
        slideQueue.async(execute: work)
    }

    private func slideDocument() -> PDFDocument? {
        if let slideDoc, slideDoc.documentURL == pdfView.document?.documentURL { return slideDoc }
        slideDoc = pdfView.document?.documentURL.flatMap { PDFDocument(url: $0) }
        return slideDoc
    }

    /// Drops every cached bitmap — call when the document behind the view changes.
    func resetSlides() {
        slideDoc = nil
        slideCache.removeAll()
        for work in slideWork.values { work.cancel() }
        slideWork.removeAll()
        slidePixelSize = .zero
        slideGeneration += 1
        slide.stepAside()
        updateSlide()
    }

    private static func rasterize(_ page: PDFPage, pixel: CGSize, box: PDFDisplayBox) -> CGImage? {
        let bounds = page.bounds(for: box)
        guard bounds.width > 0, bounds.height > 0,
              let ctx = CGContext(
                data: nil, width: Int(pixel.width), height: Int(pixel.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: pixel))
        ctx.scaleBy(x: pixel.width / bounds.width, y: pixel.height / bounds.height)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: box, to: ctx)
        return ctx.makeImage()
    }

    // MARK: Keyboard

    // A local monitor rather than keyDown overrides: SwiftUI's hosting view keeps
    // first responder to itself, so neither the PDF view nor the capture overlay
    // ever sees a key event.
    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // Leave menu shortcuts and anything modified to the rest of the app.
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        // Region capture owns the keyboard for as long as it is up.
        if overlay.isCapturing {
            switch event.keyCode {
            case 53:     overlay.deactivate()          // ESC
            case 36, 76: overlay.confirmSelection()    // Return / Enter
            default:     return false
            }
            return true
        }

        // Paging keys are presentation-only; windowed reading is untouched.
        guard pdfView.displayMode == .singlePage else { return false }

        switch event.keyCode {
        case 124, 125, 121, 49, 36:  // → ↓ PageDown Space Return
            if pdfView.canGoToNextPage { pdfView.goToNextPage(nil) }
        case 123, 126, 116, 51:      // ← ↑ PageUp Delete
            if pdfView.canGoToPreviousPage { pdfView.goToPreviousPage(nil) }
        case 115: pdfView.goToFirstPage(nil)   // Home
        case 119: pdfView.goToLastPage(nil)    // End
        case 53:  window?.toggleFullScreen(nil)  // ESC leaves the presentation
        default:  return false
        }
        return true
    }
}

final class ScreenshotOverlayView: NSView {
    weak var pdfView: PDFView?

    private var isActive = false
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var selectionFrozen = false
    private var toolbar: ScreenshotToolbarView?
    private var hint: NSView?
    private var cursorPushed = false

    /// True while region capture owns the keyboard — presentation keys must
    /// stand down so ESC/Return still mean cancel/copy.
    var isCapturing: Bool { isActive }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isActive }

    // Pass mouse events through to PDFView when not in capture mode.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isActive ? super.hitTest(point) : nil
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        dragStart = nil
        dragCurrent = nil
        selectionFrozen = false
        NSCursor.crosshair.push()
        cursorPushed = true
        window?.makeFirstResponder(self)
        installHint()
        needsDisplay = true
    }

    func deactivate() {
        isActive = false
        dragStart = nil
        dragCurrent = nil
        selectionFrozen = false
        // Belt-and-suspenders: also sweep any stragglers from earlier sessions
        for sub in subviews where sub is ScreenshotToolbarView || sub === hint {
            sub.removeFromSuperview()
        }
        toolbar = nil
        hint = nil
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        needsDisplay = true
        displayIfNeeded()  // force the dim/buttons gone in this runloop
    }

    // MARK: Drag

    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        let p = convert(event.locationInWindow, from: nil)

        if selectionFrozen {
            if currentRect.contains(p) {
                // Double-click inside selection → copy & exit (WeChat-style)
                if event.clickCount >= 2 { copyAndExit() }
                return
            } else {
                // Click outside an existing selection → start a fresh drag
                toolbar?.removeFromSuperview()
                toolbar = nil
                selectionFrozen = false
                // fall through to begin a new drag
            }
        }

        dragStart = p
        dragCurrent = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isActive, !selectionFrozen, dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isActive, dragStart != nil, dragCurrent != nil else { return }
        let rect = currentRect
        if rect.width > 4, rect.height > 4 {
            selectionFrozen = true
            showToolbar(near: rect)
        } else {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
    }

    /// Copy the frozen selection and leave capture mode. Driven by the
    /// container's key monitor — see `PDFContainerView.handleKey`.
    func confirmSelection() {
        if selectionFrozen { copyAndExit() }
    }

    // Block scroll while active — selection rect is anchored in view coords,
    // scrolling the PDF underneath would desync it.
    override func scrollWheel(with event: NSEvent) {
        if isActive { return }
        super.scrollWheel(with: event)
    }

    private var currentRect: NSRect {
        guard let s = dragStart, let c = dragCurrent else { return .zero }
        return NSRect(
            x: min(s.x, c.x), y: min(s.y, c.y),
            width: abs(c.x - s.x), height: abs(c.y - s.y)
        ).intersection(bounds)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard isActive, let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        let path = CGMutablePath()
        path.addRect(bounds)
        let sel = currentRect
        if !sel.isEmpty { path.addRect(sel) }
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)

        if !sel.isEmpty {
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(sel)
            // Corner handles
            ctx.setFillColor(NSColor.systemBlue.cgColor)
            let h: CGFloat = 4
            for p in [
                CGPoint(x: sel.minX - h/2, y: sel.minY - h/2),
                CGPoint(x: sel.maxX - h/2, y: sel.minY - h/2),
                CGPoint(x: sel.minX - h/2, y: sel.maxY - h/2),
                CGPoint(x: sel.maxX - h/2, y: sel.maxY - h/2),
            ] {
                ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: h, height: h))
            }
        }
    }

    // MARK: Hint label

    private func installHint() {
        let label = NSTextField(labelWithString: "Drag to select region   ·   ESC to cancel")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.addSubview(label)

        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])

        container.frame.size = label.intrinsicContentSize
        container.frame.size.width += 24
        container.frame.size.height += 12
        container.frame.origin = NSPoint(
            x: (bounds.width - container.frame.width) / 2,
            y: bounds.height - container.frame.height - 16
        )
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        addSubview(container)
        hint = container
    }

    // MARK: Toolbar

    private func showToolbar(near rect: NSRect) {
        hint?.removeFromSuperview()
        hint = nil
        toolbar?.removeFromSuperview()
        toolbar = nil

        let bar = ScreenshotToolbarView()
        bar.onCopy   = { [weak self] in self?.copyAndExit() }
        bar.onSave   = { [weak self] in self?.saveAndExit() }
        bar.onCancel = { [weak self] in self?.deactivate() }
        bar.layoutSubtreeIfNeeded()
        bar.frame.size = bar.fittingSize

        var origin = NSPoint(
            x: rect.midX - bar.frame.width / 2,
            y: rect.minY - bar.frame.height - 10
        )
        if origin.y < 10 { origin.y = rect.maxY + 10 }
        origin.x = max(10, min(origin.x, bounds.width - bar.frame.width - 10))
        bar.setFrameOrigin(origin)
        addSubview(bar)
        toolbar = bar
    }

    // MARK: Rendering

    private func copyAndExit() {
        if let img = renderSelection() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        }
        deactivate()
    }

    private func saveAndExit() {
        guard let img = renderSelection() else { deactivate(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "WallePDF Capture \(stamp).png"
        let window = self.window
        panel.beginSheetModal(for: window ?? NSApp.keyWindow ?? NSWindow()) { response in
            if response == .OK, let url = panel.url,
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
            self.deactivate()
        }
    }

    private func renderSelection() -> NSImage? {
        guard let pdfView, !currentRect.isEmpty else { return nil }

        // 1) Convert overlay rect into PDFView's coordinate space — handles
        //    any y-flip / origin difference between sibling NSViews.
        let rectInPDFView = convert(currentRect, to: pdfView).intersection(pdfView.bounds)
        guard rectInPDFView.width > 1, rectInPDFView.height > 1 else { return nil }

        // 2) Find the page under the selection center.
        let center = NSPoint(x: rectInPDFView.midX, y: rectInPDFView.midY)
        guard let page = pdfView.page(for: center, nearest: true) else { return nil }

        // 3) Convert the rect's corners to page coordinates. PDFKit handles
        //    page rotation and current zoom/scroll for us.
        let cornerA = pdfView.convert(NSPoint(x: rectInPDFView.minX, y: rectInPDFView.minY), to: page)
        let cornerB = pdfView.convert(NSPoint(x: rectInPDFView.maxX, y: rectInPDFView.maxY), to: page)
        let pageBounds = page.bounds(for: .cropBox)
        let pageRect = NSRect(
            x: min(cornerA.x, cornerB.x),
            y: min(cornerA.y, cornerB.y),
            width:  abs(cornerB.x - cornerA.x),
            height: abs(cornerB.y - cornerA.y)
        ).intersection(pageBounds)
        guard pageRect.width > 1, pageRect.height > 1 else { return nil }

        // 4) Render directly from PDF source into a 2× bitmap. Vector quality,
        //    independent of on-screen zoom.
        let scale: CGFloat = 2.0
        let pixelW = Int(ceil(pageRect.width  * scale))
        let pixelH = Int(ceil(pageRect.height * scale))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW, pixelsHigh: pixelH,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        ) else { return nil }
        rep.size = pageRect.size  // logical points

        guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        let ctx = nsCtx.cgContext

        // NSBitmapImageRep already maps logical points → pixels via its
        // size↔pixelsWide ratio (2×). Drawing in user coords therefore renders
        // at the native @2× resolution automatically — no extra scaleBy is
        // needed (and adding one would double-scale).
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: pageRect.size))
        ctx.translateBy(x: -pageRect.minX, y: -pageRect.minY)
        page.draw(with: .cropBox, to: ctx)

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: pageRect.size)
        image.addRepresentation(rep)
        return image
    }
}

final class ScreenshotToolbarView: NSView {
    var onCopy:   (() -> Void)?
    var onSave:   (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.masksToBounds = false

        let copy   = makeButton(title: "Copy",   key: "\r", action: #selector(copyTapped))
        let save   = makeButton(title: "Save…",  key: "",   action: #selector(saveTapped))
        let cancel = makeButton(title: "Cancel", key: "\u{1b}", action: #selector(cancelTapped))

        let stack = NSStackView(views: [copy, save, cancel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(title: String, key: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        if !key.isEmpty { b.keyEquivalent = key }
        return b
    }

    @objc private func copyTapped()   { onCopy?() }
    @objc private func saveTapped()   { onSave?() }
    @objc private func cancelTapped() { onCancel?() }
}
