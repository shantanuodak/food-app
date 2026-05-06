import SwiftUI
import UIKit

/// Purple-pink gradient used for AI-related shimmer and loading effects.
let aiShimmerGradient = LinearGradient(
    colors: [
        Color(red: 0.58, green: 0.29, blue: 0.98),  // purple
        Color(red: 0.91, green: 0.30, blue: 0.60),  // pink
        Color(red: 0.58, green: 0.29, blue: 0.98)   // purple (bookend)
    ],
    startPoint: .leading,
    endPoint: .trailing
)


struct InsertShimmerModifier: ViewModifier {
    let isActive: Bool
    let onComplete: () -> Void
    @State private var shimmerOffset: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let sweepWidth = w * 0.55

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.85), location: 0.45),
                                .init(color: .white.opacity(0.95), location: 0.5),
                                .init(color: .white.opacity(0.85), location: 0.55),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: sweepWidth)
                        .offset(x: shimmerOffset * (w + sweepWidth) - sweepWidth)
                        .blendMode(.sourceAtop)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        shimmerOffset = -0.6
                        withAnimation(.easeInOut(duration: 0.7)) {
                            shimmerOffset = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                            onComplete()
                        }
                    }
                }
            }
            .compositingGroup()
    }
}

/// Fast one-shot shimmer used when the calorie pill updates via the
/// client-side quantity fast path. Distinct from `InsertShimmerModifier`:
/// - shorter (~450ms total vs ~750ms) so it doesn't drag on rapid edits
/// - uses the purple→pink AI gradient so it reads as "we recalculated"
///   rather than a plain reveal
/// - wider gradient taper so small pill widths still feel like a sweep
struct CalorieUpdateShimmerModifier: ViewModifier {
    let isActive: Bool
    let onComplete: () -> Void
    @State private var sweepPhase: CGFloat = -0.8

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let sweepWidth = w * 0.7

                        aiShimmerGradient
                            .frame(width: sweepWidth)
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white.opacity(0.7), location: 0.4),
                                        .init(color: .white, location: 0.5),
                                        .init(color: .white.opacity(0.7), location: 0.6),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: sweepPhase * (w + sweepWidth) - sweepWidth)
                            .blendMode(.plusLighter)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .onAppear {
                        sweepPhase = -0.8
                        withAnimation(.easeOut(duration: 0.45)) {
                            sweepPhase = 1.1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onComplete()
                        }
                    }
                }
            }
            .compositingGroup()
    }
}

struct UnresolvedRowStatusView: View {
    var body: some View {
        Text("Edit & Retry")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.orange.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct FailedRowStatusView: View {
    var body: some View {
        Text(L10n.parseRetryShortLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.red.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct QueuedRowStatusView: View {
    var body: some View {
        Text(L10n.parseQueuedShortLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.secondary.opacity(0.95))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct RowThoughtProcessStatusView: View {
    let routeHint: LoadingRouteHint
    let startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15)) { context in
            let start = startedAt ?? context.date
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let text = phaseText(elapsed: elapsed)
            let shimmer = shimmerProgress(elapsed: elapsed)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(aiShimmerGradient)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        let sweepWidth = width * 0.72
                        let xOffset = (width + sweepWidth) * shimmer - sweepWidth

                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: sweepWidth, height: 16)
                        .offset(x: xOffset)
                    }
                    .mask(
                        Text(text)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    )
                    .allowsHitTesting(false)
                }
        }
    }

    private func phaseText(elapsed: TimeInterval) -> String {
        let phrases: [String]
        switch routeHint {
        case .foodDatabase:
            phrases = [
                "Looking up food",
                "Finding best match",
                "Checking serving size",
                "Estimating calories"
            ]
        case .ai:
            phrases = [
                "Reading your note",
                "Cross-checking 3 sources",
                "Resolving serving assumptions",
                "Estimating calories"
            ]
        case .unknown:
            phrases = [
                "Analyzing entry",
                "Searching matches",
                "Estimating calories"
            ]
        }

        let phaseDuration = 1.05
        let index = Int(elapsed / phaseDuration) % phrases.count
        return phrases[index]
    }

    private func shimmerProgress(elapsed: TimeInterval) -> CGFloat {
        let cycle = 1.25
        let value = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
        return CGFloat(value)
    }
}

// MARK: - Backspace-Detecting UITextField

class BackspaceDetectingTextField: UITextField {
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        if text?.isEmpty == true || text == nil {
            onDeleteBackward?()
        }
        super.deleteBackward()
    }

    // iOS 26 applies a yellow "Writing Tools" highlight to text fields.
    // Disable it by opting out of the text interaction styling.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Remove any system-added highlight/interaction overlays
        let interactionsToRemove = interactions.filter {
            let typeName = String(describing: type(of: $0))
            return typeName.contains("Highlight") || typeName.contains("LookUp")
        }
        for interaction in interactionsToRemove {
            removeInteraction(interaction)
        }
        // Disable the Writing Tools highlight on iOS 18.2+ / iOS 26
        if #available(iOS 18.2, *) {
            self.writingToolsBehavior = .none
        }
    }
}

struct BackspaceAwareTextFieldRepresentable: UIViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let onDeleteBackwardWhenEmpty: () -> Void
    var placeholder: String = ""

    func makeUIView(context: Context) -> BackspaceDetectingTextView {
        let tv = BackspaceDetectingTextView()
        tv.font = UIFont.systemFont(ofSize: 18)
        tv.backgroundColor = .clear
        tv.tintColor = .label
        tv.textColor = .label
        tv.delegate = context.coordinator
        tv.returnKeyType = .next
        tv.autocorrectionType = .no
        tv.spellCheckingType = .no
        tv.autocapitalizationType = .none
        if #available(iOS 17.0, *) {
            tv.inlinePredictionType = .no
        }
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        // Multi-line wrapping config
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)

        tv.onDeleteBackward = { [weak tv] in
            guard tv?.text.isEmpty == true else { return }
            onDeleteBackwardWhenEmpty()
        }

        // Placeholder label
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = UIFont.systemFont(ofSize: 18)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.tag = 999
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: tv.topAnchor)
        ])
        placeholderLabel.isHidden = !text.isEmpty

        return tv
    }

    func updateUIView(_ uiView: BackspaceDetectingTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        // Update placeholder visibility
        if let placeholderLabel = uiView.viewWithTag(999) as? UILabel {
            placeholderLabel.isHidden = !text.isEmpty
        }
        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused && uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
        uiView.onDeleteBackward = { [weak uiView] in
            guard uiView?.text.isEmpty == true else { return }
            onDeleteBackwardWhenEmpty()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: BackspaceAwareTextFieldRepresentable

        init(_ parent: BackspaceAwareTextFieldRepresentable) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
            // Update placeholder
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !newText.isEmpty
            }
            // Notify SwiftUI to resize the view
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return key → submit (add new row), don't insert newline
            if text == "\n" {
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChanged(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChanged(false)
        }
    }
}

/// UITextView subclass that detects backspace on empty text and
/// reports its intrinsic height so SwiftUI wraps it to multiple lines.
class BackspaceDetectingTextView: UITextView {
    var onDeleteBackward: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        // Use current bounds width (or a fallback) to compute the height
        // needed for the text to wrap properly.
        let width = bounds.width > 0 ? bounds.width : 200
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(size.height, 26))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // When bounds change (rotation, layout pass), recalculate height
        // so SwiftUI gives us enough vertical space.
        let before = intrinsicContentSize.height
        invalidateIntrinsicContentSize()
        if intrinsicContentSize.height != before {
            superview?.setNeedsLayout()
        }
    }

    override func deleteBackward() {
        let wasEmpty = text.isEmpty
        super.deleteBackward()
        if wasEmpty {
            onDeleteBackward?()
        }
    }
}

struct MinimalRowTextEditor: View {
    @Binding var text: String
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onSubmit: () -> Void
    let onDeleteBackwardWhenEmpty: () -> Void
    var placeholder: String = ""
    var showTypewriterPlaceholder: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            BackspaceAwareTextFieldRepresentable(
                text: $text,
                isFocused: isFocused,
                onFocusChanged: onFocusChanged,
                onSubmit: onSubmit,
                onDeleteBackwardWhenEmpty: onDeleteBackwardWhenEmpty,
                placeholder: showTypewriterPlaceholder ? "" : placeholder
            )
            .frame(minHeight: 26)

            if text.isEmpty && showTypewriterPlaceholder {
                TypewriterPlaceholder(text: placeholder)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct TypewriterPlaceholder: View {
    let text: String

    private let examples = [
        "Type your food here",
        "2 eggs and toast",
        "Greek yogurt with berries",
        "Chicken salad bowl",
        "Black coffee",
        "1 banana",
        "Oatmeal with honey"
    ]

    @State private var displayedText = ""
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Text(displayedText)
            .font(.system(size: 18))
            .foregroundStyle(Color(.placeholderText))
            .onAppear { startLoop() }
            .onDisappear { animationTask?.cancel() }
    }

    private func startLoop() {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)

            while !Task.isCancelled {
                for example in examples {
                    guard !Task.isCancelled else { return }

                    // Type in
                    for i in 1...example.count {
                        guard !Task.isCancelled else { return }
                        displayedText = String(example.prefix(i))
                        try? await Task.sleep(nanoseconds: 55_000_000)
                    }

                    // Pause to read
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    guard !Task.isCancelled else { return }

                    // Delete out
                    for i in stride(from: example.count, through: 0, by: -1) {
                        guard !Task.isCancelled else { return }
                        displayedText = String(example.prefix(i))
                        try? await Task.sleep(nanoseconds: 35_000_000)
                    }

                    // Brief pause before next
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }
}
