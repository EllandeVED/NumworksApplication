import SwiftUI
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

/// Window/shortcut actions invoked from Settings, provided by AppController.
struct SettingsActions {
    let centreWindow: () -> Void
    let resetWindowSize: () -> Void
    let resetWindowPosition: () -> Void
    let resetShortcut: () -> Void
    let resetAllSettings: () -> Void
}

struct SettingsRootView: View {
    @ObservedObject var preferences: Preferences
    let actions: SettingsActions

    var body: some View {
        TabView {
            GeneralSettingsView(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            WindowSettingsView(preferences: preferences, actions: actions)
                .tabItem { Label("Window", systemImage: "macwindow") }
            ShortcutSettingsView(preferences: preferences, actions: actions)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AdvancedSettingsView(actions: actions)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 440)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Show calculator when NumWorks launches",
                       isOn: $preferences.launchWindowVisible)
            }
            Section("Top Bar") {
                Toggle("Show top bar", isOn: $preferences.showTopBar)
                Toggle("Show pin button", isOn: $preferences.showPinButton)
                    .disabled(!preferences.showTopBar)
                Toggle("Show settings button", isOn: $preferences.showSettingsButton)
                    .disabled(!preferences.showTopBar)
            }
            Section {
                Picker("Window appearance", selection: $preferences.windowStyle) {
                    ForEach(WindowStyle.allCases) { style in
                        if style.isAvailable {
                            Text(style.displayName).tag(style)
                        } else {
                            Text("\(style.displayName) (coming later)").tag(style)
                        }
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Minimal mode is not available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Window

struct WindowSettingsView: View {
    @ObservedObject var preferences: Preferences
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                Toggle("Always on top", isOn: $preferences.alwaysOnTop)
                Toggle("Move calculator to current desktop when shown",
                       isOn: $preferences.moveWindowToCurrentSpaceWhenShown)
            }
            Section {
                Toggle("Remember window position",
                       isOn: $preferences.rememberWindowPosition)
                Toggle("Remember window size",
                       isOn: $preferences.rememberWindowSize)
            }
            Section {
                LabeledContent("Position and size") {
                    HStack {
                        Button("Centre Window", action: actions.centreWindow)
                        Button("Reset Size", action: actions.resetWindowSize)
                        Button("Reset Position", action: actions.resetWindowPosition)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

struct ShortcutSettingsView: View {
    @ObservedObject var preferences: Preferences
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                Toggle("Enable show/hide shortcut",
                       isOn: $preferences.hideShowShortcutEnabled)
#if canImport(KeyboardShortcuts)
                KeyboardShortcuts.Recorder(
                    "Show or hide calculator", name: .toggleCalculator)
                    .disabled(!preferences.hideShowShortcutEnabled)
                Button("Reset to Default Shortcut", action: actions.resetShortcut)
                    .disabled(!preferences.hideShowShortcutEnabled)
#else
                LabeledContent("Show or hide calculator") {
                    Text("Requires the KeyboardShortcuts package")
                        .foregroundStyle(.secondary)
                }
#endif
            } footer: {
                Text("The shortcut works from any application. Invoking it "
                     + "from another desktop brings the calculator to that desktop.")
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
                LabeledContent("NumWorks app", value: AppInfo.appVersion)
                LabeledContent("Epsilon", value: AppInfo.epsilonVersion)
            } footer: {
                Text("The Epsilon simulator is compiled into NumWorks and "
                     + "runs inside this same app process. No separate "
                     + "simulator app is launched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Reset All Settings…", role: .destructive) {
                    isConfirmingReset = true
                }
                Button("Open Diagnostics") {}
                    .disabled(true)
                    .help("Diagnostics will be available in a later version")
            }
        }
        .formStyle(.grouped)
        .alert("Reset all settings?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive, action: actions.resetAllSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All NumWorks preferences, including the keyboard shortcut "
                 + "and the saved window frame, will return to their defaults.")
        }
    }
}
