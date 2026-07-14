import XCTest
@testable import MoltenVRKit

final class WireTests: XCTestCase {
    func testFrameHeader() {
        let d = KitWire.frame(.hello, Data([1, 2, 3]))
        XCTAssertEqual(d.count, 15)
        let b = [UInt8](d)
        XCTAssertEqual(b.loadLE(UInt32.self, 0), KitWire.magic)
        XCTAssertEqual(b.loadLE(UInt16.self, 4), KitWire.protoVer)
        XCTAssertEqual(b.loadLE(UInt16.self, 6), KitWire.MsgType.hello.rawValue)
        XCTAssertEqual(b.loadLE(UInt32.self, 8), 3)
    }

    func testHelloRoundTrip() {
        let p = KitWire.encode(KitWire.Hello(protoVer: 1, featureFlags: 3, pid: 4242,
                                             appName: "KitDemo"))
        XCTAssertEqual(p.count, 76)
        let h = KitWire.decodeHello([UInt8](p))
        XCTAssertEqual(h?.protoVer, 1)
        XCTAssertEqual(h?.featureFlags, 3)
        XCTAssertEqual(h?.pid, 4242)
        XCTAssertEqual(h?.appName, "KitDemo")
    }

    func testHelloNameTruncation() {
        let long = String(repeating: "x", count: 100)
        let p = KitWire.encode(KitWire.Hello(protoVer: 1, featureFlags: 0, pid: 1,
                                             appName: long))
        XCTAssertEqual(p.count, 76)                  // fixed width regardless of input
        let h = KitWire.decodeHello([UInt8](p))
        XCTAssertEqual(h?.appName.count, 63)         // last byte stays NUL
    }

    func testPanelDescRoundTrip() {
        let desc = KitWire.PanelDesc(
            panelId: 7, surfaceId: 99,
            pos: (0.5, 1.5, -1.25), quat: (0, 0.383, 0, 0.924),
            size: (1.1, 0.7), curvature: 2.5, opacity: 0.9, z: -3,
            flags: 0b11, title: "Demo Panel")
        let p = KitWire.encode(desc)
        XCTAssertEqual(p.count, 124)
        guard let d = KitWire.decodePanelDesc([UInt8](p)) else { return XCTFail("decode") }
        XCTAssertEqual(d.panelId, 7)
        XCTAssertEqual(d.surfaceId, 99)
        XCTAssertEqual(d.pos.2, -1.25)
        XCTAssertEqual(d.quat.1, 0.383)
        XCTAssertEqual(d.size.0, 1.1)
        XCTAssertEqual(d.curvature, 2.5)
        XCTAssertEqual(d.opacity, 0.9)
        XCTAssertEqual(d.z, -3)
        XCTAssertEqual(d.flags, 0b11)
        XCTAssertEqual(d.title, "Demo Panel")
    }

    func testPointerRoundTrip() {
        let p = KitWire.encode(KitWire.Pointer(panelId: 3, hand: 1, u: 0.25, v: 0.75,
                                               buttons: 0b101, scrollX: -0.5, scrollY: 1))
        XCTAssertEqual(p.count, 28)
        let ev = KitWire.decodePointer([UInt8](p))
        XCTAssertEqual(ev?.panelId, 3)
        XCTAssertEqual(ev?.hand, 1)
        XCTAssertEqual(ev?.u, 0.25)
        XCTAssertEqual(ev?.buttons, 0b101)
        XCTAssertEqual(ev?.scrollY, 1)
    }

    func testPanelMovedRoundTrip() {
        let p = KitWire.encode(KitWire.PanelMoved(panelId: 9, pos: (1, 2, 3),
                                                  quat: (0, 0, 0, 1), size: (0.8, 0.6),
                                                  curvature: 0))
        XCTAssertEqual(p.count, 44)
        let mv = KitWire.decodePanelMoved([UInt8](p))
        XCTAssertEqual(mv?.panelId, 9)
        XCTAssertEqual(mv?.pos.1, 2)
        XCTAssertEqual(mv?.size.1, 0.6)
    }

    func testKeyRoundTrip() {
        let p = KitWire.encode(KitWire.Key(panelId: 2, keyCode: 51, modifiers: 1, isDown: true))
        XCTAssertEqual(p.count, 16)
        let k = KitWire.decodeKey([UInt8](p))
        XCTAssertEqual(k?.panelId, 2)
        XCTAssertEqual(k?.keyCode, 51)
        XCTAssertEqual(k?.modifiers, 1)
        XCTAssertEqual(k?.isDown, true)
    }

    func testTextRoundTrip() {
        let p = KitWire.encodeText(panelId: 5, "héllo →")
        let t = KitWire.decodeText([UInt8](p), length: p.count)
        XCTAssertEqual(t?.panelId, 5)
        XCTAssertEqual(t?.text, "héllo →")
    }

    func testTruncatedPayloadsRejected() {
        XCTAssertNil(KitWire.decodeHello([UInt8](repeating: 0, count: 75)))
        XCTAssertNil(KitWire.decodePanelDesc([UInt8](repeating: 0, count: 123)))
        XCTAssertNil(KitWire.decodePointer([UInt8](repeating: 0, count: 27)))
        XCTAssertNil(KitWire.decodePanelMoved([UInt8](repeating: 0, count: 43)))
        XCTAssertNil(KitWire.decodeKey([UInt8](repeating: 0, count: 15)))
        XCTAssertNil(KitWire.decodeText([UInt8](repeating: 0, count: 3), length: 3))
        XCTAssertNil(KitWire.decodePair([UInt8](repeating: 0, count: 7)))
    }

    func testLongerPayloadsAccepted() {
        // structs grow at the tail: a v2 sender may append fields, v1 must still decode
        var p = KitWire.encode(KitWire.Pointer(panelId: 1, hand: 0, u: 0, v: 0,
                                               buttons: 0, scrollX: 0, scrollY: 0))
        p.append(contentsOf: [UInt8](repeating: 0xAB, count: 16))
        XCTAssertNotNil(KitWire.decodePointer([UInt8](p)))
    }
}
