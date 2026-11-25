import XCTest
import AppKit
@testable import StickyCore

final class MarkdownCodecTests: XCTestCase {
    let base: CGFloat = 13

    private func font(bold: Bool = false, italic: Bool = false, size: CGFloat? = nil) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let f = NSFont.systemFont(ofSize: size ?? base)
        let d = f.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: d, size: size ?? base) ?? f
    }

    private func attributed(_ parts: [(String, NSFont, Bool)]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (t, f, u) in parts {
            var attrs: [NSAttributedString.Key: Any] = [.font: f]
            if u { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: t, attributes: attrs))
        }
        return out
    }

    private func runs(_ s: NSAttributedString) -> [(String, Bool, Bool, Bool, CGFloat)] {
        var r: [(String, Bool, Bool, Bool, CGFloat)] = []
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, range, _ in
            let f = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 0)
            let t = f.fontDescriptor.symbolicTraits
            let u = (attrs[.underlineStyle] as? Int ?? 0) != 0
            let skew = ((attrs[.obliqueness] as? NSNumber)?.doubleValue ?? 0) > 0
            r.append((s.attributedSubstring(from: range).string, t.contains(.bold), t.contains(.italic) || skew, u, f.pointSize))
        }
        return r
    }

    func testBoldEncodesAndRoundTrips() {
        let s = attributed([("안녕", font(bold: true), false), (" 세계", font(), false)])
        let md = MarkdownCodec.encode(s, baseSize: base)
        XCTAssertEqual(md, "**안녕** 세계")
        let back = runs(MarkdownCodec.decode(md, baseSize: base))
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].0, "안녕"); XCTAssertTrue(back[0].1)
        XCTAssertFalse(back[1].1)
    }

    func testItalicEncodes() {
        let s = attributed([("a", font(italic: true), false), ("b", font(), false)])
        XCTAssertEqual(MarkdownCodec.encode(s, baseSize: base), "*a*b")
        XCTAssertTrue(runs(MarkdownCodec.decode("*a*b", baseSize: base))[0].2)
    }

    func testUnderlineEncodes() {
        let s = attributed([("a", font(), true), ("b", font(), false)])
        XCTAssertEqual(MarkdownCodec.encode(s, baseSize: base), "<u>a</u>b")
        XCTAssertTrue(runs(MarkdownCodec.decode("<u>a</u>b", baseSize: base))[0].3)
    }

    func testSizeSpan() {
        let s = attributed([("큰", font(size: 15), false), ("글", font(), false)])
        let md = MarkdownCodec.encode(s, baseSize: base)
        XCTAssertEqual(md, "<span style=\"font-size:15pt\">큰</span>글")
        let back = runs(MarkdownCodec.decode(md, baseSize: base))
        XCTAssertEqual(back[0].4, 15)
        XCTAssertEqual(back[1].4, base)
    }

    func testNestedBoldUnderline() {
        let s = attributed([("x", font(bold: true), true)])
        let md = MarkdownCodec.encode(s, baseSize: base)
        XCTAssertEqual(md, "**<u>x</u>**")
        let back = runs(MarkdownCodec.decode(md, baseSize: base))
        XCTAssertTrue(back[0].1); XCTAssertTrue(back[0].3)
        XCTAssertEqual(MarkdownCodec.encode(MarkdownCodec.decode(md, baseSize: base), baseSize: base), md)
    }

    func testPlainTextWithMarkdownCharsIsEscapedAndRoundTrips() {
        let raw = "a*b **c** <u>d</u> \\ e_f\n# not heading"
        let s = attributed([(raw, font(), false)])
        let md = MarkdownCodec.encode(s, baseSize: base)
        let back = MarkdownCodec.decode(md, baseSize: base)
        XCTAssertEqual(back.string, raw)
        XCTAssertEqual(runs(back).count, 1)
        XCTAssertFalse(runs(back)[0].1)
        XCTAssertFalse(runs(back)[0].3)
    }

    func testNewlinesAndKoreanPreserved() {
        let raw = "기말고사 일정\n\n12/6"
        let s = attributed([(raw, font(), false)])
        let md = MarkdownCodec.encode(s, baseSize: base)
        XCTAssertEqual(md, raw)
        XCTAssertEqual(MarkdownCodec.decode(md, baseSize: base).string, raw)
    }

    func testBoldAcrossNewlineWrapsEachLine() {
        let s = attributed([("a\nb", font(bold: true), false)])
        XCTAssertEqual(MarkdownCodec.encode(s, baseSize: base), "**a**\n**b**")
    }

    func testExternalMarkdown() {
        let r = runs(MarkdownCodec.decode("**a** *b*", baseSize: base))
        XCTAssertEqual(r.map { $0.0 }, ["a", " ", "b"])
        XCTAssertTrue(r[0].1); XCTAssertFalse(r[1].1); XCTAssertTrue(r[2].2)
    }

    func testUnclosedBoldAppliesToRestOfText() {
        XCTAssertEqual(MarkdownCodec.decode("**abc", baseSize: base).string, "abc")
    }




    func testUnknownSpanStyleIsKeptAsText() {
        XCTAssertEqual(MarkdownCodec.decode("<span style=\"color:red\">a</span>", baseSize: base).string,
                       "<span style=\"color:red\">a")
    }

    private func isStruck(_ s: NSAttributedString, at i: Int) -> Bool {
        (s.attribute(.strikethroughStyle, at: i, effectiveRange: nil) as? Int ?? 0) != 0
    }

    func testStrikethroughEncodesAndRoundTrips() {
        let s = NSMutableAttributedString(string: "ab", attributes: [.font: font()])
        s.append(NSAttributedString(string: "cd", attributes: [.font: font(),
                                                              .strikethroughStyle: NSUnderlineStyle.single.rawValue]))
        let md = MarkdownCodec.encode(s, baseSize: base)
        XCTAssertEqual(md, "ab~~cd~~")
        let back = MarkdownCodec.decode(md, baseSize: base)
        XCTAssertEqual(back.string, "abcd")
        XCTAssertFalse(isStruck(back, at: 0)); XCTAssertTrue(isStruck(back, at: 2))
    }

    func testStrikethroughCombinesWithBold() {
        let s = NSAttributedString(string: "x", attributes: [.font: font(bold: true),
                                                             .strikethroughStyle: NSUnderlineStyle.single.rawValue])
        let md = MarkdownCodec.encode(s, baseSize: base)
        XCTAssertEqual(md, "**~~x~~**")
        XCTAssertEqual(MarkdownCodec.encode(MarkdownCodec.decode(md, baseSize: base), baseSize: base), md)
    }

    func testTypedTildesAreNotMistakenForStrikethrough() {
        let raw = "a ~~b~~ c ~"
        let md = MarkdownCodec.encode(attributed([(raw, font(), false)]), baseSize: base)
        let back = MarkdownCodec.decode(md, baseSize: base)
        XCTAssertEqual(back.string, raw)
        XCTAssertFalse(isStruck(back, at: 3))
    }




    func testLegacyFontFamilySpanIsIgnoredAndDroppedOnSave() {
        // Older notes may contain per-text fonts; the app now uses one font everywhere.
        let md = "<span style=\"font-family:Menlo\">코드</span> 본문 <span style=\"font-size:20pt\"><span style=\"font-family:Georgia\">**큰**</span></span>"
        let back = MarkdownCodec.decode(md, baseSize: base)
        XCTAssertEqual(back.string, "코드 본문 큰")
        let systemFamily = NSFont.systemFont(ofSize: base).familyName
        back.enumerateAttribute(.font, in: NSRange(location: 0, length: back.length)) { v, _, _ in
            XCTAssertEqual((v as? NSFont)?.familyName, systemFamily)
        }
        XCTAssertEqual(MarkdownCodec.encode(back, baseSize: base),
                       "코드 본문 <span style=\"font-size:20pt\">**큰**</span>")
    }

    func testItalicIsDrawnAsSkewSoKoreanSlantsToo() {
        // The system italic face has no Hangul glyphs, so italic is a skew applied to any script.
        let back = MarkdownCodec.decode("*한글 abc*", baseSize: base)
        XCTAssertEqual(back.attribute(.obliqueness, at: 0, effectiveRange: nil) as? Double, MarkdownCodec.italicSkew)
        XCTAssertEqual(back.attribute(.obliqueness, at: back.length - 1, effectiveRange: nil) as? Double, MarkdownCodec.italicSkew)
        XCTAssertFalse(((back.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits ?? []).contains(.italic))
    }

    func testSkewEncodesAsItalic() {
        let s = NSAttributedString(string: "기울임", attributes: [.font: font(), .obliqueness: MarkdownCodec.italicSkew])
        XCTAssertEqual(MarkdownCodec.encode(s, baseSize: base), "*기울임*")
    }
}
