import Foundation
import GameController

/// Maps MFi / Xbox / PlayStation controllers to Game Boy buttons.
final class ControllerManager {
    var onButton: ((GBButton, Bool) -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            if let controller = note.object as? GCController { self?.attach(controller) }
        }
        for controller in GCController.controllers() { attach(controller) }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }

        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.onButton?(.left, x < -0.5)
            self?.onButton?(.right, x > 0.5)
            self?.onButton?(.down, y < -0.5)
            self?.onButton?(.up, y > 0.5)
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.onButton?(.left, x < -0.5)
            self?.onButton?(.right, x > 0.5)
            self?.onButton?(.down, y < -0.5)
            self?.onButton?(.up, y > 0.5)
        }
        // Bottom face button -> B, right face button -> A (matches physical layout).
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in self?.onButton?(.b, pressed) }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in self?.onButton?(.a, pressed) }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in self?.onButton?(.b, pressed) }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in self?.onButton?(.a, pressed) }
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in self?.onButton?(.start, pressed) }
        pad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in self?.onButton?(.select, pressed) }
    }
}
