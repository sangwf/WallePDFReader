import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - Markdown → HTML

/// Converts Markdown to HTML by walking the block structure that Foundation's
/// own CommonMark/GFM parser exposes through `PresentationIntent`. No bundled
/// parser, so the app still builds from plain `swiftc`.
enum MarkdownRenderer {
    static func page(for markdown: String, title: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(css)</style>
        </head><body><article class="markdown-body">
        \(body(for: markdown))
        </article></body></html>
        """
    }

    static func body(for markdown: String) -> String {
        let (text, notes) = extractFootnotes(stripFrontMatter(markdown))
        var html = render(text)
        if !notes.isEmpty {
            html += "<section class=\"footnotes\">\n<hr>\n<ol>\n"
            for (n, note) in notes.enumerated() {
                var item = render(note.content)
                let back = note.referenced
                    ? " <a class=\"footnote-back\" href=\"#fnref-\(n + 1)\">↩</a>" : ""
                if item.hasSuffix("</p>\n") {
                    item.insert(contentsOf: back, at: item.index(item.endIndex, offsetBy: -5))
                } else {
                    item += back
                }
                html += "<li id=\"fn-\(n + 1)\">\(item)</li>\n"
            }
            html += "</ol>\n</section>\n"
        }
        return html
    }

    /// Foundation's parser has no footnote syntax, and worse, reads a
    /// `[^1]: text` line as a link reference definition whenever the text has
    /// no spaces — common in Chinese — so the note silently disappears. Pull
    /// definitions out first and turn references into numbered superscripts,
    /// numbered by first reference like GitHub.
    private static func extractFootnotes(_ text: String) -> (String, [(content: String, referenced: Bool)]) {
        var body: [String] = []
        var definitions: [(label: String, lines: [String])] = []
        var fence: String?
        var inDefinition = false

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let f = fence {
                if trimmed.hasPrefix(f) { fence = nil }
                body.append(line)
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                inDefinition = false
                body.append(line)
                continue
            }

            let ns = line as NSString
            if let m = footnoteDefinition.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                definitions.append((ns.substring(with: m.range(at: 1)),
                                    [ns.substring(from: m.range.location + m.range.length)]))
                inDefinition = true
                continue
            }
            // Indented lines (and the blank lines between them) continue a note.
            if inDefinition {
                if line.hasPrefix("    ") || line.hasPrefix("\t") {
                    definitions[definitions.count - 1].lines.append(
                        line.hasPrefix("\t") ? String(line.dropFirst()) : String(line.dropFirst(4)))
                    continue
                }
                if trimmed.isEmpty {
                    definitions[definitions.count - 1].lines.append("")
                    continue
                }
                inDefinition = false
            }
            body.append(line)
        }
        guard !definitions.isEmpty else { return (text, []) }

        var contentByLabel: [String: String] = [:]
        for d in definitions where contentByLabel[d.label] == nil {
            contentByLabel[d.label] = d.lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var order: [String] = []
        var number: [String: Int] = [:]
        fence = nil
        for i in body.indices {
            let trimmed = body[i].trimmingCharacters(in: .whitespaces)
            if let f = fence {
                if trimmed.hasPrefix(f) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            guard body[i].contains("[^") else { continue }

            let ns = body[i] as NSString
            var result = ""
            var cursor = 0
            for m in footnoteReference.matches(in: body[i], range: NSRange(location: 0, length: ns.length)) {
                let label = ns.substring(with: m.range(at: 1))
                guard contentByLabel[label] != nil else { continue }
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let n: Int
                if let existing = number[label] {
                    n = existing
                    result += "<sup class=\"footnote-ref\"><a href=\"#fn-\(n)\">\(n)</a></sup>"
                } else {
                    order.append(label)
                    n = order.count
                    number[label] = n
                    result += "<sup class=\"footnote-ref\" id=\"fnref-\(n)\"><a href=\"#fn-\(n)\">\(n)</a></sup>"
                }
                cursor = m.range.location + m.range.length
            }
            result += ns.substring(from: cursor)
            body[i] = result
        }

        // Notes nobody references still get shown, after the referenced ones.
        let referenced = order.count
        for d in definitions where number[d.label] == nil {
            order.append(d.label)
            number[d.label] = order.count
        }
        let notes = order.enumerated().map { (contentByLabel[$0.element]!, $0.offset < referenced) }
        return (body.joined(separator: "\n"), notes)
    }

    private static let footnoteDefinition = try! NSRegularExpression(pattern: #"^ {0,3}\[\^([^\]\s]+)\]:[ \t]?"#)
    private static let footnoteReference = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\]"#)

    private static func render(_ markdown: String) -> String {
        let source = preprocess(markdown)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let doc = try? AttributedString(markdown: source, options: options) else {
            return "<pre>\(escape(source))</pre>"
        }

        var html = ""
        // Open blocks, outermost first, each with the markup that closes it.
        // `cellTag` marks a table row, which pads out cells that had no content.
        var open: [(id: Int, close: String, cellTag: String?)] = []
        var cellsInRow = 0
        var columnsInTable = 0
        var atItemStart = false

        func close(from index: Int) {
            for block in open[index...].reversed() {
                if let tag = block.cellTag {
                    while cellsInRow < columnsInTable { html += "<\(tag)></\(tag)>"; cellsInRow += 1 }
                }
                html += block.close
            }
            open.removeSubrange(index...)
        }

        for run in doc.runs {
            let path = Array((run.presentationIntent?.components ?? []).reversed())

            var common = 0
            while common < open.count, common < path.count, open[common].id == path[common].identity {
                common += 1
            }
            close(from: common)

            for i in common..<path.count {
                let block = path[i]
                switch block.kind {
                case .paragraph:
                    html += "<p>"; open.append((block.identity, "</p>\n", nil))
                case .header(let level):
                    html += "<h\(level)>"; open.append((block.identity, "</h\(level)>\n", nil))
                case .blockQuote:
                    html += "<blockquote>\n"; open.append((block.identity, "</blockquote>\n", nil))
                case .orderedList:
                    var start = 1
                    if i + 1 < path.count, case .listItem(let ordinal) = path[i + 1].kind { start = ordinal }
                    html += start == 1 ? "<ol>\n" : "<ol start=\"\(start)\">\n"
                    open.append((block.identity, "</ol>\n", nil))
                case .unorderedList:
                    html += "<ul>\n"; open.append((block.identity, "</ul>\n", nil))
                case .listItem:
                    html += "<li>"; open.append((block.identity, "</li>\n", nil))
                    atItemStart = true
                case .codeBlock(let lang):
                    let cls = lang.map { " class=\"language-\(escape($0))\"" } ?? ""
                    html += "<pre><code\(cls)>"; open.append((block.identity, "</code></pre>\n", nil))
                case .thematicBreak:
                    html += "<hr>\n"; open.append((block.identity, "", nil))
                case .table(let columns):
                    columnsInTable = columns.count
                    html += "<table>\n"; open.append((block.identity, "</table>\n", nil))
                case .tableHeaderRow:
                    cellsInRow = 0
                    html += "<thead><tr>"; open.append((block.identity, "</tr></thead>\n", "th"))
                case .tableRow:
                    cellsInRow = 0
                    html += "<tr>"; open.append((block.identity, "</tr>\n", "td"))
                case .tableCell(let column):
                    let header: Bool
                    if i > 0, case .tableHeaderRow = path[i - 1].kind { header = true } else { header = false }
                    let tag = header ? "th" : "td"
                    var align = ""
                    if i > 1, case .table(let columns) = path[i - 2].kind, column < columns.count {
                        switch columns[column].alignment {
                        case .center: align = " align=\"center\""
                        case .right:  align = " align=\"right\""
                        default:      break
                        }
                    }
                    // Empty cells produce no run at all, so fill any gap ourselves.
                    while cellsInRow < column { html += "<\(tag)></\(tag)>"; cellsInRow += 1 }
                    cellsInRow += 1
                    html += "<\(tag)\(align)>"; open.append((block.identity, "</\(tag)>", nil))
                default:
                    open.append((block.identity, "", nil))
                }
            }

            html += inline(run, text: String(doc[run.range].characters),
                           in: path.last?.kind, atItemStart: &atItemStart)
        }
        close(from: 0)
        return html
    }

    private static func inline(_ run: AttributedString.Runs.Run, text: String,
                               in block: PresentationIntent.Kind?, atItemStart: inout Bool) -> String {
        if case .thematicBreak = block { return "" }
        if case .codeBlock = block { return escape(text) }

        let intent = run.inlinePresentationIntent ?? []
        if intent.contains(.blockHTML) || intent.contains(.inlineHTML) { return text }
        if intent.contains(.softBreak) { return "\n" }
        if intent.contains(.lineBreak) { return "<br>\n" }

        var s: String
        if let image = run.imageURL {
            let alt = text == "\u{FFFC}" ? "" : text
            s = "<img src=\"\(escape(image.relativeString))\" alt=\"\(escape(alt))\">"
        } else {
            s = escape(text)
            if atItemStart {
                for (marker, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where s.hasPrefix(marker) {
                    s = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> " + s.dropFirst(marker.count)
                    break
                }
            }
            if intent.contains(.code) { s = "<code>\(s)</code>" }
            if intent.contains(.strikethrough) { s = "<del>\(s)</del>" }
            if intent.contains(.emphasized) { s = "<em>\(s)</em>" }
            if intent.contains(.stronglyEmphasized) { s = "<strong>\(s)</strong>" }
        }
        atItemStart = false
        if let link = run.link {
            s = "<a href=\"\(escape(link.relativeString))\">\(s)</a>"
        }
        return s
    }

    /// YAML front matter is metadata, not content — GitHub hides it too.
    private static func stripFrontMatter(_ text: String) -> String {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return text }
        let lines = text.components(separatedBy: "\n")
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            return lines[(i + 1)...].joined(separator: "\n")
        }
        return text
    }

    private static let linkedImage = try! NSRegularExpression(
        pattern: #"\[!\[([^\]]*)\]\(\s*<?([^\s)>]+)>?(?:\s+"[^"]*")?\s*\)\]\(\s*<?([^\s)>]+)>?(?:\s+"[^"]*")?\s*\)"#
    )

    /// Foundation's parser drops an image nested inside a link — the usual way
    /// README badges are written — so rewrite those to inline HTML first.
    /// Fenced code is left alone so code samples are shown verbatim.
    private static func preprocess(_ text: String) -> String {
        var out: [String] = []
        var fence: String?
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let f = fence {
                if trimmed.hasPrefix(f) { fence = nil }
                out.append(line)
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                out.append(line)
                continue
            }
            guard line.contains("[![") else { out.append(line); continue }

            let ns = line as NSString
            var result = ""
            var cursor = 0
            for m in linkedImage.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let alt = ns.substring(with: m.range(at: 1))
                let src = ns.substring(with: m.range(at: 2))
                let href = ns.substring(with: m.range(at: 3))
                result += "<a href=\"\(escape(href))\"><img src=\"\(escape(src))\" alt=\"\(escape(alt))\"></a>"
                cursor = m.range.location + m.range.length
            }
            result += ns.substring(from: cursor)
            out.append(result)
        }
        return out.joined(separator: "\n")
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    private static let css = """
    :root {
      color-scheme: light dark;
      --fg: #1f2328; --muted: #59636e; --bg: #ffffff; --border: #d1d9e0;
      --code-bg: #f6f8fa; --link: #0969da; --quote: #59636e; --row-alt: #f6f8fa;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #e6edf3; --muted: #9198a1; --bg: #1e1e1e; --border: #3d444d;
        --code-bg: #2a2a2c; --link: #4493f8; --quote: #9198a1; --row-alt: #252527;
      }
    }
    html { background: var(--bg); }
    body {
      margin: 0; color: var(--fg); background: var(--bg);
      font: 16px/1.6 -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    .markdown-body { max-width: 860px; margin: 0 auto; padding: 32px 40px 80px; word-wrap: break-word; }
    h1, h2, h3, h4, h5, h6 { margin: 1.5em 0 0.6em; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--muted); }
    .markdown-body > :first-child { margin-top: 0; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 16px; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    ul, ol { padding-left: 2em; }
    li + li { margin-top: .25em; }
    li > p { margin: 0; }
    li > ul, li > ol { margin: .25em 0 0; }
    li:has(> p > input[type=checkbox]:first-child) { list-style: none; }
    li > p > input[type=checkbox]:first-child { margin: 0 .35em 0 -1.4em; vertical-align: middle; }
    blockquote { padding: 0 1em; color: var(--quote); border-left: .25em solid var(--border); }
    blockquote > :last-child { margin-bottom: 0; }
    code, pre {
      font: 85%/1.45 ui-monospace, "SF Mono", Menlo, monospace;
    }
    code { padding: .2em .4em; background: var(--code-bg); border-radius: 6px; }
    pre { padding: 16px; overflow: auto; background: var(--code-bg); border-radius: 6px; }
    pre code { padding: 0; background: none; font-size: 100%; }
    hr { height: 2px; margin: 24px 0; border: 0; background: var(--border); }
    table { border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; }
    tr:nth-child(2n) td { background: var(--row-alt); }
    img { max-width: 100%; }
    sup.footnote-ref { font-size: .75em; line-height: 0; }
    sup.footnote-ref a::before { content: "["; } sup.footnote-ref a::after { content: "]"; }
    .footnotes { margin-top: 40px; font-size: .875em; color: var(--muted); }
    .footnotes hr { height: 1px; margin: 0 0 16px; }
    .footnotes ol { padding-left: 1.5em; }
    .footnotes li > p { margin: 0 0 8px; }
    .footnote-back { margin-left: .2em; }
    :target { scroll-margin-top: 24px; }
    kbd {
      padding: 2px 5px; font: 11px ui-monospace, Menlo, monospace;
      border: 1px solid var(--border); border-bottom-width: 2px; border-radius: 6px;
    }
    """
}

// MARK: - Serving local files to the web view

/// Serves `walle-md://local/<absolute path>`: Markdown files come back rendered,
/// anything else (images next to the document) as-is. Pages load from this
/// scheme rather than file:// so relative image paths resolve without granting
/// the web view blanket file access.
final class MarkdownSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "walle-md"

    static func url(for file: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "local"
        components.path = file.path
        return components.url!
    }

    static func fileURL(from url: URL) -> URL {
        URL(fileURLWithPath: url.path)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestURL = task.request.url else { return }
        let file = Self.fileURL(from: requestURL)

        let body: Data
        let mime: String
        if DocumentKind(url: file) == .markdown {
            let html: String
            if let data = try? Data(contentsOf: file) {
                html = MarkdownRenderer.page(for: Self.decode(data), title: file.lastPathComponent)
            } else {
                html = MarkdownRenderer.page(
                    for: "Couldn’t read `\(file.path)`.", title: file.lastPathComponent)
            }
            body = Data(html.utf8)
            mime = "text/html"
        } else {
            guard let data = try? Data(contentsOf: file) else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            body = data
            mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
        }

        task.didReceive(URLResponse(url: requestURL, mimeType: mime,
                                    expectedContentLength: body.count,
                                    textEncodingName: mime == "text/html" ? "utf-8" : nil))
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// UTF-8 first; older Chinese documents are often GB18030.
    private static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return s }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Markdown tab

struct MarkdownView: NSViewRepresentable {
    let url: URL
    let generation: Int
    let onOpen: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(MarkdownSchemeHandler(), forURLScheme: MarkdownSchemeHandler.scheme)
        // Documents may carry raw HTML; never run scripts from it. Our own
        // script lives in a separate content world and is unaffected.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let controller = config.userContentController
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true, in: .defaultClient))
        controller.add(context.coordinator, contentWorld: .defaultClient, name: "scroll")

        let web = WKWebView(frame: .zero, configuration: config)
        // Otherwise a white frame flashes before the first paint in dark mode.
        web.setValue(false, forKey: "drawsBackground")
        web.allowsMagnification = true
        web.navigationDelegate = context.coordinator

        let coordinator = context.coordinator
        coordinator.url = url
        coordinator.generation = generation
        coordinator.onOpen = onOpen
        web.load(URLRequest(url: MarkdownSchemeHandler.url(for: url)))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onOpen = onOpen
        if coordinator.url != url {
            coordinator.url = url
            coordinator.generation = generation
            web.load(URLRequest(url: MarkdownSchemeHandler.url(for: url)))
        } else if coordinator.generation != generation {
            coordinator.generation = generation
            web.reload()
        }
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController
            .removeScriptMessageHandler(forName: "scroll", contentWorld: .defaultClient)
    }

    /// GitHub-style heading anchors so `#section` links work, plus scroll
    /// reporting for the reading-position store.
    private static let script = #"""
    (() => {
      const seen = {};
      for (const h of document.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
        const base = h.textContent.trim().toLowerCase()
          .replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s/g, '-');
        const n = seen[base] = (seen[base] ?? -1) + 1;
        if (!h.id) h.id = n ? `${base}-${n}` : base;
      }
      let timer;
      addEventListener('scroll', () => {
        clearTimeout(timer);
        timer = setTimeout(() => webkit.messageHandlers.scroll.postMessage(scrollY), 150);
      }, { passive: true });
    })();
    """#

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var url: URL?
        var generation = 0
        var onOpen: ((URL) -> Void)?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let url, let y = message.body as? Double else { return }
            ReadingStore.shared.set(ReadingState(page: 0, x: 0, y: y), for: url)
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url, let state = ReadingStore.shared.get(url), state.y > 0 else { return }
            web.evaluateJavaScript("window.scrollTo(0, \(state.y))", in: nil, in: .defaultClient)
        }

        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let target = action.request.url else {
                decisionHandler(.allow)
                return
            }
            guard target.scheme == MarkdownSchemeHandler.scheme else {
                decisionHandler(.cancel)
                NSWorkspace.shared.open(target)
                return
            }

            let file = MarkdownSchemeHandler.fileURL(from: target)
            // Same document: an in-page #anchor jump.
            if file.path == url?.path {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if !FileManager.default.fileExists(atPath: file.path) {
                NSSound.beep()
            } else if DocumentKind(url: file) != nil {
                onOpen?(file)
            } else {
                NSWorkspace.shared.open(file)
            }
        }
    }
}
