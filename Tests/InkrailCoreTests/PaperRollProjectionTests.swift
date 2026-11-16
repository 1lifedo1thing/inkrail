import XCTest
@testable import InkrailCore

final class PaperRollProjectionTests: XCTestCase {
    func testProjectionIsInvertibleAcrossVisibleBend() {
        let projection = PaperRollProjection(width: 720, viewportHeight: 240)
        for step in 0...100 {
            let y = -projection.bendHeight + Double(step) * projection.bendHeight * 3 / 100
            XCTAssertEqual(projection.unprojectY(projection.projectY(y)), y, accuracy: 0.000_001)
            for x in [0.0, 76, 360, 644, 720] {
                XCTAssertEqual(projection.unprojectX(projection.projectX(x, at: y), at: y), x, accuracy: 0.000_001)
            }
        }
    }

    func testWritingBandRemainsUntransformed() {
        let projection = PaperRollProjection(width: 560, viewportHeight: 200)
        for y in [projection.bendHeight, 190, 250] {
            XCTAssertEqual(projection.projectY(y), y)
            XCTAssertEqual(projection.horizontalScale(at: y), 1)
            XCTAssertEqual(projection.projectX(76, at: y), 76)
        }
    }

    func testEarlierTextCompressesMonotonicallyTowardLip() {
        let projection = PaperRollProjection(width: 720, viewportHeight: 240)
        let h = projection.bendHeight
        XCTAssertEqual(projection.projectY(-h), 0)
        XCTAssertEqual(projection.projectY(h), h)
        let topLine = projection.projectY(-h + 30) - projection.projectY(-h)
        let lowerLine = projection.projectY(h) - projection.projectY(h - 30)
        XCTAssertGreaterThan(topLine, 0)
        XCTAssertLessThan(topLine, lowerLine)
        XCTAssertGreaterThan(projection.projectY(0), 0)
        XCTAssertLessThan(projection.horizontalScale(at: -h), projection.horizontalScale(at: 0))
    }

    func testNonfiniteGeometryIsBounded() {
        let projection = PaperRollProjection(width: .infinity, viewportHeight: .nan)
        XCTAssertTrue(projection.width.isFinite)
        XCTAssertTrue(projection.bendHeight.isFinite)
        XCTAssertEqual(projection.projectY(.nan), 0)
        XCTAssertEqual(projection.unprojectY(.infinity), 0)
        XCTAssertTrue(projection.projectX(.nan, at: .infinity).isFinite)
        XCTAssertTrue(projection.unprojectX(.infinity, at: .nan).isFinite)
    }
}
