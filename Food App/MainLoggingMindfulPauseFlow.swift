import Foundation

extension MainLoggingShellView {
    @discardableResult
    func presentMindfulPauseIfNeeded(for action: MindfulPauseAction, now: Date = Date()) -> Bool {
        guard appStore.selectedChallenge == .emotionalEating else { return false }
        guard !isMindfulPausePresented else { return true }
        guard MindfulPauseGate.shouldShow(today: now) else { return false }
        guard isOutsideMealTime(now: now, settings: appStore.mealReminderSettings) else { return false }

        pendingMindfulPauseAction = action
        isMindfulPausePresented = true
        return true
    }

    func performMindfulPauseAction(_ action: MindfulPauseAction) {
        switch action {
        case .text:
            inputMode = .text
            NotificationCenter.default.post(name: .focusComposerInputFromBackgroundTap, object: nil)

        case .voice:
            inputMode = .voice

        case let .camera(source, isQuickCapture):
            isQuickCameraCaptureActive = isQuickCapture
            handleCameraSourceSelection(source)
        }
    }

    private func isOutsideMealTime(now: Date, settings: MealReminderSettings) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if settings.eatingWindowEnabled {
            return !isMinute(
                minuteOfDay,
                insideStart: settings.eatingWindowStart.minutesFromMidnight,
                end: settings.eatingWindowEnd.minutesFromMidnight
            )
        }

        let mealWindows: [(enabled: Bool, start: MealReminderTime, end: MealReminderTime)] = [
            (settings.breakfastEnabled, settings.breakfastStart, settings.breakfast),
            (settings.lunchEnabled, settings.lunchStart, settings.lunch),
            (settings.dinnerEnabled, settings.dinnerStart, settings.dinner)
        ]

        let enabledWindows = mealWindows.filter(\.enabled)
        guard !enabledWindows.isEmpty else { return false }

        return !enabledWindows.contains { window in
            isMinute(
                minuteOfDay,
                insideStart: window.start.minutesFromMidnight,
                end: window.end.minutesFromMidnight
            )
        }
    }

    private func isMinute(_ minute: Int, insideStart start: Int, end: Int) -> Bool {
        if start <= end {
            return minute >= start && minute <= end
        }
        return minute >= start || minute <= end
    }
}

private extension MealReminderTime {
    var minutesFromMidnight: Int {
        hour * 60 + minute
    }
}
