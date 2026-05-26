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
        appContent
            .onAppear {
                flow.sync(isOnboardingComplete: appStore.isOnboardingComplete)
            }
            .onChange(of: appStore.isOnboardingComplete) { _, isComplete in
                flow.sync(isOnboardingComplete: isComplete)
            }
    }

    @ViewBuilder
    private var appContent: some View {
        Group {
            if !appStore.isSessionRestored {
                LaunchSessionRestoringView()
            } else {
                switch flow.route {
                case .onboarding:
                    OnboardingView(flow: flow)
                case .home:
                    HomeTabShellView()
                }
            }
        }
    }
}

private struct LaunchSessionRestoringView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ProgressView()
                .controlSize(.large)
        }
    }
}

private struct HomeTabShellView: View {
    var body: some View {
        MainLoggingShellView()
    }
}

extension Notification.Name {
    static var openCameraFromTabBar: Notification.Name { Notification.Name("openCameraFromTabBar") }
    static var openQuickCameraFromSystem: Notification.Name { Notification.Name("openQuickCameraFromSystem") }
    static var quickCameraStatusChanged: Notification.Name { Notification.Name("quickCameraStatusChanged") }
    static var openVoiceFromTabBar: Notification.Name { Notification.Name("openVoiceFromTabBar") }
    static var openNutritionSummaryFromTabBar: Notification.Name { Notification.Name("openNutritionSummaryFromTabBar") }
    static var voiceRecordingStateChanged: Notification.Name { Notification.Name("voiceRecordingStateChanged") }
    static var dismissKeyboardFromTabBar: Notification.Name { Notification.Name("dismissKeyboardFromTabBar") }
    static var focusComposerInputFromBackgroundTap: Notification.Name { Notification.Name("focusComposerInputFromBackgroundTap") }
    static var replayHomeTutorialFromAdmin: Notification.Name { Notification.Name("replayHomeTutorialFromAdmin") }
}

#Preview {
    ContentView()
        .environmentObject(AppStore())
}
