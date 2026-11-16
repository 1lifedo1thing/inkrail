import XCTest
@testable import InkrailCore

final class LampBeamProfileTests: XCTestCase {
    func testStrongestIlluminationIsAtTheSlit() {
        let source = LampBeamProfile.illumination(x: 0, rise: 0)
        XCTAssertEqual(source, 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(source, LampBeamProfile.illumination(x: 0, rise: 35))
        XCTAssertGreaterThan(source, LampBeamProfile.illumination(x: 25, rise: 0))
        XCTAssertGreaterThan(source, LampBeamProfile.illumination(x: 0, rise: -5))
    }

    func testCentreFadesContinuouslyUpThePaper() {
        var previous = LampBeamProfile.illumination(x: 0, rise: 0)
        for rise in stride(from: 4.0, through: LampBeamProfile.sourceY, by: 4) {
            let value = LampBeamProfile.illumination(x: 0, rise: rise)
            XCTAssertLessThanOrEqual(value, previous, "Centre brightened at rise \(rise)")
            previous = value
        }
        XCTAssertEqual(previous, 0)
    }

    func testFanWidensAwayFromTheSlit() {
        // Compare lateral light with the centre at the same height, so this
        // measures widening independently of the vertical brightness decay.
        func relativeShoulder(at rise: Double) -> Double {
            LampBeamProfile.illumination(x: 60, rise: rise)
                / LampBeamProfile.illumination(x: 0, rise: rise)
        }
        let near = relativeShoulder(at: 20)
        let middle = relativeShoulder(at: 100)
        let far = relativeShoulder(at: 200)
        XCTAssertLessThan(near, 0.30)
        XCTAssertGreaterThan(middle, 0.5)
        XCTAssertGreaterThan(middle, near)
        XCTAssertGreaterThan(far, middle)
    }

    func testVeryLittleLightSpillsBelowTheSlit() {
        let above = LampBeamProfile.illumination(x: 0, rise: 14)
        let below = LampBeamProfile.illumination(x: 0, rise: -14)
        XCTAssertGreaterThan(above, 0.9)
        XCTAssertLessThan(below, 0.02)
        XCTAssertLessThan(below, above * 0.03)
        XCTAssertLessThan(LampBeamProfile.illumination(x: 30, rise: -14), 0.01)
    }

    func testBitmapEdgesFadeToTransparentWithoutASeam() {
        let side = Double(LampBeamProfile.width) / 2
        let bottomRise = LampBeamProfile.sourceY - Double(LampBeamProfile.height)
        for rise in stride(from: bottomRise, through: LampBeamProfile.sourceY, by: 8) {
            XCTAssertEqual(LampBeamProfile.illumination(x: -side, rise: rise), 0)
            XCTAssertEqual(LampBeamProfile.illumination(x: side, rise: rise), 0)
            XCTAssertLessThan(LampBeamProfile.illumination(x: side - 1, rise: rise), 0.001)
        }
        for x in stride(from: -side, through: side, by: 8) {
            XCTAssertEqual(LampBeamProfile.illumination(x: x, rise: LampBeamProfile.sourceY), 0)
            XCTAssertEqual(LampBeamProfile.illumination(x: x, rise: bottomRise), 0)
            XCTAssertLessThan(LampBeamProfile.illumination(x: x, rise: LampBeamProfile.sourceY - 1), 0.001)
            XCTAssertLessThan(LampBeamProfile.illumination(x: x, rise: bottomRise + 1), 0.001)
        }
    }

    func testProfileIsSymmetricFiniteAndBoundedAcrossItsFootprint() {
        for rise in stride(from: -30.0, through: 450, by: 10) {
            for x in stride(from: 0.0, through: 380, by: 10) {
                let value = LampBeamProfile.illumination(x: x, rise: rise)
                XCTAssertTrue(value.isFinite)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
                XCTAssertEqual(value, LampBeamProfile.illumination(x: -x, rise: rise), accuracy: 0.000_001)
            }
        }
    }

    func testNonfiniteAndOutOfBoundsCoordinatesProduceNoLight() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(LampBeamProfile.illumination(x: value, rise: 70), 0)
            XCTAssertEqual(LampBeamProfile.illumination(x: 0, rise: value), 0)
        }
        XCTAssertEqual(LampBeamProfile.illumination(x: Double.greatestFiniteMagnitude, rise: 0), 0)
        XCTAssertEqual(LampBeamProfile.illumination(x: 0, rise: Double.greatestFiniteMagnitude), 0)
        XCTAssertEqual(LampBeamProfile.illumination(x: 0, rise: -Double.greatestFiniteMagnitude), 0)
    }
}
