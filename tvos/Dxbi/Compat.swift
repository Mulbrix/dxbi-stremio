// dx.bi — Copyright (C) 2026 dx.bi. GNU General Public License, version 3 or later (see LICENSE).
import SwiftUI

// The iPhone app's look helpers (ios/Dxbi/UI/Compat.swift), as the shared views (Theme, Cards) use
// them, the Apple TV way: frosted material and tvOS's own button styles, which take the remote's focus.

extension View {
    @ViewBuilder
    func dxGlass<S: Shape>(interactive: Bool = false, hidden: Bool = false, in shape: S) -> some View {
        if hidden { self } else { self.background(.ultraThinMaterial, in: shape) }
    }

    func dxGlassButton() -> some View { buttonStyle(.bordered) }

    func dxGlassProminentButton() -> some View { buttonStyle(.borderedProminent) }
}
