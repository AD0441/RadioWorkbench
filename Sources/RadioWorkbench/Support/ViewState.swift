import SwiftUI

// The macOS 27 SDK exports both a State property wrapper and a State macro.
// CLT does not ship the SwiftUIMacros host plugin. This alias explicitly selects
// the stable public property wrapper and keeps state owned by the view.
typealias ViewState<Value> = SwiftUI.State<Value>
