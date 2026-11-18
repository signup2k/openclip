// PopupRadialLayout.swift
// OpenClip
//
// Geometry shared by radial menu drawing and pointer hit-testing. All coordinates use
// SwiftUI's top-left origin; item zero sits at twelve o'clock and items proceed clockwise.
import SwiftUI

public enum PopupLayoutStyle: String, Sendable {
    case horizontal
    case radial

    public static func resolve(_ storedValue: String) -> Self {
        Self(rawValue: storedValue) ?? .horizontal
    }
}

struct PopupRadialLayout {
    let itemCount: Int
    var scale: CGFloat = 1

    var outerRadius: CGFloat { PopupMetrics.radialOuterRadius * scale }
    var innerRadius: CGFloat { PopupMetrics.radialInnerRadius * scale }
    var diameter: CGFloat { outerRadius * 2 }
    var center: CGPoint { CGPoint(x: outerRadius, y: outerRadius) }
    var step: Double { 2 * .pi / Double(max(1, itemCount)) }
    var labelWidth: CGFloat {
        let chord = (innerRadius + outerRadius) * sin(.pi / Double(max(2, itemCount)))
        return max(28 * scale, min(44 * scale, chord - 4 * scale))
    }

    func angle(for index: Int) -> Double {
        -.pi / 2 + Double(index) * step
    }

    func labelPosition(for index: Int) -> CGPoint {
        let radius = (innerRadius + outerRadius) / 2
        let angle = angle(for: index)
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// The entire annular sector is a target, including the space between icons. The central
    /// hub and transparent corners deliberately resolve to no action.
    func itemIndex(at point: CGPoint) -> Int? {
        guard itemCount > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        let angle = atan2(dy, dx) + .pi / 2 + step / 2
        let wrapped = (angle.truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)
        return min(itemCount - 1, Int(wrapped / step))
    }

    func panelItemIndex(at point: CGPoint) -> Int? {
        let inset = PopupMetrics.popupShadowInset
        return itemIndex(at: CGPoint(x: point.x - inset, y: point.y - inset))
    }

    static func pages<Item>(for items: [Item]) -> [[Item]] {
        guard !items.isEmpty else { return [[]] }
        return stride(from: 0, to: items.count, by: PopupMetrics.radialPageSize).map {
            Array(items[$0..<min($0 + PopupMetrics.radialPageSize, items.count)])
        }
    }
}

struct PopupRadialSector: Shape {
    let index: Int
    let itemCount: Int
    let innerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        guard itemCount > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let step = 2 * Double.pi / Double(itemCount)
        let start = -Double.pi / 2 + Double(index) * step - step / 2
        let end = start + step
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        path.addArc(center: center, radius: radius * innerRadiusRatio,
                    startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}
