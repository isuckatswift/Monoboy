import SwiftUI
import UIKit

private func haptic() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

/// A touch D-pad: slide your thumb around for diagonals.
struct DPadView: View {
    let onButton: (GBButton, Bool) -> Void
    var size: CGFloat = 150

    @State private var active: Set<GBButton> = []

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.16))
                .frame(width: size, height: size / 3)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.16))
                .frame(width: size / 3, height: size)
            arrow("arrowtriangle.up.fill", .up, x: 0, y: -size / 3)
            arrow("arrowtriangle.down.fill", .down, x: 0, y: size / 3)
            arrow("arrowtriangle.left.fill", .left, x: -size / 3, y: 0)
            arrow("arrowtriangle.right.fill", .right, x: size / 3, y: 0)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { update($0.location) }
                .onEnded { _ in update(nil) }
        )
    }

    private func arrow(_ name: String, _ button: GBButton, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.11))
            .foregroundColor(active.contains(button) ? .white : Color(white: 0.45))
            .offset(x: x, y: y)
    }

    private func update(_ point: CGPoint?) {
        var next: Set<GBButton> = []
        if let point {
            let dx = point.x - size / 2
            let dy = point.y - size / 2
            let dead = size * 0.12
            if dx > dead { next.insert(.right) }
            if dx < -dead { next.insert(.left) }
            if dy > dead { next.insert(.down) }
            if dy < -dead { next.insert(.up) }
        }
        guard next != active else { return }
        for button in active.subtracting(next) { onButton(button, false) }
        let newlyPressed = next.subtracting(active)
        for button in newlyPressed { onButton(button, true) }
        if !newlyPressed.isEmpty { haptic() }
        active = next
    }
}

/// A round (A / B) or pill-shaped (Select / Start) press-and-hold button.
struct PressButton: View {
    let label: String
    let button: GBButton
    let onButton: (GBButton, Bool) -> Void
    var diameter: CGFloat = 70
    var isPill = false

    @State private var isDown = false

    var body: some View {
        Group {
            if isPill {
                Capsule()
                    .fill(isDown ? Color(white: 0.5) : Color(white: 0.2))
                    .frame(width: diameter * 1.2, height: diameter * 0.45)
            } else {
                Circle()
                    .fill(isDown ? Color(white: 0.5) : Color(white: 0.2))
                    .frame(width: diameter, height: diameter)
            }
        }
        .overlay(
            Text(label)
                .font(.system(size: isPill ? 11 : 22, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isDown else { return }
                    isDown = true
                    onButton(button, true)
                    haptic()
                }
                .onEnded { _ in
                    isDown = false
                    onButton(button, false)
                }
        )
    }
}

/// A and B in the classic diagonal arrangement.
struct ActionButtonsView: View {
    let onButton: (GBButton, Bool) -> Void
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            PressButton(label: "B", button: .b, onButton: onButton, diameter: size * 0.46)
                .offset(x: -size * 0.24, y: size * 0.14)
            PressButton(label: "A", button: .a, onButton: onButton, diameter: size * 0.46)
                .offset(x: size * 0.24, y: -size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

struct MenuButtonsView: View {
    let onButton: (GBButton, Bool) -> Void

    var body: some View {
        HStack(spacing: 24) {
            PressButton(label: "SELECT", button: .select, onButton: onButton, diameter: 64, isPill: true)
            PressButton(label: "START", button: .start, onButton: onButton, diameter: 64, isPill: true)
        }
    }
}
