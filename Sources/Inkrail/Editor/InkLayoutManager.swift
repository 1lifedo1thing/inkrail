import AppKit
import InkrailCore

/// Keep native glyph shaping, hit testing and selection. Only ASCII ink gets
/// deterministic pressure, overprint and registration variation. Complex
/// graphemes, ligatures and emoji use the unmodified AppKit drawing path.
final class InkLayoutManager: NSLayoutManager {
    var wornInk = true
    var inkBuildup = 0.55
    var composing = false
    var paperRollEnabled = false
    private var resolvingProjectedPoint = false

    private var rollGeometry: (projection: PaperRollProjection, clip: NSRect, origin: NSPoint)? {
        guard paperRollEnabled, let view = textContainers.first?.textView,
              let clip = view.enclosingScrollView?.contentView,
              clip.bounds.width > 0, clip.bounds.height > 0 else { return nil }
        return (PaperRollProjection(width: clip.bounds.width, viewportHeight: clip.bounds.height),
                clip.bounds, view.textContainerOrigin)
    }

    /// Public rectangles use native document coordinates, as does NSTextView.
    func projectedRect(_ rect: NSRect) -> NSRect {
        guard let geometry = rollGeometry else { return rect }
        if let line = rawLine(at: NSPoint(x: rect.midX, y: rect.midY), origin: geometry.origin),
           line.height > 0 {
            let top = line.minY + geometry.origin.y - geometry.clip.minY
            let bottom = line.maxY + geometry.origin.y - geometry.clip.minY
            let scaleY = max(0.001, (geometry.projection.projectY(bottom) - geometry.projection.projectY(top)) / line.height)
            let scaleX = geometry.projection.horizontalScale(at: (top + bottom) / 2)
            return NSRect(x: geometry.projection.width / 2 + (rect.minX - geometry.projection.width / 2) * scaleX,
                          y: geometry.clip.minY + geometry.projection.projectY(top)
                            + (rect.minY - geometry.origin.y - line.minY) * scaleY,
                          width: rect.width * scaleX, height: rect.height * scaleY)
        }
        let top = rect.minY - geometry.clip.minY
        let bottom = rect.maxY - geometry.clip.minY
        let xs = [geometry.projection.projectX(rect.minX, at: top),
                  geometry.projection.projectX(rect.maxX, at: top),
                  geometry.projection.projectX(rect.minX, at: bottom),
                  geometry.projection.projectX(rect.maxX, at: bottom)]
        let y = geometry.projection.projectY(top) + geometry.clip.minY
        return NSRect(x: xs.min() ?? rect.minX, y: y,
                      width: (xs.max() ?? rect.maxX) - (xs.min() ?? rect.minX),
                      height: geometry.projection.projectY(bottom) - geometry.projection.projectY(top))
    }

    func unprojectedPoint(_ point: NSPoint) -> NSPoint {
        guard let geometry = rollGeometry else { return point }
        let rawY = geometry.projection.unprojectY(point.y - geometry.clip.minY)
        let approximate = NSPoint(x: geometry.projection.unprojectX(point.x, at: rawY),
                                  y: rawY + geometry.clip.minY)
        guard let line = rawLine(at: approximate, origin: geometry.origin), line.height > 0 else { return approximate }
        let top = line.minY + geometry.origin.y - geometry.clip.minY
        let bottom = line.maxY + geometry.origin.y - geometry.clip.minY
        let scaleY = max(0.001, (geometry.projection.projectY(bottom) - geometry.projection.projectY(top)) / line.height)
        let scaleX = geometry.projection.horizontalScale(at: (top + bottom) / 2)
        return NSPoint(x: geometry.projection.width / 2 + (point.x - geometry.projection.width / 2) / scaleX,
                       y: geometry.origin.y + line.minY
                         + (point.y - geometry.clip.minY - geometry.projection.projectY(top)) / scaleY)
    }

    private func rawLine(at point: NSPoint, origin: NSPoint) -> NSRect? {
        guard let container = textContainers.first else { return nil }
        let native = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        if extraLineFragmentTextContainer === container,
           native.y >= extraLineFragmentRect.minY { return extraLineFragmentRect }
        guard numberOfGlyphs > 0 else { return nil }
        let nested = resolvingProjectedPoint
        resolvingProjectedPoint = true
        defer { resolvingProjectedPoint = nested }
        let glyph = super.glyphIndex(for: native, in: container, fractionOfDistanceThroughGlyph: nil)
        return lineFragmentRect(forGlyphAt: min(glyph, numberOfGlyphs - 1), effectiveRange: nil)
    }

    private func nativePoint(_ point: NSPoint) -> NSPoint {
        guard let geometry = rollGeometry, !resolvingProjectedPoint else { return point }
        let document = NSPoint(x: point.x + geometry.origin.x, y: point.y + geometry.origin.y)
        let raw = unprojectedPoint(document)
        return NSPoint(x: raw.x - geometry.origin.x, y: raw.y - geometry.origin.y)
    }

    override func glyphIndex(for point: NSPoint, in container: NSTextContainer,
                             fractionOfDistanceThroughGlyph partialFraction: UnsafeMutablePointer<CGFloat>?) -> Int {
        let mapped = nativePoint(point)
        let nested = resolvingProjectedPoint
        resolvingProjectedPoint = true
        defer { resolvingProjectedPoint = nested }
        return super.glyphIndex(for: mapped, in: container, fractionOfDistanceThroughGlyph: partialFraction)
    }

    override func glyphIndex(for point: NSPoint, in container: NSTextContainer) -> Int {
        let mapped = nativePoint(point)
        let nested = resolvingProjectedPoint
        resolvingProjectedPoint = true
        defer { resolvingProjectedPoint = nested }
        return super.glyphIndex(for: mapped, in: container)
    }

    override func characterIndex(for point: NSPoint, in container: NSTextContainer,
                                 fractionOfDistanceBetweenInsertionPoints partialFraction: UnsafeMutablePointer<CGFloat>?) -> Int {
        let mapped = nativePoint(point)
        let nested = resolvingProjectedPoint
        resolvingProjectedPoint = true
        defer { resolvingProjectedPoint = nested }
        return super.characterIndex(for: mapped, in: container, fractionOfDistanceBetweenInsertionPoints: partialFraction)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawRolledLines(glyphsToShow, at: origin) { range in
            super.drawBackground(forGlyphRange: range, at: origin)
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawRolledLines(glyphsToShow, at: origin) { range in
            self.drawInkGlyphs(forGlyphRange: range, at: origin)
        }
    }

    /// Draw real TextKit line fragments, including native selection/marked
    /// backgrounds, under the same small affine transforms. Expanding the
    /// requested range lets older lines remain visible over the rounded lip;
    /// no second text view or raster copy participates in editing.
    private func drawRolledLines(_ requested: NSRange, at origin: NSPoint,
                                 draw: @escaping (NSRange) -> Void) {
        guard let geometry = rollGeometry, let container = textContainers.first,
              let context = NSGraphicsContext.current?.cgContext else {
            draw(requested)
            return
        }
        let projection = geometry.projection
        let extra = projection.bendHeight
        let visible = NSRect(x: 0, y: geometry.clip.minY - extra - origin.y,
                             width: container.containerSize.width,
                             height: geometry.clip.height + extra)
        let wasResolving = resolvingProjectedPoint
        resolvingProjectedPoint = true
        let range = glyphRange(forBoundingRect: visible, in: container)
        resolvingProjectedPoint = wasResolving
        guard range.length > 0 else { return }
        enumerateLineFragments(forGlyphRange: range) { line, _, _, glyphRange, _ in
            let top = line.minY + origin.y - geometry.clip.minY
            let bottom = line.maxY + origin.y - geometry.clip.minY
            let projectedTop = projection.projectY(top)
            let projectedBottom = projection.projectY(bottom)
            guard projectedBottom > 0, projectedTop < geometry.clip.height,
                  line.height > 0 else { return }
            let scaleY = max(0.001, (projectedBottom - projectedTop) / line.height)
            let scaleX = projection.horizontalScale(at: (top + bottom) / 2)
            context.saveGState()
            context.translateBy(x: projection.width / 2 * (1 - scaleX),
                                y: projectedTop + geometry.clip.minY - (line.minY + origin.y) * scaleY)
            context.scaleBy(x: scaleX, y: scaleY)
            draw(glyphRange)
            context.restoreGState()
        }
    }

    private func drawInkGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard wornInk, !composing, let storage = textStorage,
              let context = NSGraphicsContext.current?.cgContext else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let source = storage.string as NSString
        var glyph = glyphsToShow.location
        let limit = NSMaxRange(glyphsToShow)
        while glyph < limit {
            let character = characterIndexForGlyph(at: glyph)
            guard character < source.length else {
                super.drawGlyphs(forGlyphRange: NSRange(location: glyph, length: limit - glyph), at: origin)
                break
            }
            let scalar = source.character(at: character)
            if isSimpleInkGlyph(glyph, source: source) {
                let font = storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont
                let impression = InkImpression(characterIndex: character, codeUnit: scalar,
                    buildup: inkBuildup, pointSize: Double(font?.pointSize ?? 20))
                let range = NSRange(location: glyph, length: 1)
                context.saveGState()
                context.translateBy(x: impression.offsetX, y: impression.offsetY)
                if impression.spread > 0 {
                    // A few ink-loaded strikes spread asymmetrically. Redraw
                    // native glyphs at subpoint offsets, preserving their shape,
                    // ribbon colour and advances (never substitute bold fonts).
                    context.setAlpha(impression.spreadOpacity)
                    let spread = impression.spread
                    for (x, y) in [(spread, spread * 0.12),
                                   (-spread * 0.60, spread * 0.45),
                                   (spread * 0.10, -spread * 0.55)] {
                        super.drawGlyphs(forGlyphRange: range,
                                         at: NSPoint(x: origin.x + x, y: origin.y + y))
                    }
                }
                context.setAlpha(impression.opacity)
                super.drawGlyphs(forGlyphRange: range, at: origin)
                context.restoreGState()
                glyph += 1
            } else {
                let start = glyph
                glyph += 1
                while glyph < limit {
                    if isSimpleInkGlyph(glyph, source: source) { break }
                    glyph += 1
                }
                super.drawGlyphs(forGlyphRange: NSRange(location: start, length: glyph - start), at: origin)
            }
        }
    }

    /// ASCII bases can belong to non-ASCII graphemes (e + combining acute),
    /// and native shaping can map multiple characters to one glyph. Do not
    /// separate or overprint either case, or any whitespace/control glyph.
    private func isSimpleInkGlyph(_ glyph: Int, source: NSString) -> Bool {
        let character = characterIndexForGlyph(at: glyph)
        guard character < source.length else { return false }
        let scalar = source.character(at: character)
        guard scalar >= 33 && scalar < 127,
              source.rangeOfComposedCharacterSequence(at: character).length == 1 else { return false }
        var actualGlyphs = NSRange()
        let characters = characterRange(forGlyphRange: NSRange(location: glyph, length: 1),
                                        actualGlyphRange: &actualGlyphs)
        return characters.length == 1 && actualGlyphs == NSRange(location: glyph, length: 1)
    }
}
