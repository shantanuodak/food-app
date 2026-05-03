//
//  ContentView.swift
//  Food App
//
//  Created by Shantanu Odak on 2/15/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appStore: AppStore
    @StateObject private var flow = AppFlowCoordinator()

    var body: some View {
        Group {
            switch flow.route {
            case .onboarding:
                OnboardingView(flow: flow)
            case .home:
                HomeTabShellView()
            }
        }
        .onAppear {
            flow.sync(isOnboardingComplete: appStore.isOnboardingComplete)
        }
        .onChange(of: appStore.isOnboardingComplete) { _, isComplete in
            flow.sync(isOnboardingComplete: isComplete)
        }
    }
}

private struct HomeTabShellView: View {
    var body: some View {
        MainLoggingShellView()
    }
}

extension Notification.Name {
    static let openCameraFromTabBar = Notification.Name("openCameraFromTabBar")
    static let openVoiceFromTabBar = Notification.Name("openVoiceFromTabBar")
    static let openNutritionSummaryFromTabBar = Notification.Name("openNutritionSummaryFromTabBar")
    static let voiceRecordingStateChanged = Notification.Name("voiceRecordingStateChanged")
    static let dismissKeyboardFromTabBar = Notification.Name("dismissKeyboardFromTabBar")
    static let focusComposerInputFromBackgroundTap = Notification.Name("focusComposerInputFromBackgroundTap")
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
}
