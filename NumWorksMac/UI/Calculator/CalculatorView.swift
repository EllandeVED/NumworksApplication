import SwiftUI
import WebKit
import AppKit

struct CalculatorView: View {
    let wm: WindowManagement
    @ObservedObject private var prefs = Preferences.shared
    //not modify these
    @State private var hoveringPin = false
    @State private var didLockOverlay = false
    @State private var extraRatioX: CGFloat = 0
    @State private var extraRatioY: CGFloat = 0
    @State private var offsetRatioX: CGFloat = 0
    @State private var offsetRatioY: CGFloat = 0

    // Overlay calibration (adjust these values manually)
    // overlayExtra = global growth in all directions
    // overlayExtraX / overlayExtraY = fine tuning per axis
    // overlayOffsetX / overlayOffsetY = positional adjustments
    //modifiable these
    private let overlayExtra: CGFloat = 40
    private let overlayExtraX: CGFloat = 0
    private let overlayExtraY: CGFloat = 11

    private let overlayOffsetX: CGFloat = 0
    private let overlayOffsetY: CGFloat = 45

    private func lockOverlayIfNeeded(for size: CGSize) {
        guard !didLockOverlay else { return }
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return }

        // Convert the user-provided calibration values into ratios relative to the current window size.
        // After this point, resizing stays proportional.
        extraRatioX = (overlayExtra + overlayExtraX) / w
        extraRatioY = (overlayExtra + overlayExtraY) / h
        offsetRatioX = overlayOffsetX / w
        offsetRatioY = overlayOffsetY / h

        didLockOverlay = true
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                if !prefs.calculatorImageHidden {
                    Image("CalculatorImage")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                if OnLaunch.hasInstalledSimulator() {
                    CalculatorWebView(
                        onReady: {
                            wm.attachWebView($0)
                            print("[Calculator] onReady → posting calculatorDidLoad")
                            NotificationCenter.default.post(name: .calculatorDidLoad, object: nil)
                        },
                        onBaseSize: { wm.setBaseSize($0) }
                    )
                    .frame(
                        width: {
                            let w = geo.size.width
                            if w <= 0 { return w }

                            let ex = w * (didLockOverlay ? extraRatioX : ((overlayExtra + overlayExtraX) / w))
                            return w + ex * 2
                        }(),
                        height: {
                            let h = geo.size.height
                            if h <= 0 { return h }

                            let ey = h * (didLockOverlay ? extraRatioY : ((overlayExtra + overlayExtraY) / h))
                            return h + ey * 2
                        }()
                    )
                    .offset(
                        x: {
                            let w = geo.size.width
                            if w <= 0 { return 0 }

                            let ex = w * (didLockOverlay ? extraRatioX : ((overlayExtra + overlayExtraX) / w))
                            let ox = w * (didLockOverlay ? offsetRatioX : (overlayOffsetX / w))
                            return ox - ex
                        }(),
                        y: {
                            let h = geo.size.height
                            if h <= 0 { return 0 }

                            let ey = h * (didLockOverlay ? extraRatioY : ((overlayExtra + overlayExtraY) / h))
                            let oy = h * (didLockOverlay ? offsetRatioY : (overlayOffsetY / h))
                            return oy - ey
                        }()
                    )
                    .onAppear {
                        lockOverlayIfNeeded(for: geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        lockOverlayIfNeeded(for: newSize)
                    }
                } else {
                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.height)
                }
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
