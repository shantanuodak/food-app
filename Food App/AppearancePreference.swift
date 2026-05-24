//
//  AppearancePreference.swift
//  Food App
//
//  User-selectable appearance mode. Backed by UserDefaults so it
//  survives launches and is readable from anywhere (including the
//  app entry point that applies preferredColorScheme).
//

import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearancePreference"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
