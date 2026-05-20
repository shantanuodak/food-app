import SwiftUI

// MARK: - BarcodeDetectionPill (Phase 2)

/// Floating pill that appears when the live viewfinder is seeing a barcode.
/// Tells the user the system has found something scannable so they know
/// the upcoming tap will go through the fast barcode lane.
struct BarcodeDetectionPill: View {
    /// nil = no detection in view; non-nil = currently seeing this barcode.
    let detection: DetectedBarcode?

    var body: some View {
        Group {
            if let detection {
                HStack(spacing: 8) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.77, blue: 0.28))
                    Text("Barcode detected — tap to capture")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.96))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.66))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                        )
                )
                .shadow(color: Color.black.opacity(0.45), radius: 8, y: 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Barcode detected. Tap shutter to capture.")
                .accessibilityValue(detection.symbology)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: detection)
    }
}

// MARK: - CameraModeIconRow (Phase 3)

/// Tiny purely-informational row of icons that communicates "we handle three
/// kinds of input automatically." No tap targets. Sits below the top bar.
struct CameraModeIconRow: View {
    var body: some View {
        HStack(spacing: 18) {
            modeChip(systemImage: "barcode.viewfinder", label: "Barcode")
            modeChip(systemImage: "doc.text.viewfinder", label: "Label")
            modeChip(systemImage: "fork.knife", label: "Food")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.38))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera auto-detects barcode, nutrition label, or food.")
    }

    private func modeChip(systemImage: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
        }
    }
}

// MARK: - CameraFirstLaunchTip (Phase 3)

/// One-time tip shown the first time the user opens the custom camera.
/// Backed by UserDefaults so it doesn't re-appear after dismissal.
///
/// Stored under `Self.userDefaultsKey`. Bump the key if you ever want to
/// re-show the tip to existing users (e.g., after a major camera rework).
struct CameraFirstLaunchTip: View {
    static let userDefaultsKey = "foodapp.camera.firstLaunchTipShown.v1"

    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 16) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Color(red: 1.0, green: 0.77, blue: 0.28))

                Text("Quick tip")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                VStack(alignment: .leading, spacing: 10) {
                    tipRow(systemImage: "barcode.viewfinder",
                           text: "Point at a barcode — we'll look it up instantly.")
                    tipRow(systemImage: "doc.text.viewfinder",
                           text: "Point at a Nutrition Facts panel — we'll read it directly.")
                    tipRow(systemImage: "fork.knife",
                           text: "Or just snap your meal — we'll figure it out.")
                }

                Button(action: dismiss) {
                    Text("Got it")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(white: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                    )
            )
            .shadow(color: Color.black.opacity(0.55), radius: 30, y: 14)
        }
        .transition(.opacity)
    }

    private func tipRow(systemImage: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.77, blue: 0.28))
                .frame(width: 26)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dismiss() {
        UserDefaults.standard.set(true, forKey: Self.userDefaultsKey)
        withAnimation(.easeOut(duration: 0.18)) {
            isPresented = false
        }
    }
}

extension CameraFirstLaunchTip {
    /// Returns true if the tip should be shown on this open. Reads
    /// UserDefaults — no observation required since the value flips only
    /// once.
    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: userDefaultsKey)
    }
}

#if DEBUG
#Preview("Barcode detected pill") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 24) {
            BarcodeDetectionPill(detection: nil)
            BarcodeDetectionPill(detection: DetectedBarcode(payload: "0049000028911", symbology: "UPC-A"))
            BarcodeDetectionPill(detection: DetectedBarcode(payload: "0028400433556", symbology: "EAN-13"))
        }
    }
}

#Preview("Mode icon row") {
    ZStack {
        Color.black.ignoresSafeArea()
        CameraModeIconRow()
    }
}

#Preview("First-launch tip") {
    @Previewable @State var showTip = true
    return ZStack {
        Color.gray.opacity(0.4).ignoresSafeArea()
        if showTip {
            CameraFirstLaunchTip(isPresented: $showTip)
        }
    }
}
#endif
