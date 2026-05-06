import Foundation

extension OnboardingRoute {
    var headline: String {
        switch self {
        case .welcome:
            return "Log your food with less effort"
        case .goal:
            return "What’s your goal right now?"
        case .age:
            return "How young are you?"
        case .baseline:
            return "Let’s set your baseline"
        case .activity:
            return "How active are you most days?"
        case .pace:
            return "Choose your pace"
        case .preferencesOptional:
            return "Food Preferences"
        case .planPreview:
            return "Your plan is ready"
        case .account:
            return "Save your setup"
        case .permissions:
            return "Apple Health"
        case .notificationsPermission:
            return "Notifications"
        case .ready:
            return "You’re all set"
        case .goalValidation:
            return "Your plan is ready"
        case .socialProof:
            return "Food App provides long-term results"
        case .challenge:
            return "What's your biggest challenge?"
        case .experience:
            return "Have you tried calorie counting before?"
        case .howItWorks:
            return "Why Food App's approach works"
        case .challengeInsight:
            return ""
        }
    }

    var subhead: String {
        switch self {
        case .welcome:
            return "Set up tracking in under 2 minutes."
        case .goal:
            return "We’ll use this to set your calorie and macro direction."
        case .age:
            return "We will use this to calulate BMI"
        case .baseline:
            return "Add your profile details so calorie estimates are personalized."
        case .activity:
            return "Choose your typical day, not your best day."
        case .pace:
            return "Consistency beats speed. Pick a pace you can sustain."
        case .preferencesOptional:
            return ""
        case .planPreview:
            return "Here is your starting target. You can adjust this later."
        case .account:
            return "Create or connect an account to keep your progress synced."
        case .permissions:
            return "Optional. Sync activity automatically — you can change this later in Settings."
        case .notificationsPermission:
            return "Optional. Helpful reminders to stay consistent — you can change this later in Settings."
        case .ready:
            return "You’re ready to log your first meal."
        case .goalValidation:
            return "Based on your profile, here’s your starting target."
        case .socialProof:
            return ""
        case .challenge:
            return ""
        case .experience:
            return ""
        case .howItWorks:
            return ""
        case .challengeInsight:
            return ""
        }
    }
}

