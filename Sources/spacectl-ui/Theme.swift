import SwiftUI

/// Dark palette taken from the app icon: near-black navy surfaces with a violet accent.
enum Theme {
    static let bg = Color(red: 0.082, green: 0.082, blue: 0.114)
    static let sidebar = Color(red: 0.063, green: 0.063, blue: 0.090)
    static let card = Color(red: 0.110, green: 0.110, blue: 0.153)
    static let raised = Color(red: 0.137, green: 0.137, blue: 0.188)
    static let border = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.55)
    static let accent = Color(red: 0.49, green: 0.36, blue: 1.0)
    static let teal = Color(red: 0.35, green: 0.90, blue: 0.80)
}

/// Spacelift stack and run states mapped to one color, shared by pills and sidebar dots.
func stateColor(_ state: String?) -> Color {
    switch state ?? "" {
    case "FINISHED": return .green
    case "FAILED": return .red
    case "UNCONFIRMED", "PENDING_REVIEW": return .orange
    case "PLANNING", "APPLYING", "INITIALIZING", "PREPARING", "PREPARING_APPLY",
         "PERFORMING", "DESTROYING", "QUEUED", "READY", "PENDING", "CONFIRMED": return Theme.accent
    case "DISCARDED", "CANCELED", "STOPPED", "SKIPPED": return .gray
    default: return .secondary
    }
}

func prettyState(_ state: String?) -> String {
    (state ?? "UNKNOWN").replacingOccurrences(of: "_", with: " ").capitalized
}

/// Every `GroupBox` in the app renders as a rounded card with a small uppercase caption.
struct CardStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.muted)
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}

extension View {
    /// Rounded surface for tables: a card on its own tab, a darker well when nested in a card.
    func tableSurface(embedded: Bool) -> some View {
        self.scrollContentBackground(.hidden)
            .background(embedded ? Theme.bg : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            .padding(embedded ? 0 : 16)
    }
}

extension DetailTab {
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .history: return "clock.arrow.circlepath"
        case .logs: return "doc.text"
        case .live: return "dot.radiowaves.left.and.right"
        case .outputs: return "arrow.up.right.square"
        case .environment: return "slider.horizontal.3"
        case .everything: return "square.stack.3d.up"
        }
    }
}
