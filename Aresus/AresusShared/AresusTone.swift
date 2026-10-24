import SwiftUI

extension AresusState {
    /// The status colour of a state (Shared/Design): green running, red issue, grey off. Used by the app's screens and
    /// the widget.
    var tone: StatusTone {
        switch self {
        case .issue: .issue
        case .active: .active
        case .inactive: .inactive
        }
    }
}
