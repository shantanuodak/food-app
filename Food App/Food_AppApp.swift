//
//  Food_AppApp.swift
//  Food App
//
//  Created by Shantanu Odak on 2/15/26.
//

import SwiftUI
import TipKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct Food_AppApp: App {
    @StateObject private var appStore = AppStore()

    init() {
        // Configure TipKit once at app launch. Default datastore lives in
        // ~/Library/Application Support; persists dismissal state across
        // launches without us managing UserDefaults keys.
        do {
            try Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        } catch {
            NSLog("[Tutorial] Tips.configure failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStore)
                .preferredColorScheme(.light)
                .onOpenURL { url in
#if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
#endif
                }
                .task {
                    appStore.warmBackend()
                    // Refresh the cached notification auth state from the OS
                    // (the user may have toggled it inside iOS Settings while
                    // the app was backgrounded), then idempotently
                    // re-schedule any challenge-driven nudges.
                    await appStore.refreshNotificationAuthState()
                    await appStore.reconcileNotifications()
                    // Retry any photo uploads that were stashed to disk by
                    // a previous session's "decoupled image upload" save
                    // path but never finished (e.g. user force-quit between
                    // save success and the background upload firing). The
                    // food_log rows are already on the server; we just need
                    // to attach the photos.
                    //
                    // No-op when there's no auth or no pending entries.
                    // Internally bails on the first storage failure so we
                    // don't burn battery if the bucket is permanently
                    // unhappy — the rest re-enqueue for the next launch.
                    await appStore.drainDeferredImageUploads()
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
        }
    }
}
