//
//  CodeView.swift
//  Glance
//

import AppKit
import Observation
import SwiftUI

/// Where the code view is scrolled, in lines, so the minimap can follow it and scroll it.
@Observable
final class EditorScroll {
    /// The fractional lines at the top and bottom of the visible area, counted from 0.
    var top: Double = 0
    var bottom: Double = 0
    /// Scrolls the code view so this fractional line is at the top.
    @ObservationIgnored var scrollTo: (Double) -> Void = { _ in }

    var visibleLines: Double { bottom - top }
}

/// The read-only source view: a text view, so a selection can span lines and copy with ⌘C,
/// with a gutter of line numbers and change bars. Right-click copies the path with the selected lines.
struct CodeView: NSViewRepresentable {
    let path: String
    let content: FileContent
    let language: SourceLanguage
    let files: FilesModel
    let scroll: EditorScroll
    let copy: (String) -> Void
    @Environment(\.glanceAccent) private var accent

    func makeCoordinator() -> Coordinator {
        Coordinator(files: files, scroll: scroll)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CodeTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(Palette.window)
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        // Lines wrap short of the view's width, which `CodeTextView` keeps the container at.
        textView.textContainer?.widthTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: 1_000_000, height: 1_000_000_000)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(Palette.window)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView
        scrollView.verticalRulerView = LineNumberRuler(scrollView: scrollView, textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.observe(scrollView)
        textView.copyPath = { [weak coordinator = context.coordinator] includingLines in
            coordinator?.copyPath(includingLines: includingLines)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.files = files
        coordinator.copy = copy
        coordinator.scroll = scroll
        guard let textView = coordinator.textView else { return }
        textView.selectedTextAttributes = [.backgroundColor: NSColor(accent.opacity(0.22))]

        if coordinator.path != path {
            coordinator.load(path, content: content, language: language)
        } else if coordinator.content != content {
            // The file changed on disk, or its changes did.
            coordinator.reload(content, language: language)
        } else if files.selectedLines != coordinator.reportedLines {
            // The model moved the selection itself, e.g. by reopening the file.
            textView.moveCaret(toLine: files.currentLine)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var files: FilesModel
        var copy: (String) -> Void = { _ in }
        weak var textView: CodeTextView?
        private(set) var path: String?
        private(set) var content: FileContent?
        /// The lines last written to the model, so selection changes that come from the model can be told apart.
        private(set) var reportedLines: ClosedRange<Int>?

        var scroll: EditorScroll {
            didSet { if scroll !== oldValue { connect() } }
        }

        init(files: FilesModel, scroll: EditorScroll) {
            self.files = files
            self.scroll = scroll
            super.init()
            connect()
        }

        private func connect() {
            scroll.scrollTo = { [weak self] line in self?.scroll(toLine: line) }
            reportScroll()
        }

        func observe(_ scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(reportScroll),
                name: NSView.boundsDidChangeNotification, object: scrollView.contentView
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(textViewDidResize),
                name: NSView.frameDidChangeNotification, object: scrollView.documentView
            )
        }

        private var isReporting = false
        private var isReportPending = false

        /// Measuring lines lays text out, which resizes the text view, so a resize reports once layout has finished.
        @objc private func textViewDidResize() {
            guard !isReportPending else { return }
            isReportPending = true
            DispatchQueue.main.async { [weak self] in
                self?.isReportPending = false
                self?.reportScroll()
            }
        }

        /// Tells the minimap which lines are showing.
        @objc func reportScroll() {
            guard !isReporting, let textView, let visible = textView.enclosingScrollView?.contentView.bounds else { return }
            isReporting = true
            defer { isReporting = false }
            let top = textView.fractionalLine(at: visible.minY)
            let bottom = textView.fractionalLine(at: visible.maxY)
            if scroll.top != top { scroll.top = top }
            if scroll.bottom != bottom { scroll.bottom = bottom }
        }

        private func scroll(toLine line: Double) {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let clip = scrollView.contentView
            let maxY = max(0, textView.frame.height - clip.bounds.height)
            let y = line <= 0 ? 0 : min(max(textView.y(ofFractionalLine: line), 0), maxY)
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
            scrollView.reflectScrolledClipView(clip)
        }

        func load(_ path: String, content: FileContent, language: SourceLanguage) {
            guard let textView else { return }
            // Read the line first: replacing the text reports a selection of its own.
            let line = files.currentLine
            self.path = path
            self.content = content
            textView.show(content, as: language)
            textView.scroll(.zero)
            textView.moveCaret(toLine: line)
            reportScroll()
        }

        /// Shows the same file's new contents where the old ones were, keeping the scroll position and selection.
        func reload(_ content: FileContent, language: SourceLanguage) {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let origin = scrollView.contentView.bounds.origin
            let selection = textView.selectedRange()
            self.content = content
            textView.show(content, as: language)
            if let container = textView.textContainer { textView.layoutManager?.ensureLayout(for: container) }
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let length = (textView.string as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            scrollView.verticalRulerView?.needsDisplay = true
            reportScroll()
        }

        func copyPath(includingLines: Bool) {
            guard let path = files.activePath else { return }
            copy(includingLines ? files.activeReference ?? path : path)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            textView.needsDisplay = true
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true

            let lines = textView.selectedLines
            reportedLines = lines
            if files.selectedLines != lines { files.selectedLines = lines }
            let column = textView.caretColumn
            if files.currentColumn != column { files.currentColumn = column }
        }
    }
}

final class CodeTextView: NSTextView {
    static let lineHeight: CGFloat = 20
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// Asks for the active file's path to be copied, with the selected lines when `true`.
    var copyPath: ((_ includingLines: Bool) -> Void)?
    private(set) var marks: [Int: FileContent.Mark] = [:]
    /// The UTF-16 offset where each line starts.
    private var lineStarts = [0]

    /// Room left between the end of a wrapped line and the minimap.
    static let trailingMargin: CGFloat = 28

    var lineCount: Int { lineStarts.count }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // A finite height: TextKit fails to draw with CGFloat.greatestFiniteMagnitude.
        let size = NSSize(width: max(newSize.width - Self.trailingMargin, 40), height: 1_000_000_000)
        if textContainer?.size != size { textContainer?.size = size }
    }

    func show(_ content: FileContent, as language: SourceLanguage) {
        marks = content.marks
        var starts = [0]
        for line in content.lines.dropLast() {
            starts.append(starts[starts.count - 1] + line.utf16.count + 1)
        }
        lineStarts = starts

        // Every row gets the same fixed height.
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        let font = Self.font
        let naturalHeight = font.ascender - font.descender + font.leading
        let text = NSMutableAttributedString(attributedString: SyntaxHighlighter.highlight(content.lines, as: language, font: font))
        let all = NSRange(location: 0, length: text.length)
        text.addAttribute(.paragraphStyle, value: paragraph, range: all)
        text.addAttribute(.baselineOffset, value: (Self.lineHeight - naturalHeight) / 2, range: all)
        textStorage?.setAttributedString(text)
    }

    /// The 1-based line holding the UTF-16 offset `location`.
    func line(at location: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    /// The lines the selection touches. A selection that ends just after a newline doesn't include the next line.
    var selectedLines: ClosedRange<Int> {
        let range = selectedRange()
        let first = line(at: range.location)
        let last = range.length > 0 ? line(at: range.upperBound - 1) : first
        return first...max(first, last)
    }

    var caretColumn: Int {
        let location = selectedRange().location
        return location - lineStarts[line(at: location) - 1] + 1
    }

    func moveCaret(toLine line: Int) {
        let index = lineStarts[min(max(line, 1), lineStarts.count) - 1]
        setSelectedRange(NSRange(location: index, length: 0))
        scrollToVisible(lineRect(line).insetBy(dx: 0, dy: -Self.lineHeight * 3))
    }

    /// The 1-based line's rect in the view, covering every row it wraps onto.
    func lineRect(_ line: Int) -> NSRect {
        let line = min(max(line, 1), lineStarts.count)
        let origin = textContainerOrigin
        let fallback = NSRect(x: 0, y: origin.y + CGFloat(line - 1) * Self.lineHeight, width: bounds.width, height: Self.lineHeight)
        guard let layoutManager, let textContainer else { return fallback }
        let length = (string as NSString).length
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] : length
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: max(0, end - start)), actualCharacterRange: nil)
        var rect: NSRect
        if glyphs.length > 0 {
            rect = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                .union(layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil))
        } else {
            // An empty last line: after the trailing newline, or the whole of an empty file.
            layoutManager.ensureLayout(for: textContainer)
            rect = layoutManager.extraLineFragmentRect
            if rect.isEmpty {
                guard line > 1 else { return fallback }
                let previous = lineRect(line - 1)
                return NSRect(x: 0, y: previous.maxY, width: bounds.width, height: Self.lineHeight)
            }
        }
        return NSRect(x: 0, y: origin.y + rect.minY, width: bounds.width, height: rect.height)
    }

    /// The line at `y` in the view, from 0, with the fraction of the way down it.
    func fractionalLine(at y: CGFloat) -> Double {
        let probe = NSRect(x: 0, y: y, width: bounds.width, height: 1)
        guard let line = lines(in: probe)?.lowerBound else { return 0 }
        let rect = lineRect(line)
        let fraction = rect.height > 0 ? min(max((y - rect.minY) / rect.height, 0), 1) : 0
        return Double(line - 1) + Double(fraction)
    }

    /// The `y` in the view where the fractional line from 0 begins.
    func y(ofFractionalLine line: Double) -> CGFloat {
        let whole = min(max(Int(line.rounded(.down)), 0), lineCount - 1)
        let rect = lineRect(whole + 1)
        return rect.minY + CGFloat(min(max(line - Double(whole), 0), 1)) * rect.height
    }

    /// The lines with a row inside `rect`, in the view's coordinates.
    func lines(in rect: NSRect) -> ClosedRange<Int>? {
        guard lineCount > 0, let layoutManager, let textContainer else { return nil }
        let origin = textContainerOrigin
        let containerRect = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let first = line(at: characters.location)
        // Include the empty last line, which has no glyphs of its own.
        let last = NSMaxRange(characters) >= (string as NSString).length ? lineCount : line(at: max(characters.location, NSMaxRange(characters) - 1))
        return first...max(first, last)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard selectedRange().length == 0 else { return }
        NSColor(Palette.currentLine).setFill()
        lineRect(selectedLines.lowerBound).intersection(rect).fill(using: .sourceOver)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        // Right-clicking outside the selection moves the caret there, so the menu acts on the clicked line.
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        let selection = selectedRange()
        if selection.length == 0 || !(selection.location...selection.upperBound).contains(index) {
            setSelectedRange(NSRange(location: index, length: 0))
        }

        let lines = selectedLines
        let lineLabel = lines.count == 1 ? "Line \(lines.lowerBound)" : "Lines \(lines.lowerBound)–\(lines.upperBound)"
        let menu = NSMenu()
        menu.addItem(item("Copy", #selector(copy(_:)), key: "c"))
        menu.addItem(item("Select All", #selector(selectAll(_:)), key: "a"))
        menu.addItem(.separator())
        menu.addItem(item("Copy Relative Path", #selector(copyRelativePath(_:))))
        menu.addItem(item("Copy Relative Path with \(lineLabel)", #selector(copyRelativePathWithLines(_:))))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func copyRelativePath(_ sender: Any?) {
        copyPath?(false)
    }

    @objc private func copyRelativePathWithLines(_ sender: Any?) {
        copyPath?(true)
    }
}

/// Line numbers and change bars, drawn beside the text view, one number per line however many rows it wraps onto.
private final class LineNumberRuler: NSRulerView {
    private static let thickness: CGFloat = 49

    private var textView: CodeTextView? { clientView as? CodeTextView }

    init(scrollView: NSScrollView, textView: CodeTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.thickness
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        // Views don't clip by default, and the dirty rect can reach past the gutter over the text.
        clipsToBounds = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewDidScroll),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        // Resizing rewraps the lines, which moves their numbers.
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewDidScroll),
            name: NSView.frameDidChangeNotification, object: textView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var requiredThickness: CGFloat { Self.thickness }
    override var isFlipped: Bool { true }

    @objc private func clipViewDidScroll() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dirtyRect = dirtyRect.intersection(bounds)
        NSColor(Palette.window).setFill()
        dirtyRect.fill()
        guard let textView else { return }

        let height = CodeTextView.lineHeight
        let visible = textView.convert(dirtyRect, from: self)
        guard let lines = textView.lines(in: NSRect(x: 0, y: visible.minY, width: textView.bounds.width, height: visible.height)) else { return }

        let selected = textView.selectedLines
        let showsCurrentLine = textView.selectedRange().length == 0
        for line in lines {
            let lineRect = textView.lineRect(line)
            let top = convert(NSPoint(x: 0, y: lineRect.minY), from: textView).y
            let rect = NSRect(x: 0, y: top, width: bounds.width, height: lineRect.height)
            if showsCurrentLine, selected.contains(line) {
                NSColor(Palette.currentLine).setFill()
                rect.fill(using: .sourceOver)
            }
            if let mark = textView.marks[line] {
                NSColor(mark.barColor).setFill()
                NSRect(x: 0, y: rect.minY, width: 3, height: rect.height).fill()
            }
            let number = "\(line)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: CodeTextView.font,
                .foregroundColor: NSColor(selected.contains(line) ? Palette.text : Palette.gutter),
            ]
            let size = number.size(withAttributes: attributes)
            number.draw(
                // On the line's first row, not centered across its wrapped rows.
                at: NSPoint(x: rect.maxX - 14 - size.width, y: rect.minY + (height - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
