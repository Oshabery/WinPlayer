import XCTest
@testable import DeskLink

final class ConnectionModelTests: XCTestCase {
    func testParseHostOnly() {
        XCTAssertEqual(HostAddress(parsing: "  my-pc.local "), HostAddress(host: "my-pc.local", port: 3389))
    }

    func testParseHostAndPort() {
        XCTAssertEqual(HostAddress(parsing: "192.168.1.10:3390"), HostAddress(host: "192.168.1.10", port: 3390))
    }

    func testParseIPv6() {
        XCTAssertEqual(HostAddress(parsing: "[fe80::1]:3390"), HostAddress(host: "fe80::1", port: 3390))
        XCTAssertEqual(HostAddress(parsing: "[fe80::1]"), HostAddress(host: "fe80::1", port: 3389))
        XCTAssertEqual(HostAddress(parsing: "fe80::1"), HostAddress(host: "fe80::1", port: 3389))
    }

    func testRejectInvalid() {
        XCTAssertNil(HostAddress(parsing: ""))
        XCTAssertNil(HostAddress(parsing: "host:0"))
        XCTAssertNil(HostAddress(parsing: "host:70000"))
        XCTAssertNil(HostAddress(parsing: ":3389"))
        XCTAssertNil(HostAddress(parsing: "my pc"))
        XCTAssertNil(HostAddress(parsing: "[fe80::1]x"))
    }

    func testDisplayString() {
        XCTAssertEqual(HostAddress(host: "pc", port: 3389).displayString, "pc")
        XCTAssertEqual(HostAddress(host: "pc", port: 3390).displayString, "pc:3390")
        XCTAssertEqual(HostAddress(host: "fe80::1", port: 3390).displayString, "[fe80::1]:3390")
    }

    func testResolutionIsRoundedForRDP() {
        let size = ResolutionMode.fitScreen.size(fitting: CGSize(width: 1194, height: 834))
        XCTAssertEqual(size.width, 1192)
        XCTAssertEqual(size.height, 832)
        XCTAssertEqual(ResolutionMode.fullHD.size(fitting: .zero).width, 1920)
        XCTAssertEqual(ResolutionMode.fitScreen.size(fitting: CGSize(width: 50, height: 99_999)).height, 8192)
    }

    func testKeyboardValues() {
        XCTAssertEqual(KeyboardLayoutOption.japanese.rdpValues.layout, 0x411)
        XCTAssertEqual(KeyboardLayoutOption.japanese.rdpValues.type, 7)
        XCTAssertEqual(KeyboardLayoutOption.us.rdpValues.layout, 0x409)
    }
}
