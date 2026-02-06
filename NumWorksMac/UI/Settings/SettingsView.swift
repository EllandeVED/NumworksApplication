import SwiftUI
import AppKit
import KeyboardShortcuts
import LaunchAtLogin

private let settingsTitleSize: CGFloat = 30

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 620, minHeight: 420)
        .onAppear {
            NotificationCenter.default.post(name: .settingsWindowDidAppear, object: nil)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .settingsWindowDidDisappear, object: nil)
        }
    }
}

private struct GeneralSettingsPane: View {
    @StateObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Hide/Show App") {
                    KeyboardShortcuts.Recorder(for: .hideShowApp)
                }

                LabeledContent("Pin/Unpin App") {
                    KeyboardShortcuts.Recorder(for: .pinUnpinApp)
                }
            }

            Section("Startup") {
                LaunchAtLogin.Toggle()
                    .onAppear {
                        let key = "didSetDefaultLaunchAtLogin"
                        if !UserDefaults.standard.bool(forKey: key) {
                            LaunchAtLogin.isEnabled = true
                            UserDefaults.standard.set(true, forKey: key)
                        }
                    }
            }

            Section("Interface") {
                Toggle(
                    "Hide Menu Bar Icon",
                    isOn: Binding(
                        get: { !prefs.isMenuBarIconEnabled },
                        set: { prefs.isMenuBarIconEnabled = !$0 }
                    )
                )

                Toggle("Show Pin/Unpin button on Calculator", isOn: $prefs.showPinButtonOnCalculator)

                Toggle("Show Dock Icon", isOn: $prefs.showDockIcon)
            }

            Section("Preferred Icon") {
                HStack(spacing: 12) {
                    iconChoice(title: "Filled", style: .filled)
                    iconChoice(title: "Outline", style: .outline)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(16)
        .navigationTitle("") 
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NumWorks Settings")
                    .font(.system(size: settingsTitleSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func iconChoice(title: String, style: MenuBarIconStyle) -> some View {
        let selected = prefs.menuBarIconStyle == style

        Button {
            prefs.menuBarIconStyle = style
        } label: {
            HStack(spacing: 8) {
                Image(style.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(title)
            }
            .frame(minWidth: 120)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .gray.opacity(0.2))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(16)
        .navigationTitle("") 
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NumWorks Settings")
                    .font(.system(size: settingsTitleSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(16)
        .navigationTitle("") 
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NumWorks Settings")
                    .font(.system(size: settingsTitleSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(16)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NumWorks Settings")
                    .font(.system(size: settingsTitleSize, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

extension KeyboardShortcuts.Name {
    static let hideShowApp = Self("hideShowApp")
    static let pinUnpinApp = Self("pinUnpinApp")
}


//#Preview {
//    SettingsView()
//}
