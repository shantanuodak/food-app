import SwiftUI
import UIKit
import UserNotifications

struct NotificationReminderSettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRequestingPermission = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: remindersEnabledBinding) {
                    Label("Meal reminders", systemImage: "bell.badge")
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(notificationFooterText)
            }

            Section {
                mealReminderRow(
                    title: "Breakfast",
                    systemImage: "sunrise.fill",
                    enabledKeyPath: \.breakfastEnabled,
                    startKeyPath: \.breakfastStart,
                    endKeyPath: \.breakfast
                )
                mealReminderRow(
                    title: "Lunch",
                    systemImage: "sun.max.fill",
                    enabledKeyPath: \.lunchEnabled,
                    startKeyPath: \.lunchStart,
                    endKeyPath: \.lunch
                )
                mealReminderRow(
                    title: "Dinner",
                    systemImage: "moon.fill",
                    enabledKeyPath: \.dinnerEnabled,
                    startKeyPath: \.dinnerStart,
                    endKeyPath: \.dinner
                )
            } header: {
                Text("Meal windows")
            } footer: {
                Text("Food App schedules one reminder at the end of each enabled meal window on this device.")
            }
            .disabled(!appStore.mealReminderSettings.remindersEnabled)

            Section {
                Toggle(isOn: settingsBoolBinding(\.eatingWindowEnabled)) {
                    Label("Eating window", systemImage: "clock.badge")
                }

                if appStore.mealReminderSettings.eatingWindowEnabled {
                    DatePicker(
                        selection: settingsTimeBinding(\.eatingWindowStart),
                        displayedComponents: .hourAndMinute
                    ) {
                        Label("Starts", systemImage: "arrow.right.circle")
                    }
                    DatePicker(
                        selection: settingsTimeBinding(\.eatingWindowEnd),
                        displayedComponents: .hourAndMinute
                    ) {
                        Label("Ends", systemImage: "arrow.left.circle")
                    }
                }
            } header: {
                Text("Eating window")
            } footer: {
                Text("Used as context for engagement nudges without creating extra meal reminders.")
            }
            .disabled(!appStore.mealReminderSettings.remindersEnabled)

            smartNudgesSection
        }
        .navigationTitle("Notifications & Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appStore.refreshNotificationAuthState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await appStore.refreshNotificationAuthState() }
        }
    }

    @ViewBuilder
    private var smartNudgesSection: some View {
        Section {
            Toggle(isOn: healthNudgesEnabledBinding) {
                Label("Smart health nudges", systemImage: "sparkles")
            }
        } header: {
            Text("Smart nudges")
        } footer: {
            Text("Gentle, real-time reminders that only fire when you're falling behind on a goal for the day — never when you're already on track.")
        }

        Section {
            Toggle(isOn: healthNudgeBoolBinding(\.hydrationEnabled)) {
                Label("Hydration", systemImage: "drop.fill")
            }
            Toggle(isOn: healthNudgeBoolBinding(\.proteinEnabled)) {
                Label("Protein", systemImage: "fork.knife")
            }
            Toggle(isOn: healthNudgeBoolBinding(\.movementEnabled)) {
                Label("Movement", systemImage: "figure.walk")
            }

            if appStore.healthNudgeSettings.movementEnabled {
                Stepper(value: stepGoalBinding, in: 2000...20000, step: 1000) {
                    HStack {
                        Label("Daily step goal", systemImage: "shoeprints.fill")
                        Spacer()
                        Text("\(appStore.healthNudgeSettings.stepGoal.formatted())")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("What to nudge me about")
        } footer: {
            Text(smartNudgesFooterText)
        }
        .disabled(!appStore.healthNudgeSettings.enabled)
    }

    private var smartNudgesFooterText: String {
        if appStore.healthNudgeSettings.movementEnabled,
           !(appStore.isHealthSyncEnabled && appStore.healthAuthorizationState == .authorized) {
            return "Movement nudges need Apple Health access. Turn on Apple Health sync in Settings to enable step-based reminders."
        }
        return "Hydration and protein nudges use what you've logged today. Movement uses your Apple Health step count."
    }

    private var notificationFooterText: String {
        switch appStore.notificationAuthState {
        case .authorized, .provisional:
            return "Turn reminders off here to stop Food App's scheduled meal nudges on this device."
        case .notDetermined:
            return "Turning reminders on will ask iOS for notification permission."
        case .denied:
            return "Notifications are blocked in iOS Settings. Turning this on will open Settings so you can allow them."
        default:
            return "Notification permission is currently unavailable on this device."
        }
    }

    private var remindersEnabledBinding: Binding<Bool> {
        Binding(
            get: { appStore.mealReminderSettings.remindersEnabled },
            set: { enabled in
                guard enabled else {
                    appStore.setMealRemindersEnabled(false)
                    return
                }

                switch appStore.notificationAuthState {
                case .authorized, .provisional, .ephemeral:
                    appStore.setMealRemindersEnabled(true)
                case .notDetermined:
                    requestNotificationPermission()
                case .denied:
                    appStore.setMealRemindersEnabled(false)
                    openAppSettings()
                default:
                    appStore.setMealRemindersEnabled(false)
                }
            }
        )
    }

    private var healthNudgesEnabledBinding: Binding<Bool> {
        Binding(
            get: { appStore.healthNudgeSettings.enabled },
            set: { enabled in
                guard enabled else {
                    appStore.setHealthNudgesEnabled(false)
                    return
                }

                switch appStore.notificationAuthState {
                case .authorized, .provisional, .ephemeral:
                    appStore.setHealthNudgesEnabled(true)
                case .notDetermined:
                    requestPermissionThenEnableHealthNudges()
                case .denied:
                    appStore.setHealthNudgesEnabled(false)
                    openAppSettings()
                default:
                    appStore.setHealthNudgesEnabled(false)
                }
            }
        )
    }

    private func healthNudgeBoolBinding(_ keyPath: WritableKeyPath<HealthNudgeSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appStore.healthNudgeSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = appStore.healthNudgeSettings
                settings[keyPath: keyPath] = newValue
                appStore.setHealthNudgeSettings(settings)
            }
        )
    }

    private var stepGoalBinding: Binding<Int> {
        Binding(
            get: { appStore.healthNudgeSettings.stepGoal },
            set: { newValue in
                var settings = appStore.healthNudgeSettings
                settings.stepGoal = newValue
                appStore.setHealthNudgeSettings(settings)
            }
        )
    }

    private func requestPermissionThenEnableHealthNudges() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        Task {
            let status = await appStore.requestNotificationAuthorization()
            await MainActor.run {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    appStore.setHealthNudgesEnabled(true)
                default:
                    appStore.setHealthNudgesEnabled(false)
                }
                isRequestingPermission = false
            }
        }
    }

    private func mealReminderRow(
        title: String,
        systemImage: String,
        enabledKeyPath: WritableKeyPath<MealReminderSettings, Bool>,
        startKeyPath: WritableKeyPath<MealReminderSettings, MealReminderTime>,
        endKeyPath: WritableKeyPath<MealReminderSettings, MealReminderTime>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: settingsBoolBinding(enabledKeyPath)) {
                Label(title, systemImage: systemImage)
            }

            if appStore.mealReminderSettings[keyPath: enabledKeyPath] {
                HStack(alignment: .top, spacing: 18) {
                    mealWindowTimePicker(
                        Text("From")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary),
                        selection: settingsTimeBinding(startKeyPath)
                    )
                    mealWindowTimePicker(
                        Text("Until")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary),
                        selection: settingsTimeBinding(endKeyPath)
                    )
                }
                .padding(.leading, 34)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }

    private func mealWindowTimePicker<Label: View>(
        _ label: Label,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsBoolBinding(_ keyPath: WritableKeyPath<MealReminderSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appStore.mealReminderSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = appStore.mealReminderSettings
                settings[keyPath: keyPath] = newValue
                appStore.setMealReminderSettings(settings)
            }
        )
    }

    private func settingsTimeBinding(_ keyPath: WritableKeyPath<MealReminderSettings, MealReminderTime>) -> Binding<Date> {
        Binding(
            get: { date(for: appStore.mealReminderSettings[keyPath: keyPath]) },
            set: { newDate in
                var settings = appStore.mealReminderSettings
                settings[keyPath: keyPath] = reminderTime(from: newDate)
                appStore.setMealReminderSettings(settings)
            }
        )
    }

    private func requestNotificationPermission() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        Task {
            let status = await appStore.requestNotificationAuthorization()
            await MainActor.run {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    appStore.setMealRemindersEnabled(true)
                default:
                    appStore.setMealRemindersEnabled(false)
                }
                isRequestingPermission = false
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func date(for time: MealReminderTime) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = time.hour
        components.minute = time.minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func reminderTime(from date: Date) -> MealReminderTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return MealReminderTime(hour: components.hour ?? 12, minute: components.minute ?? 0)
    }
}
