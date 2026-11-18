import CoreGraphics

public struct TextResult: Sendable {
    public let text: String
    public let bounds: CGRect?
    public let html: String?
    public let rtf: String?

    public init(text: String, bounds: CGRect? = nil, html: String? = nil, rtf: String? = nil) {
        self.text = text
        self.bounds = bounds
        self.html = html
        self.rtf = rtf
    }
}
