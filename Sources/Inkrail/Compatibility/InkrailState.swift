import SwiftUI

// SDK 27 also uses the spelling @State for a compiler macro. Some standalone
// Command Line Tools installations lack its SwiftUIMacros plugin. This alias
// deliberately selects Apple's existing State *property wrapper*, not that
// macro. SwiftUI still owns storage, view invalidation and projected bindings.
// Preserve the original eager-initialization behavior of this macOS 13 app;
// do not use this as a substitute for the newer macro's lazy initialization.
typealias InkrailState<Value> = SwiftUI.State<Value>
