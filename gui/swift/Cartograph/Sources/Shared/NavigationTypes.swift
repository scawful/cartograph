import SwiftUI

enum SidebarTab: Hashable {
    case dashboard
    case symbols
    case path(id: String)
    case graph
    case focus
}

enum SymbolKind: String, CaseIterable, Identifiable {
    case function
    case `class`
    case method
    case variable
    case module
    case constant
    case `import`

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .function: return "f.square"
        case .class: return "c.square"
        case .method: return "m.square"
        case .variable: return "v.square"
        case .module: return "shippingbox"
        case .constant: return "number.square"
        case .import: return "arrow.down.square"
        }
    }

    var color: Color {
        switch self {
        case .function: return .blue
        case .class: return .purple
        case .method: return .cyan
        case .variable: return .orange
        case .module: return .green
        case .constant: return .red
        case .import: return .gray
        }
    }
}
