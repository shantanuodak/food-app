//
//  Food_AppApp.swift
//  Food App
//
//  Created by Shantanu Odak on 2/15/26.
//

import SwiftUI

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct Food_AppApp: App {
    @UIApplicationDelegateAdaptor(FoodAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootBootstrapView()
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    if QuickCameraLaunchStore.handle(url: url) {
                        return
                    }
#if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
#endif
                }
        }
    }
}

private struct RootBootstrapView: View {
    @StateObject private var appStore = AppStore()

    var body: some View {
        RootAppContentView(appStore: appStore)
    }
}

private struct RootAppContentView: View {
    @ObservedObject var appStore: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var postLaunchMaintenanceTask: Task<Void, Never>?

    var body: some View {
        ContentView()
            .environmentObject(appStore)
            .task {
                FoodBackgroundRefreshService.shared.appStore = appStore
                Task(priority: .background) { @MainActor in
                    // Let the first screen render before doing launch
                    // maintenance. The launch path stays UI-first; heavier
                    // network work is scheduled only after auth restoration.
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !Task.isCancelled else { return }
                    FoodBackgroundRefreshService.shared.scheduleAppRefresh()
                    await appStore.refreshNotificationAuthState()
                    schedulePostLaunchMaintenanceIfReady()
                }
            }
            // Cold-start case: when auth restoration hasn't finished by
            // the time `.task` above runs, queue expensive network
            // maintenance once the session is available.
            .onChange(of: appStore.isSessionRestored) { _, restored in
                guard restored else { return }
                schedulePostLaunchMaintenanceIfReady()
            }
            .onChange(of: appStore.isOnboardingComplete) { _, _ in
                schedulePostLaunchMaintenanceIfReady()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    FoodBackgroundRefreshService.shared.scheduleAppRefresh()
                }
            }
    }

    @MainActor
    private func schedulePostLaunchMaintenanceIfReady() {
        guard appStore.isSessionRestored, appStore.isOnboardingComplete else { return }
        guard postLaunchMaintenanceTask == nil else { return }

        postLaunchMaintenanceTask = Task(priority: .background) { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await appStore.reconcileNotifications()
            await appStore.drainDeferredImageUploads()
            postLaunchMaintenanceTask = nil
        }
    }
}
