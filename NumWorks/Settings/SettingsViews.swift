import SwiftUI
#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

/// Window/shortcut actions invoked from Settings, provided by AppController.
struct SettingsActions {
    let centreWindow: () -> Void
    let resetWindowSize: () -> Void
    let resetWindowPosition: () -> Void
    let restoreDefaultSettings: () -> Void
}

enum SettingsTab: String {
    case general, toolbar, window, shortcuts, advanced, about
}

struct SettingsRootView: View {
    @ObservedObject var preferences: Preferences
    let actions: SettingsActions

    @State private var selection = SettingsRootView.initialTab()

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ToolbarSettingsView(preferences: preferences)
                .tabItem { Label("Toolbar", systemImage: "menubar.rectangle") }
                .tag(SettingsTab.toolbar)
            WindowSettingsView(preferences: preferences, actions: actions)
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
        // Grouped forms have no intrinsic height inside a TabView, so the
        // window needs a fixed content size; forms scroll if they overflow.
        .frame(width: 460, height: 480)
    }

    /// Debug aid: `NumWorks --show-settings --settings-tab=<name>` opens
    /// Settings on a specific tab for automated UI verification.
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
                     + "shortcuts. macOS hides the menu bar for apps without "
                     + "a Dock icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Toolbar

struct ToolbarSettingsView: View {
    @ObservedObject var preferences: Preferences

    private var toolbarControlsEnabled: Bool {
        preferences.windowStyle == .toolbar
    }

    var body: some View {
        Form {
            Section {
                // Minimal stays hidden until it has a safe implementation.
                Picker("Toolbar style", selection: $preferences.windowStyle) {
                    Text("Standard macOS Window").tag(WindowStyle.native)
                    Text("Native Toolbar").tag(WindowStyle.toolbar)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show top toolbar", isOn: $preferences.showTopBar)
                    .disabled(!toolbarControlsEnabled)
                Toggle("Show pin button", isOn: $preferences.showPinButton)
                    .disabled(!toolbarControlsEnabled || !preferences.showTopBar)
                Toggle("Show settings button", isOn: $preferences.showSettingsButton)
                    .disabled(!toolbarControlsEnabled || !preferences.showTopBar)
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
                        Button("Center Window", action: actions.centreWindow)
                        Button("Reset Position", action: actions.resetWindowPosition)
                        Button("Reset Size", action: actions.resetWindowSize)
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
                LabeledContent("NumWorks", value: AppInfo.bundleVersion)
                LabeledContent("Build", value: AppInfo.bundleBuild)
                LabeledContent("Epsilon", value: AppInfo.epsilonVersion)
                if let buildDate = AppInfo.buildDate {
                    LabeledContent("Build date", value: buildDate)
                }
            } header: {
                Text("Versions")
            } footer: {
                Text("The Epsilon simulator is compiled into NumWorks and "
                     + "runs inside this same app process. No separate "
                     + "simulator app is launched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Default Settings…") {
                    isConfirmingReset = true
                }
            } footer: {
                Text("Window position and size are not affected; they have "
                     + "their own reset buttons in the Window tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
