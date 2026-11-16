/// Geometry shared by the native editor and its paper-stage host.
/// Positions and sizes use points in a top-origin coordinate system.
public enum PaperFeedLayout {
    /// Start position and paper treatment are independent. Bottom ends the
    /// native viewport just below its lower writing line; Top leaves room
    /// for the line to advance down the sheet before automatic feeding.
    public static func editorHeight(paperHeight: Double, position: PaperStartPosition,
                                    motion _: PaperMotion = .sheet) -> Double {
        return max(1, finite(paperHeight) - (position == .bottom ? 172 : 68))
    }

    /// Maximum visible caret bottom, measured from the viewport's top edge.
    public static func caretLimit(viewportHeight: Double, position: PaperStartPosition) -> Double {
        let height = finite(viewportHeight)
        return position == .bottom ? max(1, height - 4) : max(100, height - 108)
    }

    /// Leading whitespace places an empty bottom-starting letter at the feed
    /// line without inserting whitespace characters into the document.
    public static func topInset(viewportHeight: Double, lineHeight: Double,
                                position: PaperStartPosition) -> Double {
        guard position == .bottom else { return 68 }
        return max(68, caretLimit(viewportHeight: viewportHeight, position: position)
                   - max(0, finite(lineHeight)))
    }

    /// Desired clip origin for a caret measured in document coordinates.
    /// The native scroll view remains responsible for constraining the result
    /// to the actual document extent. Top mode preserves an existing offset;
    /// bottom mode feeds backward as text is deleted as well as forward.
    public static func desiredScrollOffset(caretBottom: Double, currentOffset: Double,
                                           viewportHeight: Double,
                                           position: PaperStartPosition) -> Double {
        let required = caretBottom - caretLimit(viewportHeight: viewportHeight, position: position)
        if position == .bottom { return max(0, required) }
        return max(0, max(currentOffset, required))
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
