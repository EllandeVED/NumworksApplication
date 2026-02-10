import SwiftUI
import WebKit
import AppKit

struct CalculatorView: View {
    let wm: WindowManagement
    @StateObject private var prefs = Preferences.shared
    @State private var hoveringPin = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image("CalculatorImage")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if OnLaunch.hasInstalledSimulator() {
                CalculatorWebView(
                    onReady: {
                        wm.attachWebView($0)
                        print("[Calculator] onReady → posting calculatorDidLoad")
                        NotificationCenter.default.post(name: .calculatorDidLoad, object: nil)
                    },
                    onBaseSize: { wm.setBaseSize($0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if prefs.showPinButtonOnCalculator {
                Button {
                    AppController.shared.togglePinned()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                            )

                        PinStickIcon(active: prefs.isPinned)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .onHover { hovering in
                    if hovering && !hoveringPin {
                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    }
                    hoveringPin = hovering
                }
                .accessibilityLabel(prefs.isPinned ? "Unpin" : "Pin")
                .offset(x: -10, y: 10)
            }
            SimulatorUpdateView()
        }
    }
}

#Preview {
    CalculatorView(wm: WindowManagement())
}

//An animated pin that “sticks” into a surface when active (tilt + down motion + shadow)
private struct PinStickIcon: View {
    var active: Bool
    @State private var trigger = false

    private struct PinAnimState: VectorArithmetic {
        var rotation: CGFloat
        var yOffset: CGFloat
        var shadow: CGFloat
        static var zero: PinAnimState { .init(rotation: 0, yOffset: 0, shadow: 0) }
        static func - (lhs: PinAnimState, rhs: PinAnimState) -> PinAnimState {
            .init(rotation: lhs.rotation - rhs.rotation, yOffset: lhs.yOffset - rhs.yOffset, shadow: lhs.shadow - rhs.shadow)
        }
        static func + (lhs: PinAnimState, rhs: PinAnimState) -> PinAnimState {
            .init(rotation: lhs.rotation + rhs.rotation, yOffset: lhs.yOffset + rhs.yOffset, shadow: lhs.shadow + rhs.shadow)
        }
        mutating func scale(by rhs: Double) {
            rotation *= rhs
            yOffset *= rhs
            shadow *= rhs
        }
        var magnitudeSquared: Double { Double(rotation * rotation + yOffset * yOffset + shadow * shadow) }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.secondary.opacity(0.10))
                .frame(width: 20, height: 10)
                .scaleEffect(x: 1, y: active ? 0.88 : 1, anchor: .center)
                .animation(.spring(response: 0.22, dampingFraction: 0.88), value: active)
                .opacity(0.9)

            Image(systemName: active ? "pin.fill" : "pin")
                .imageScale(.medium)
                .keyframeAnimator(
                    initialValue: PinAnimState(
                        rotation: active ? 12 : 0,
                        yOffset: 0,
                        shadow: 1
                    ),
                    trigger: trigger
                ) { content, value in
                    content
                        .rotationEffect(.degrees(value.rotation))
                        .offset(y: value.yOffset)
                        .shadow(radius: value.shadow)
                } keyframes: { _ in
                    KeyframeTrack(\.rotation) {
                        if active {
                            CubicKeyframe(18, duration: 0.08)
                            CubicKeyframe(6, duration: 0.10)
                            CubicKeyframe(10, duration: 0.10)
                            CubicKeyframe(12, duration: 0.12)
                        } else {
                            CubicKeyframe(6, duration: 0.10)
                            CubicKeyframe(2, duration: 0.10)
                            CubicKeyframe(0, duration: 0.12)
                        }
                    }

                    KeyframeTrack(\.yOffset) {
                        if active {
                            CubicKeyframe(3, duration: 0.08)
                            CubicKeyframe(-2, duration: 0.10)
                            CubicKeyframe(1, duration: 0.10)
                            CubicKeyframe(0, duration: 0.12)
                        } else {
                            CubicKeyframe(-4, duration: 0.10)
                            CubicKeyframe(-2, duration: 0.10)
                            CubicKeyframe(0, duration: 0.12)
                        }
                    }

                    KeyframeTrack(\.shadow) {
                        if active {
                            CubicKeyframe(5, duration: 0.08)
                            CubicKeyframe(3, duration: 0.20)
                            CubicKeyframe(2, duration: 0.12)
                        } else {
                            CubicKeyframe(3, duration: 0.10)
                            CubicKeyframe(2, duration: 0.10)
                            CubicKeyframe(1, duration: 0.12)
                        }
                    }
                }
        }
        .onChange(of: active) { _, _ in trigger.toggle() }
    }
}
