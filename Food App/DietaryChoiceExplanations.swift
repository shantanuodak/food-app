import Foundation

/// Per-option explanations for dietary preferences and allergies, surfaced
/// as inline disclosures next to each toggle in the Profile screen.
///
/// Voice locked 2026-05-01 (see L10n.swift voice rules):
/// - Always describes what the app does ("We'll flag…", "We'll favor…")
///   so the user knows what selecting the toggle changes.
/// - Plain, direct, no marketing language.
/// - Keep to 1-2 sentences. The Profile is a list view, not a doc.
///
/// These strings live here (not L10n.swift) because they're closely
/// coupled to the enum cases; moving them to L10n.swift would split a
/// single conceptual unit across two files. If we add localization
/// beyond English they migrate to L10n.swift then.

extension PreferenceChoice {
    /// One-sentence "what does selecting this do" copy. Visible when the
    /// user taps the info chevron next to a preference in the Profile.
    var explanation: String {
        switch self {
        case .highProtein:
            return "We'll favor higher-protein items in your suggestions and flag meals that fall short."
        case .vegetarian:
            return "We'll flag any meal that includes meat or fish."
        case .vegan:
            return "We'll flag meals with meat, fish, dairy, or eggs."
        case .pescatarian:
            return "We'll flag meals with meat. Fish is fine."
        case .lowCarb:
            return "We'll favor lower-carb items and flag carb-heavy meals."
        case .keto:
            return "We'll flag carb-heavy meals so you can stay in keto range."
        case .glutenFree:
            return "We'll flag meals containing wheat, barley, or rye."
        case .dairyFree:
            return "We'll flag meals with milk, cheese, butter, or yogurt."
        case .halal:
            return "We'll flag pork and alcohol in your meals."
        case .lowSodium:
            return "We'll favor lower-sodium items and flag meals high in salt."
        case .mediterranean:
            return "We'll lean toward olive oil, fish, vegetables, and whole grains in suggestions."
        case .noPreference:
            return "No flagging or filtering — every meal is fair game."
        }
    }
}

extension AllergyChoice {
    /// One-sentence "what does selecting this do" copy. Visible when the
    /// user taps the info chevron next to an allergy in the Profile.
    var explanation: String {
        switch self {
        case .peanuts:
            return "We'll flag any meal that includes peanuts."
        case .treeNuts:
            return "We'll flag meals with almonds, walnuts, cashews, pecans, pistachios, hazelnuts, macadamias, or Brazil nuts."
        case .gluten:
            return "We'll flag wheat, barley, rye, and anything made from them — bread, pasta, crackers, and so on."
        case .dairy:
            return "We'll flag milk, cheese, butter, yogurt, and cream."
        case .eggs:
            return "We'll flag meals containing eggs."
        case .shellfish:
            return "We'll flag shrimp, crab, lobster, and other shellfish."
        case .fish:
            return "We'll flag fish — salmon, tuna, cod, and the rest."
        case .soy:
            return "We'll flag tofu, edamame, soy sauce, and other soy ingredients."
        case .sesame:
            return "We'll flag sesame seeds, tahini, and items that include them."
        }
    }
}
