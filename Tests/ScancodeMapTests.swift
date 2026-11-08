import XCTest
@testable import DeskLink

final class ScancodeMapTests: XCTestCase {
    func testLetters() {
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x04), 0x1E) // a
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x14), 0x10) // q
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x1D), 0x2C) // z
    }

    func testDigits() {
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x1E), 0x02) // 1
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x27), 0x0B) // 0
    }

    func testExtendedKeysCarryFlag() {
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x4F), 0x14D) // →
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x4C), 0x153) // Delete
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x58), 0x11C) // テンキー Enter
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0xE3), 0x15B) // Command → 左 Windows
    }

    func testFunctionKeys() {
        XCTAssertEqual(ScancodeMap.function(1), 0x3B)
        XCTAssertEqual(ScancodeMap.function(10), 0x44)
        XCTAssertEqual(ScancodeMap.function(11), 0x57)
        XCTAssertEqual(ScancodeMap.function(12), 0x58)
        XCTAssertNil(ScancodeMap.function(13))
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x45), 0x58) // F12
    }

    func testJapaneseKeys() {
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x87), 0x73) // ろ
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x89), 0x7D) // ¥
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x8A), 0x79) // 変換
        XCTAssertEqual(ScancodeMap.scancode(forHIDUsage: 0x8B), 0x7B) // 無変換
    }

    func testUnknownUsage() {
        XCTAssertNil(ScancodeMap.scancode(forHIDUsage: 0x00))
        XCTAssertNil(ScancodeMap.scancode(forHIDUsage: 0x200))
    }

    func testAsciiShortcutMapping() {
        XCTAssertEqual(KeyboardInputController.asciiScancode(for: "c")?.0, 0x2E)
        XCTAssertEqual(KeyboardInputController.asciiScancode(for: "C")?.1, true)
        XCTAssertEqual(KeyboardInputController.asciiScancode(for: "0")?.0, 0x0B)
        XCTAssertNil(KeyboardInputController.asciiScancode(for: "あ"))
        XCTAssertNil(KeyboardInputController.asciiScancode(for: "ab"))
    }
}
