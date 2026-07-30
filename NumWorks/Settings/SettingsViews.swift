import SwiftUI
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

/// Window/shortcut actions invoked from Settings, provided by AppController.
struct SettingsActions {
    let restoreDefaultSettings: () -> Void
    let checkForUpdates: () -> Void
}

enum SettingsTab: String {
    case general, window, shortcuts, advanced, about
}

struct SettingsRootView: View {
    @ObservedObject var preferences: Preferences
    let actions: SettingsActions

    @State private var selection = SettingsRootView.initialTab()

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(preferences: preferences, actions: actions)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            WindowToolbarSettingsView(preferences: preferences)
                .tabItem { Label("Window", systemImage: "macwindow") }
                .tag(SettingsTab.window)
            ShortcutSettingsView(preferences: preferences)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            AdvancedSettingsView(actions: actions)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.advanced)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 460, height: 520)
    }

    private static func initialTab() -> SettingsTab {
#if DEBUG
        for argument in ProcessInfo.processInfo.arguments {
            if argument.hasPrefix("--settings-tab="),
               let tab = SettingsTab(rawValue:
                   String(argument.dropFirst("--settings-tab=".count))) {
                return tab
            }
        }
#endif
        return .general
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var preferences: Preferences
    let actions: SettingsActions

    private var isInApplicationsFolder: Bool {
        Bundle.main.isInstalled
    }

    private var automaticUpdates: Binding<Bool> {
        Binding(
            get: { UpdateController.shared.automaticallyChecksForUpdates },
            set: { UpdateController.shared.automaticallyChecksForUpdates = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch NumWorks at login", isOn: $preferences.launchAtLogin)
                    .disabled(!Preferences.isLaunchAtLoginAvailable)
                Toggle("Show calculator when NumWorks launches",
                       isOn: $preferences.launchWindowVisible)
            } footer: {
                if !Preferences.isLaunchAtLoginAvailable {
                    Text("Launch at login requires the LaunchAtLogin package, "
                         + "which is missing from this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Show Dock icon", isOn: $preferences.showDockIcon)
            } footer: {
                Text("Without a Dock icon, NumWorks keeps running in the "
                     + "background and stays reachable through its keyboard "
                     + "shortcuts. The Dock icon stays visible while Settings "
                     + "is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Enable menu bar icon", isOn: $preferences.showMenuBarIcon)
                Picker("Menu bar icon style", selection: $preferences.menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!preferences.showMenuBarIcon)
            }

            Section {
                Toggle("Check for updates automatically", isOn: automaticUpdates)
                Button("Check for Updates…", action: actions.checkForUpdates)
                    .disabled(!UpdateController.shared.canCheckForUpdates)
                if !isInApplicationsFolder {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Button("Move to Applications Folder") {
                            AppMover.moveIfNecessary(prompt: false)
                        }
                        .controlSize(.small)
                    }
                }
            } footer: {
                if isInApplicationsFolder {
                    Text("Automatic checks run a few seconds after launch (at most once a day). Updates install only while NumWorks lives in the Applications folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label {
                        Text("NumWorks can check for updates here, but installation requires the Applications folder. "
                             + "If an update is found, you’ll be asked to move the app first.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityLabel(
                        "Warning: Updates can be checked, but installation requires the Applications folder.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Window (merged with Toolbar)

struct WindowToolbarSettingsView: View {
    @ObservedObject var preferences: Preferences

    private var isToolbarStyle: Bool {
        preferences.windowStyle == .toolbar
    }

    var body: some View {
        Form {
            Section {
                Toggle("Always on top", isOn: $preferences.alwaysOnTop)
                Toggle("Move calculator to current desktop when shown",
                       isOn: $preferences.moveWindowToCurrentSpaceWhenShown)
            }
            Section {
                Picker("Toolbar style", selection: $preferences.windowStyle) {
                    Text("Native").tag(WindowStyle.native)
                    Text("Toolbar").tag(WindowStyle.toolbar)
                }
                .pickerStyle(.radioGroup)
            }
            if isToolbarStyle {
                Section {
                    Toggle("Show pin button", isOn: $preferences.showPinButton)
                    Toggle("Show settings button", isOn: $preferences.showSettingsButton)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

struct ShortcutSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Enable shortcuts", isOn: $preferences.shortcutsEnabled)
            }
            Section {
#if canImport(KeyboardShortcuts)
                KeyboardShortcuts.Recorder(
                    "Show or hide calculator", name: .toggleCalculator)
                    .disabled(!preferences.shortcutsEnabled)
                KeyboardShortcuts.Recorder(
                    "Toggle always on top", name: .toggleAlwaysOnTop)
                    .disabled(!preferences.shortcutsEnabled)
#else
                LabeledContent("Shortcuts") {
                    Text("Requires the KeyboardShortcuts package")
                        .foregroundStyle(.secondary)
                }
#endif
            } footer: {
                Text("The shortcuts work from any application. Showing the "
                     + "calculator from another desktop brings it to that desktop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    let actions: SettingsActions

    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                Button("Restore Default Settings…") {
                    isConfirmingReset = true
                }
            } footer: {
                Text("The calculator window keeps its current position and size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Custom Epsilon Framework") {
                    Text("Coming in a future release.")
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
        .alert("Restore all settings to their default values?",
               isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Restore Defaults", action: actions.restoreDefaultSettings)
        } message: {
            Text("Every preference and both keyboard shortcuts will return "
                 + "to their defaults. The calculator window keeps its "
                 + "current position and size.")
        }
    }
}
