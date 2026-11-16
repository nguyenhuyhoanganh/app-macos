import SwiftUI

/// On the macOS 27 SDK `@State` resolves to a macro whose plugin ships only with
/// Xcode. Naming the property wrapper through an alias builds with Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
