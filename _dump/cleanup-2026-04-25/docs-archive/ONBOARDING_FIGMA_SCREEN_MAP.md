# Onboarding Figma Screen Map

Date: 2026-03-15

Purpose: This file tracks the current Figma source-of-truth links for each onboarding screen in the iOS app so implementation can happen screen by screen.

Source onboarding flow in code:

- `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/AppFlowCoordinator.swift`
- `/Users/shantanuodak/Desktop/Codex Folders/Food App/Food App/Food App/OnboardingView.swift`

## Current Onboarding Screens

1. `Welcome`
   Code screen: `OB01WelcomeScreen`
   Figma: pending

2. `Goal`
   Code screen: `OB02GoalScreen`
   Figma: pending

3. `Baseline`
   Code screen: `OB03BaselineScreen`
   Figma:
   - Variant 1: `https://www.figma.com/design/DhFzjShBStaYPuueglO4tn/Food-App?node-id=68-266&t=FUeX9EQ1zdvlxMfc-4`
   - Variant 2: `https://www.figma.com/design/DhFzjShBStaYPuueglO4tn/Food-App?node-id=68-486&t=FUeX9EQ1zdvlxMfc-4`
   - Variant 3: `https://www.figma.com/design/DhFzjShBStaYPuueglO4tn/Food-App?node-id=68-310&t=FUeX9EQ1zdvlxMfc-4`
   Notes:
   - Treat these as separate states or sub-screens of the same baseline step until implementation confirms the intended behavior split.

4. `Activity`
   Code screen: `OB04ActivityScreen`
   Figma:
   - `https://www.figma.com/design/DhFzjShBStaYPuueglO4tn/Food-App?node-id=68-595&t=FUeX9EQ1zdvlxMfc-4`

5. `Pace`
   Code screen: `OB05PaceScreen`
   Figma:
   - Variant 1: `https://www.figma.com/design/DhFzjShBStaYPuueglO4tn/Food-App?node-id=68-691&t=FUeX9EQ1zdvlxMfc-4`
   - Variant 2: `https://www.figma.com/design/DhFzjShBStaYPuueglO4tn/Food-App?node-id=68-1088&t=FUeX9EQ1zdvlxMfc-4`
   - Variant 3: `https://www.figma.com/design/DhFzjShBStaYPuueglO4tn/Food-App?node-id=68-1031&t=FUeX9EQ1zdvlxMfc-4`
   Notes:
   - Treat these as separate pace states or option-selection states until implementation confirms exact mapping.

6. `Preferences`
   Code screen: `OB06PreferencesOptionalScreen`
   Figma:
   - deleted by product direction
   Notes:
   - Current instruction is to remove this page from the onboarding flow rather than redesign it.

7. `Plan Preview`
   Code screen: `OB07PlanPreviewScreen`
   Figma: pending

8. `Account`
   Code screen: `OB08AccountScreen`
   Figma: pending

9. `Permissions`
   Code screen: `OB09PermissionsScreen`
   Figma: pending

10. `Ready`
    Code screen: `OB10ReadyScreen`
    Figma: pending

## Current Product Direction Captured

- `Preferences` should be removed from onboarding.
- `Baseline` has 3 linked design nodes that likely represent multiple states within the same step.
- `Pace` has 3 linked design nodes that likely represent multiple states within the same step.

## Next Implementation Order

Recommended order based on the links currently available:

1. `Baseline`
2. `Activity`
3. `Pace`
4. remove `Preferences` from flow
5. continue once Figma links are provided for:
   - `Welcome`
   - `Goal`
   - `Plan Preview`
   - `Account`
   - `Permissions`
   - `Ready`
