import XCTest
@testable import TUIKit

@TUIActor
final class Base64Tests: XCTestCase {

    func testEmptyInputEncodesToEmptyString() async {
        XCTAssertEqual(Base64.encode(""), "")
        XCTAssertEqual(Base64.encode([]), "")
    }

    func testPaddingFollowsRemainingByteCount() async {
        XCTAssertEqual(Base64.encode("f"), "Zg==")
        XCTAssertEqual(Base64.encode("fo"), "Zm8=")
        XCTAssertEqual(Base64.encode("foo"), "Zm9v")
        XCTAssertEqual(Base64.encode("foob"), "Zm9vYg==")
        XCTAssertEqual(Base64.encode("fooba"), "Zm9vYmE=")
        XCTAssertEqual(Base64.encode("foobar"), "Zm9vYmFy")
    }

    func testMultibyteCharactersEncodeAsUTF8() async {
        XCTAssertEqual(Base64.encode("あ"), "44GC")
        XCTAssertEqual(Base64.encode("日本語"), "5pel5pys6Kqe")
        XCTAssertEqual(Base64.encode("🙂"), "8J+Zgg==")
    }

    func testControlCharactersEncodeLikeAnyOtherByte() async {
        XCTAssertEqual(Base64.encode("a\nb"), "YQpi")
        XCTAssertEqual(Base64.encode([0x00, 0x1B, 0x07]), "ABsH")
    }

    func testAllByteValuesEncodeToTheStandardAlphabet() async {
        let expected = """
            AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7\
            PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3\
            eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKz\
            tLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v\
            8PHy8/T19vf4+fr7/P3+/w==
            """
        XCTAssertEqual(Base64.encode((0...255).map { UInt8($0) }), expected)
    }

    func testEncodedLengthIsAlwaysAMultipleOfFour() async {
        for count in 0..<32 {
            let encoded = Base64.encode([UInt8](repeating: 0x61, count: count))
            XCTAssertEqual(encoded.utf8.count, (count + 2) / 3 * 4, "count = \(count)")
        }
    }
}
