import SwiftUI

struct OB01WelcomeScreen: View {
    let onGetStarted: () -> Void
    let onExistingAccount: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var photosAppeared = false

    private let greenCTA = Color(red: 0.126, green: 0.494, blue: 0.216)

    private var titleColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.96)
            : Color.black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.9)
            : Color.black
    }

    var body: some View {
        ZStack {
            OnboardingAnimatedBackground()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: 72)

                titleBlock
                    .padding(.horizontal, 30)

                animationPanel
                    .padding(.top, 72)
                    .padding(.horizontal, 16)

                foodPhotoCollage
                    .padding(.top, 44)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)

                Spacer(minLength: 24)

                VStack(spacing: 24) {
                    Button(action: onGetStarted) {
                        Text("Get Started")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .background(greenCTA, in: RoundedRectangle(cornerRadius: 52, style: .continuous))
                            .shadow(color: Color(red: 0.184, green: 0.357, blue: 0.118).opacity(0.63), radius: 11.4, x: 1, y: -1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(L10n.onboardingSplashStartHint))

                    Button(action: onExistingAccount) {
                        Text(L10n.onboardingSplashExistingAccountButton)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 26)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear.ignoresSafeArea())
        .onAppear {
            appeared = true
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.4)) {
                photosAppeared = true
            }
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Log your food with")
                .font(OnboardingTypography.onboardingHeadline(size: 44))
                .foregroundStyle(titleColor)

            Text("less \(Text("Effort").font(OnboardingTypography.instrumentSerif(style: .italic, size: 44)))")
                .font(OnboardingTypography.onboardingHeadline(size: 44))
                .foregroundStyle(titleColor)
        }
        .multilineTextAlignment(.leading)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Typing Demo

    private var animationPanel: some View {
        OnboardingTypingDemoView()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
    }

    // MARK: - Food Photo Collage

    @State private var shimmerPhase: CGFloat = -1

    private var foodPhotoCollage: some View {
        ZStack {
            // Left photo
            shimmerPhotoCard(
                image: "IntroFood1",
                width: 148, height: 191,
                rotation: 0,
                offsetX: -55, offsetY: 10
            )

            // Right photo
            shimmerPhotoCard(
                image: "IntroFood2",
                width: 157, height: 189,
                rotation: 19.5,
                offsetX: 40, offsetY: -5
            )
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.5)
                .repeatForever(autoreverses: false)
            ) {
                shimmerPhase = 1
            }
        }
    }

    private func shimmerPhotoCard(image: String, width: CGFloat, height: CGFloat, rotation: Double, offsetX: CGFloat, offsetY: CGFloat) -> some View {
        Image(image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Shimmer on the image surface
            .overlay(
                shimmerGradient(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            // White border with shimmer highlight
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white, lineWidth: 6.4)
            )
            .overlay(
                shimmerBorderHighlight(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .shadow(color: Color.black.opacity(0.55), radius: 6, y: 3.2)
            .rotationEffect(.degrees(rotation))
            .offset(x: offsetX, y: offsetY)
            .scaleEffect(photosAppeared ? 1 : 0.8)
            .opacity(photosAppeared ? 1 : 0)
    }

    private func shimmerGradient(width: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let sweepWidth = w * 0.7

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.25), location: 0.4),
                    .init(color: .white.opacity(0.35), location: 0.5),
                    .init(color: .white.opacity(0.25), location: 0.6),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: sweepWidth)
            .offset(x: shimmerPhase * (w + sweepWidth) - sweepWidth)
            .allowsHitTesting(false)
        }
    }

    private func shimmerBorderHighlight(width: CGFloat) -> some View {
        GeometryReader { geo in
            let sweepWidth = geo.size.width * 0.55

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 2)
                .frame(width: sweepWidth)
                .offset(x: shimmerPhase * (geo.size.width + sweepWidth) - sweepWidth)
                .allowsHitTesting(false)
        }
    }
}
