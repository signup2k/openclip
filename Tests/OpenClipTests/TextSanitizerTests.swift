import XCTest
@testable import Core

final class TextSanitizerTests: XCTestCase {

    func testInvisibleAndZeroWidthCharactersAreNotSubstantial() {
        XCTAssertFalse(TextSanitizer.isSubstantial("\u{0000}")) // Null byte
        XCTAssertFalse(TextSanitizer.isSubstantial("\u{00A0}")) // Non-breaking space
        XCTAssertFalse(TextSanitizer.isSubstantial("\u{200B}")) // Zero-width space
        XCTAssertFalse(TextSanitizer.isSubstantial("\u{200C}")) // Zero-width non-joiner
        XCTAssertFalse(TextSanitizer.isSubstantial("\u{200D}")) // Zero-width joiner
        XCTAssertFalse(TextSanitizer.isSubstantial("\u{2060}")) // Word joiner
        XCTAssertFalse(TextSanitizer.isSubstantial("\u{FEFF}")) // Zero-width no-break space / BOM
        XCTAssertFalse(TextSanitizer.isSubstantial("\u{200B}\u{00A0}\u{FEFF}   \n"))
    }

    func testSanitize() {
        XCTAssertNil(TextSanitizer.sanitize(nil))
        XCTAssertNil(TextSanitizer.sanitize(""))
        XCTAssertNil(TextSanitizer.sanitize("  \u{200B}\u{FEFF}  "))
        XCTAssertEqual(TextSanitizer.sanitize("  hello  "), "hello")
        XCTAssertEqual(TextSanitizer.sanitize("\u{200B}openclip\u{FEFF}"), "openclip")
    }
}
