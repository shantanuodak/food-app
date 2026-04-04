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

    private var preferredColorScheme: ColorScheme? {
        switch appStore.appearancePreference {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStore)
                .preferredColorScheme(preferredColorScheme)
                .onOpenURL { url in
#if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
#endif
                }
        }
    }
}
