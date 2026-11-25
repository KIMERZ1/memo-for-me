import AppKit
import StickyCore

extension NSFont {
    func toggling(_ trait: NSFontDescriptor.SymbolicTraits, on: Bool) -> NSFont {
        var t = fontDescriptor.symbolicTraits
        if on { t.insert(trait) } else { t.remove(trait) }
        return NSFont(descriptor: fontDescriptor.withSymbolicTraits(t), size: pointSize) ?? self
    }
    func withPointSize(_ s: CGFloat) -> NSFont {
        NSFont(descriptor: fontDescriptor, size: s) ?? self
    }
}

/// Rich-text editor. Formatting commands apply to the selection only; with no selection they
/// change the typing attributes (existing text is untouched).
final class NoteTextView: NSTextView {
    static let minSize: CGFloat = 9, maxSize: CGFloat = 48
    private var baseFont: NSFont { NSFont.systemFont(ofSize: NoteAppearance.baseFontSize) }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    func setUp() {
        isRichText = true
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        drawsBackground = false
        textColor = .black
        font = baseFont
        typingAttributes = [.font: baseFont, .foregroundColor: NSColor.black]
        textContainerInset = NSSize(width: 14, height: 14)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        insertionPointColor = .black
    }

    // MARK: Styling

    struct RunStyle {
        var bold = false, italic = false, underline = false, strike = false
        var size: CGFloat = NoteAppearance.baseFontSize
    }

    private func style(of attrs: [NSAttributedString.Key: Any]) -> RunStyle {
        let f = attrs[.font] as? NSFont ?? baseFont
        let t = f.fontDescriptor.symbolicTraits
        return RunStyle(
            bold: t.contains(.bold),
            italic: t.contains(.italic) || ((attrs[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0,
            underline: (attrs[.underlineStyle] as? Int ?? 0) != 0,
            strike: (attrs[.strikethroughStyle] as? Int ?? 0) != 0,
            size: f.pointSize)
    }

    /// Returns `old` with `style` applied (one font everywhere: the system font).
    private func attributes(applying st: RunStyle, to old: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = old
        let base = NSFont.systemFont(ofSize: st.size)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if st.bold { traits.insert(.bold) }
        let font = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: st.size) ?? base
        a[.font] = font
        a[.obliqueness] = st.italic ? MarkdownCodec.italicSkew : nil   // skew: the system italic face has no Hangul
        a[.underlineStyle] = st.underline ? NSUnderlineStyle.single.rawValue : nil
        a[.strikethroughStyle] = st.strike ? NSUnderlineStyle.single.rawValue : nil
        return a
    }

    /// Applies `change` to every run of the selection; with no selection, to what is typed next.
    private func restyle(_ change: (inout RunStyle) -> Void) {
        let range = selectedRange()
        if range.length == 0 {
            var st = style(of: typingAttributes)
            change(&st)
            typingAttributes = attributes(applying: st, to: typingAttributes)
            return
        }
        guard let ts = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        ts.enumerateAttributes(in: range) { attrs, r, _ in runs.append((r, attrs)) }
        ts.beginEditing()
        for (r, attrs) in runs {
            var st = style(of: attrs)
            change(&st)
            ts.setAttributes(attributes(applying: st, to: attrs), range: r)
        }
        ts.endEditing()
        didChangeText()
    }

    /// Whether every character of the selection (or the typing style, with no selection) has the trait.
    private func allHave(_ kp: KeyPath<RunStyle, Bool>) -> Bool {
        let range = selectedRange()
        if range.length == 0 { return style(of: typingAttributes)[keyPath: kp] }
        var all = true
        textStorage?.enumerateAttributes(in: range) { attrs, _, stop in
            if !style(of: attrs)[keyPath: kp] { all = false; stop.pointee = true }
        }
        return all
    }

    private func toggle(_ kp: KeyPath<RunStyle, Bool>, _ wk: WritableKeyPath<RunStyle, Bool>) {
        let turnOn = !allHave(kp)
        restyle { $0[keyPath: wk] = turnOn }
    }

    // MARK: Commands

    @objc func toggleBold() { toggle(\.bold, \.bold) }
    @objc func toggleItalic() { toggle(\.italic, \.italic) }
    @objc func toggleUnderline() { toggle(\.underline, \.underline) }
    @objc func toggleStrikethrough() { toggle(\.strike, \.strike) }

    func adjustSize(by delta: CGFloat) {
        restyle { $0.size = min(Self.maxSize, max(Self.minSize, $0.size + delta)) }
    }

    struct SelectionStyle { var bold = false, italic = false, underline = false, strike = false }

    /// What the whole selection has in common (a trait counts only if every character has it).
    func selectionStyle() -> SelectionStyle {
        let range = selectedRange()
        guard range.length > 0, let ts = textStorage else { return SelectionStyle() }
        var st = SelectionStyle(bold: true, italic: true, underline: true, strike: true)
        ts.enumerateAttributes(in: range) { attrs, _, _ in
            let r = style(of: attrs)
            if !r.bold { st.bold = false }
            if !r.italic { st.italic = false }
            if !r.underline { st.underline = false }
            if !r.strike { st.strike = false }
        }
        return st
    }

    // MARK: Cursor

    // Two systems decide the cursor and must agree: AppKit's cursor rects (used once the note is the key window)
    // and the content view's always-active tracking (used while the app is inactive). Both say: I-beam over the
    // text, arrow under the hover toolbar.

    /// Areas (in this view's coordinates) covered by the hover toolbar, where the I-beam must not show.
    var excludedCursorRects: () -> [NSRect] = { [] }

    private func isOverOverlay(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        return excludedCursorRects().contains { $0.contains(p) }
    }
    /// Called when a click/drag finishes (NSTextView tracks the whole drag inside `mouseDown`).
    var onMouseDownFinished: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if !isOverOverlay(event) { NSCursor.iBeam.set() }   // the click that makes this note key: I-beam at once
        super.mouseDown(with: event)
        onMouseDownFinished?()
    }
    override func mouseMoved(with event: NSEvent) {
        if isOverOverlay(event) { NSCursor.arrow.set() } else { super.mouseMoved(with: event) }
    }
    override func cursorUpdate(with event: NSEvent) {
        if isOverOverlay(event) { NSCursor.arrow.set() } else { super.cursorUpdate(with: event) }
    }

    override func resetCursorRects() {
        discardCursorRects()
        var pieces = [visibleRect]
        for hole in excludedCursorRects() { pieces = pieces.flatMap { Self.subtract(hole, from: $0) } }
        pieces.forEach { addCursorRect($0, cursor: .iBeam) }
    }

    private static func subtract(_ hole: NSRect, from r: NSRect) -> [NSRect] {
        let h = r.intersection(hole)
        if h.isNull || h.isEmpty { return [r] }
        var out: [NSRect] = []
        if h.minY > r.minY { out.append(NSRect(x: r.minX, y: r.minY, width: r.width, height: h.minY - r.minY)) }
        if h.maxY < r.maxY { out.append(NSRect(x: r.minX, y: h.maxY, width: r.width, height: r.maxY - h.maxY)) }
        if h.minX > r.minX { out.append(NSRect(x: r.minX, y: h.minY, width: h.minX - r.minX, height: h.height)) }
        if h.maxX < r.maxX { out.append(NSRect(x: h.maxX, y: h.minY, width: r.maxX - h.maxX, height: h.height)) }
        return out
    }
}
