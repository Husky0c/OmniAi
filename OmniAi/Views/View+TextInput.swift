import SwiftUI

extension View {
    @ViewBuilder
    func omniNoAutocapitalization() -> some View {
#if canImport(UIKit)
        autocapitalization(.none)
#else
        self
#endif
    }

    @ViewBuilder
    func omniURLKeyboard() -> some View {
#if canImport(UIKit)
        keyboardType(.URL)
#else
        self
#endif
    }
}
