import SwiftUI
import AppKit

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general
        case appUpdate
        case epsilonUpdate
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .appUpdate: return "App Update"
            case .epsilonUpdate: return "Epsilon Update"
            case .about: return "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .appUpdate: return "arrow.triangle.2.circlepath"
            case .epsilonUpdate: return "terminal"
            case .about: return "info.circle"
            }
        }
    }

    struct Pane: Identifiable {
        let tab: Tab
        let view: AnyView
        var id: String { tab.id }
    }

    @State private var selection: Tab = .general

    private let panes: [Pane] = [
        .init(tab: .general, view: AnyView(GeneralSettingsPane())),
        .init(tab: .appUpdate, view: AnyView(AppUpdateSettingsPane())),
        .init(tab: .epsilonUpdate, view: AnyView(EpsilonUpdateSettingsPane())),
        .init(tab: .about, view: AnyView(AboutSettingsPane())),
    ]

    var body: some View {
        TabView(selection: $selection) {
            ForEach(panes) { pane in
                pane.view
                    .tag(pane.tab)
                    .tabItem { Label(pane.tab.title, systemImage: pane.tab.systemImage) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(minWidth: 620, minHeight: 420)
    }
}

private struct GeneralSettingsPane: View {
    @StateObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show menu bar icon", isOn: $prefs.isMenuBarIconEnabled)

                Toggle("Keep app pinned", isOn: $prefs.isPinned)
            }

            Section("Appearance") {
                Picker("Menu bar icon style", selection: $prefs.menuBarIconStyle) {
                    Text("Filled").tag(MenuBarIconStyle.filled)
                    Text("Outline").tag(MenuBarIconStyle.outline)
                }

                Stepper(value: $prefs.menuBarIconSize, in: 12...28, step: 1) {
                    HStack {
                        Text("Menu bar icon size")
                        Spacer()
                        Text("\(Int(prefs.menuBarIconSize))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .navigationTitle("General")
    }
}

private struct AppUpdateSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Update")
                .font(.title2)
                .bold()

            Text("Add your updater settings here.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
    }
}

private struct EpsilonUpdateSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Epsilon Update")
                .font(.title2)
                .bold()

            Text("Add Epsilon-specific update options here.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2)
                .bold()

            Text("Build info, credits, links, etc.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
    }
}

#Preview {
    SettingsView()
}
