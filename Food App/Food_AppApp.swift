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
    @StateObject private var appStore = AppStore()

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
                    // Refresh the cached notification auth state from the OS
                    // (the user may have toggled it inside iOS Settings while
                    // the app was backgrounded), then idempotently
                    // re-schedule any challenge-driven nudges.
                    await appStore.refreshNotificationAuthState()
                    await appStore.reconcileNotifications()
                }
        }
    }
}
