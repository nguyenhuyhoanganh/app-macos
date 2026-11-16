import SwiftUI

/// Trên SDK macOS 27, `@State` là macro mà plugin chỉ có trong Xcode.
/// Gọi property wrapper qua alias thì build được bằng Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
