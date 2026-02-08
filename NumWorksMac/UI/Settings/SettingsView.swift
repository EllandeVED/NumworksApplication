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
        .frame(minWidth: 420, minHeight: 420)
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
            Section {
                Text("Shortcuts")
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    KeyboardShortcuts.Recorder(for: .hideShowApp)
                    Text("Hide / Show App")
                }

                HStack(spacing: 12) {
                    KeyboardShortcuts.Recorder(for: .pinUnpinApp)
                    Text("Pin / Unpin App")
                }
            }

            Section {
                Text("Startup")
                    .fontWeight(.bold)

                LaunchAtLogin.Toggle()
                    .onAppear {
                        let key = "didSetDefaultLaunchAtLogin"
                        if !UserDefaults.standard.bool(forKey: key) {
                            LaunchAtLogin.isEnabled = true
                            UserDefaults.standard.set(true, forKey: key)
                        }
                    }
            }

            Section {
                Text("Interface")
                    .fontWeight(.bold)

                Toggle("Show Menu Bar Icon", isOn: $prefs.isMenuBarIconEnabled)
                Toggle("Show Pin/Unpin button on Calculator", isOn: $prefs.showPinButtonOnCalculator)
                Toggle("Show Dock Icon", isOn: $prefs.showDockIcon)
            }

            Section {
                Text("Preferred Icon")
                    .fontWeight(.bold)

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
    @State private var currentSimulatorVersion: String = ""
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Epsilon Update")
                .font(.title2)
                .bold()

            HStack(spacing: 8) {
                Text("Current version:")
                Text(currentSimulatorVersion)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            Button {
                checkForUpdates()
            } label: {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Check for updates")
                }
            }
            .disabled(isChecking)

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
        .onAppear {
            currentSimulatorVersion = simulatorVersionString()
        }
    }

    private func simulatorVersionString() -> String {
        UserDefaults.standard.string(forKey: "installedSimulatorVersion") ?? EpsilonVersions.bundledSimulator
    }

    private func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        Task { @MainActor in
            defer { isChecking = false }
            do {
                let current = simulatorVersionString()
                let report = try await EpsilonUpdateChecker.checkLatest(currentVersionString: current)

                if report.needsUpdate {
                    NotificationCenter.default.post(
                        name: .requestEpsilonUpdateUI,
                        object: nil,
                        userInfo: [
                            "remoteURL": report.remoteURL,
                            "remoteVersion": report.remoteVersion.string,
                            "required": false
                        ]
                    )
                }

                currentSimulatorVersion = simulatorVersionString()
            } catch {
                print("[Settings] epsilon update check failed: \(error)")
            }
        }
    }
}

private struct AboutSettingsPane: View {
    private let repoURL = URL(string: "https://github.com/EllandeVED/NumworksApplication")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2)
                .bold()

            HStack(spacing: 8) {
                Text("App version")
                    .fontWeight(.bold)
                Text(appVersionString())
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("Running on Epsilon")
                Text(simulatorVersionString())
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 6)

            HStack(spacing: 8) {
                Text("Made by")
                    .fontWeight(.bold)
                Text("Ellande VED")
            }

            Link("See on GitHub: NumworksApplication", destination: repoURL)

            Link("Report an issue/request: Report", destination: repoURL)

            Divider().padding(.vertical, 6)

            Button {
                MITLiscence.present()
            } label: {
                Text("MIT LISCENCE")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

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

    private func appVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        ?? ""
    }

    private func simulatorVersionString() -> String {
        UserDefaults.standard.string(forKey: "installedSimulatorVersion") ?? EpsilonVersions.bundledSimulator
    }
}

extension KeyboardShortcuts.Name {
    static let hideShowApp = Self("hideShowApp")
    static let pinUnpinApp = Self("pinUnpinApp")
}

extension Notification.Name {
    static let settingsWindowDidAppear = Notification.Name("settingsWindowDidAppear")
    static let settingsWindowDidDisappear = Notification.Name("settingsWindowDidDisappear")
}

