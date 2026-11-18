/// Geometry shared by the native editor and its paper-stage host.
/// Positions and sizes use points in a top-origin coordinate system.
public enum PaperFeedLayout {
    // Space for the mechanism and footer beneath the native scroll view.
    // Top gives the reader a little more room below the writing line.
    private static func spaceBelowEditor(_ position: PaperStartPosition) -> Double {
        position == .bottom ? 172 : 148
    }

    public static func editorHeight(paperHeight: Double, position: PaperStartPosition,
                                    motion _: PaperMotion = .sheet) -> Double {
        return max(1, finite(paperHeight) - spaceBelowEditor(position))
    }

    /// Maximum visible caret bottom, measured from the viewport's top edge.
    public static func caretLimit(viewportHeight: Double, position: PaperStartPosition) -> Double {
        let height = finite(viewportHeight)
        // Both modes feed at the same physical line, 176 pt above the paper's foot.
        let trailingSpace = 176 - spaceBelowEditor(position)
        return max(position == .bottom ? 1 : 100, height - trailingSpace)
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
