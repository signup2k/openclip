import CoreGraphics

/// The parent of the current hover sub-bar.
public struct ActiveSubGroupState: Sendable {
    public let groupID: String
    public let parentIndex: Int
    public let parentButtonFrame: CGRect
}
