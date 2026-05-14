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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appStore = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStore)
                .onOpenURL { url in
                    if QuickCameraLaunchStore.handle(url: url) {
                        return
                    }
#if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
#endif
                }
                .task {
                    FoodBackgroundRefreshService.shared.appStore = appStore
                    Task(priority: .background) { @MainActor in
                        // Let the first screen render before doing launch
                        // maintenance. On real devices these OS calls can
                        // contend with SwiftUI's first paint and look like a
                        // frozen app, especially after a fresh install.
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        guard !Task.isCancelled else { return }
                        FoodBackgroundRefreshService.shared.scheduleAppRefresh()
                        appStore.warmBackend()
                        await appStore.refreshNotificationAuthState()
                        await appStore.reconcileNotifications()
                        await appStore.drainDeferredImageUploads()
                    }
                }
                // Cold-start case: when auth restoration hasn't finished by
                // the time `.task` above runs, the drain inside it is a
                // no-op (`session` is still nil). Run again the moment the
                // session becomes available so the user doesn't have to
                // wait until next launch for stuck photos to attach.
                .onChange(of: appStore.isSessionRestored) { _, restored in
                    guard restored else { return }
                    Task { await appStore.drainDeferredImageUploads() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        FoodBackgroundRefreshService.shared.scheduleAppRefresh()
                    }
                }
        }
    }
}
