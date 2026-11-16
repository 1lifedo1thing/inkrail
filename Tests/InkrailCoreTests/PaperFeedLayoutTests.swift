import XCTest
@testable import InkrailCore

final class PaperFeedLayoutTests: XCTestCase {
    func testRollRetainsIndependentTopAndBottomGeometryAcrossWindowSizes() {
        for paperHeight in [440.0, 520.0, 708.0, 900.0] {
            let top = PaperFeedLayout.editorHeight(paperHeight: paperHeight, position: .top, motion: .roll)
            let bottom = PaperFeedLayout.editorHeight(paperHeight: paperHeight, position: .bottom, motion: .roll)
            XCTAssertGreaterThan(top, bottom)
            for position in PaperStartPosition.allCases {
                XCTAssertEqual(PaperFeedLayout.editorHeight(paperHeight: paperHeight, position: position, motion: .roll),
                               PaperFeedLayout.editorHeight(paperHeight: paperHeight, position: position, motion: .sheet))
            }
            let topStart = PaperFeedLayout.topInset(viewportHeight: top, lineHeight: 24, position: .top) + 24
            let bottomStart = PaperFeedLayout.topInset(viewportHeight: bottom, lineHeight: 24, position: .bottom) + 24
            XCTAssertLessThan(topStart, bottomStart)
            XCTAssertEqual(bottomStart, paperHeight - 176)
        }
    }

    func testDefaultPaperKeepsBothModesAboveTheSameMechanismBand() {
        let topHeight = PaperFeedLayout.editorHeight(paperHeight: 708, position: .top)
        let bottomHeight = PaperFeedLayout.editorHeight(paperHeight: 708, position: .bottom)
        XCTAssertEqual(topHeight, 640)
        XCTAssertEqual(bottomHeight, 536)
        XCTAssertEqual(PaperFeedLayout.caretLimit(viewportHeight: topHeight, position: .top), 532)
        XCTAssertEqual(PaperFeedLayout.caretLimit(viewportHeight: bottomHeight, position: .bottom), 532)
        XCTAssertEqual(PaperFeedLayout.topInset(viewportHeight: topHeight, lineHeight: 24, position: .top), 68)
        XCTAssertEqual(PaperFeedLayout.topInset(viewportHeight: bottomHeight, lineHeight: 24, position: .bottom), 508)
    }

    func testMinimumAndResizedPaperKeepRoomBelowBottomWritingLine() {
        for paperHeight in [440.0, 708.0, 900.0] {
            let viewport = PaperFeedLayout.editorHeight(paperHeight: paperHeight, position: .bottom)
            let limit = PaperFeedLayout.caretLimit(viewportHeight: viewport, position: .bottom)
            let inset = PaperFeedLayout.topInset(viewportHeight: viewport, lineHeight: 28, position: .bottom)
            XCTAssertEqual(inset + 28, limit)
            XCTAssertEqual(viewport - limit, 4)
            XCTAssertEqual(paperHeight - limit, 176)
        }
        XCTAssertEqual(PaperFeedLayout.editorHeight(paperHeight: 440, position: .bottom), 268)
        XCTAssertEqual(PaperFeedLayout.editorHeight(paperHeight: 900, position: .bottom), 728)
    }

    func testAdvancingLinesFeedsTextUpWhileCaretStaysAtBottomBand() {
        let viewport = 536.0
        var offset = 0.0
        for caretBottom in [532.0, 556.0, 580.0, 604.0] {
            offset = PaperFeedLayout.desiredScrollOffset(caretBottom: caretBottom, currentOffset: offset,
                                                        viewportHeight: viewport, position: .bottom)
            XCTAssertEqual(caretBottom - offset, 532)
        }
        XCTAssertEqual(offset, 72)
    }

    func testDeletingLinesFeedsBackToFirstLineWithoutNegativeScroll() {
        var offset = 72.0
        for caretBottom in [580.0, 556.0, 532.0] {
            offset = PaperFeedLayout.desiredScrollOffset(caretBottom: caretBottom, currentOffset: offset,
                                                        viewportHeight: 536, position: .bottom)
            XCTAssertEqual(caretBottom - offset, 532)
        }
        XCTAssertEqual(offset, 0)
        XCTAssertEqual(PaperFeedLayout.desiredScrollOffset(caretBottom: 20, currentOffset: offset,
                                                          viewportHeight: 536, position: .bottom), 0)
    }

    func testTopModePreservesManualScrollAndOnlyFeedsWhenNeeded() {
        XCTAssertEqual(PaperFeedLayout.desiredScrollOffset(caretBottom: 300, currentOffset: 120,
                                                          viewportHeight: 640, position: .top), 120)
        XCTAssertEqual(PaperFeedLayout.desiredScrollOffset(caretBottom: 700, currentOffset: 120,
                                                          viewportHeight: 640, position: .top), 168)
        XCTAssertEqual(PaperFeedLayout.desiredScrollOffset(caretBottom: 68, currentOffset: 0,
                                                          viewportHeight: 640, position: .top), 0)
    }

    func testChangingModeRepositionsTheSameLogicalLine() {
        let logicalCaretBottom = 96.0
        let topCaret = 68 + logicalCaretBottom
        let bottomCaret = 508 + logicalCaretBottom
        let topOffset = PaperFeedLayout.desiredScrollOffset(caretBottom: topCaret, currentOffset: 0,
                                                          viewportHeight: 640, position: .top)
        let bottomOffset = PaperFeedLayout.desiredScrollOffset(caretBottom: bottomCaret, currentOffset: 0,
                                                             viewportHeight: 536, position: .bottom)
        XCTAssertEqual(topCaret - topOffset, 164)
        XCTAssertEqual(bottomCaret - bottomOffset, 532)
        XCTAssertEqual(topCaret - 68, bottomCaret - 508)
    }

    func testResizingReanchorsFirstLineAcrossRepresentativeLineHeights() {
        for viewportHeight in [268.0, 536.0, 728.0] {
            for lineHeight in [18.0, 24.0, 34.0] {
                let inset = PaperFeedLayout.topInset(viewportHeight: viewportHeight, lineHeight: lineHeight,
                                                    position: .bottom)
                let caretBottom = inset + lineHeight
                XCTAssertEqual(caretBottom, viewportHeight - 4)
                XCTAssertEqual(PaperFeedLayout.desiredScrollOffset(caretBottom: caretBottom, currentOffset: 0,
                                                                  viewportHeight: viewportHeight, position: .bottom), 0)
            }
        }
    }

    func testDegenerateDimensionsNeverCreateNegativeInsetsOrViewportHeights() {
        for position in PaperStartPosition.allCases {
            for size in [-10.0, 0.0, 1.0, Double.nan, Double.infinity] {
                XCTAssertGreaterThanOrEqual(PaperFeedLayout.editorHeight(paperHeight: size, position: position), 1)
                XCTAssertGreaterThanOrEqual(PaperFeedLayout.caretLimit(viewportHeight: size, position: position), 1)
                XCTAssertGreaterThanOrEqual(PaperFeedLayout.topInset(viewportHeight: size, lineHeight: 1000,
                                                                   position: position), 68)
            }
        }
    }
}
