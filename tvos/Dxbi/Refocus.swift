// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import AVKit
import UIKit

extension Notification.Name {
    /** The remote's focus wanted back on the screen showing (TitleView takes it to Play) */
    static let dxRefocus = Notification.Name("dxbi.refocus")
}

/**
 * Keeps the remote's focus on the app's screens. tvOS can leave it nowhere (or on the tab bar) when
 * the player closes, and again when the TV changes mode a moment later (Match Content going back to
 * the Apple TV's own): from there, Menu leaves the app instead of going back. So the focus is put
 * back after each of those, and Menu pressed with nothing focused only brings the focus back.
 */
@MainActor
enum Refocus {
    private static var watching = false
    private static let catcher = MenuCatcher()

    static func now() {
        if let root = keyWindow?.rootViewController {
            root.setNeedsFocusUpdate()
            root.updateFocusIfNeeded()
        }
        NotificationCenter.default.post(name: .dxRefocus, object: nil)
    }

    /** Once, when the app's screens are in their window */
    static func watch(_ window: UIWindow) {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(forName: .AVDisplayManagerModeSwitchEnd, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { now() }
            }
        }
        let menu = UITapGestureRecognizer(target: catcher, action: #selector(MenuCatcher.pressed))
        menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        menu.delegate = catcher
        catcher.window = window
        window.addGestureRecognizer(menu)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }
}

/** Menu with nothing focused: taken here (else tvOS takes it as leaving the app), and the focus put back */
@MainActor
private final class MenuCatcher: NSObject, UIGestureRecognizerDelegate {
    weak var window: UIWindow?

    @objc func pressed() { Refocus.now() }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let window else { return false }
        return UIFocusSystem.focusSystem(for: window)?.focusedItem == nil
    }
}
