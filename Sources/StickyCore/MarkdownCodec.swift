import AppKit

/// Converts between rich text and the small Markdown subset the app stores:
/// `**bold**`, `*italic*`, `~~strikethrough~~`, `<u>underline</u>`, `<span style="font-size:Npt">size</span>`.
/// There is one font everywhere; `font-family` spans from older notes are read and ignored.
public enum MarkdownCodec {
    /// Italic is a skew drawn on top of the text (works for Hangul too; the system italic face has no Hangul).
    public static let italicSkew: Double = 0.2

    // MARK: Encode

    public static func encode(_ s: NSAttributedString, baseSize: CGFloat) -> String {
        var out = ""
        var atLineStart = true
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, range, _ in
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.bold)
            let italic = traits.contains(.italic) || ((attrs[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0
            let underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
            let strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
            let size = font?.pointSize ?? baseSize
            let text = s.attributedSubstring(from: range).string
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (i, line) in lines.enumerated() {
                if i > 0 { out += "\n"; atLineStart = true }
                if line.isEmpty { continue }
                var seg = escape(String(line), atLineStart: atLineStart)
                atLineStart = false
                if underline { seg = "<u>\(seg)</u>" }
                if strike { seg = "~~\(seg)~~" }
                if italic { seg = "*\(seg)*" }
                if bold { seg = "**\(seg)**" }
                if abs(size - baseSize) > 0.01 {
                    seg = "<span style=\"font-size:\(format(size))pt\">\(seg)</span>"
                }
                out += seg
            }
        }
        return out
    }

    private static func format(_ v: CGFloat) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", Double(v))
    }

    private static func escape(_ s: String, atLineStart: Bool) -> String {
        var r = ""
        for (i, ch) in s.enumerated() {
            switch ch {
            case "\\", "*", "<", "~": r += "\\\(ch)"
            case "#" where i == 0 && atLineStart: r += "\\#"
            default: r.append(ch)
            }
        }
        return r
    }

    // MARK: Decode

    public static func decode(_ md: String, baseSize: CGFloat) -> NSAttributedString {
        let chars = Array(md)
        let result = NSMutableAttributedString()
        var buffer = ""
        var bold = false, italic = false, underline = false, strike = false
        var sizes: [CGFloat?] = []     // one entry per open <span>; nil for spans that carry no size

        func flush() {
            guard !buffer.isEmpty else { return }
            let size = sizes.reversed().compactMap { $0 }.first ?? baseSize
            var traits: NSFontDescriptor.SymbolicTraits = []
            if bold { traits.insert(.bold) }
            let base = NSFont.systemFont(ofSize: size)
            let font = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if italic { attrs[.obliqueness] = italicSkew }
            if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: buffer, attributes: attrs))
            buffer = ""
        }
        func has(_ token: String, at i: Int) -> Bool {
            let t = Array(token)
            return i + t.count <= chars.count && Array(chars[i..<i + t.count]) == t
        }

        var i = 0
        let spanOpen = "<span style=\""
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count {
                buffer.append(chars[i + 1]); i += 2
            } else if has("**", at: i) {
                flush(); bold.toggle(); i += 2
            } else if has("~~", at: i) {
                flush(); strike.toggle(); i += 2
            } else if chars[i] == "*" {
                flush(); italic.toggle(); i += 1
            } else if has("<u>", at: i) {
                flush(); underline = true; i += 3
            } else if has("</u>", at: i) {
                flush(); underline = false; i += 4
            } else if has("</span>", at: i) {
                flush(); if !sizes.isEmpty { sizes.removeLast() }; i += 7
            } else if has(spanOpen, at: i), let end = chars[i...].firstIndex(of: ">"),
                      let span = parseSpanStyle(String(chars[(i + spanOpen.count)..<end])) {
                flush(); sizes.append(span.size); i = end + 1
            } else {
                buffer.append(chars[i]); i += 1
            }
        }
        flush()
        return result
    }

    /// Parses the style part of `<span style="...">` (the text up to the closing quote), e.g.
    /// `font-size:15pt` or `font-family:Menlo`. Returns nil for anything else.
    private static func parseSpanStyle(_ tail: String) -> (size: CGFloat?, family: String?)? {
        guard tail.hasSuffix("\"") else { return nil }
        var size: CGFloat?, family: String?
        for decl in tail.dropLast().split(separator: ";") {
            let kv = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { return nil }
            switch kv[0] {
            case "font-size":
                guard kv[1].hasSuffix("pt"), let v = Double(kv[1].dropLast(2)) else { return nil }
                size = CGFloat(v)
            case "font-family": family = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            default: return nil
            }
        }
        return size == nil && family == nil ? nil : (size, family)
    }
}
