import SwiftUI
import WidgetKit
import AppIntents

private enum FoodWidgetSharedStore {
    static let appGroupID = "group.com.shantanu.foodapp"
    static let snapshotKey = "widget.dailyCaloriesSnapshot"
}

struct FoodWidgetCaloriesSnapshot: Codable, Equatable {
    let date: String
    let consumedCalories: Double
    let targetCalories: Double
    let consumedProtein: Double?
    let consumedCarbs: Double?
    let consumedFat: Double?
    let updatedAt: Date
}

struct FoodCameraWidgetEntry: TimelineEntry {
    let date: Date
    let calories: FoodWidgetCaloriesSnapshot?

    static func current(date: Date = Date()) -> FoodCameraWidgetEntry {
        FoodCameraWidgetEntry(date: date, calories: Self.loadCaloriesSnapshot())
    }

    private static func loadCaloriesSnapshot() -> FoodWidgetCaloriesSnapshot? {
        guard let data = UserDefaults(suiteName: FoodWidgetSharedStore.appGroupID)?
            .data(forKey: FoodWidgetSharedStore.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(FoodWidgetCaloriesSnapshot.self, from: data)
    }
}

struct FoodCameraWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodCameraWidgetEntry {
        FoodCameraWidgetEntry(
            date: Date(),
            calories: FoodWidgetCaloriesSnapshot(
                date: "today",
                consumedCalories: 1_250,
                targetCalories: 1_770,
                consumedProtein: 92,
                consumedCarbs: 168,
                consumedFat: 47,
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FoodCameraWidgetEntry) -> Void) {
        completion(.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodCameraWidgetEntry>) -> Void) {
        let entry = FoodCameraWidgetEntry.current()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct FoodCameraWidgetView: View {
    let entry: FoodCameraWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "fork.knife")
                .font(.system(size: 19, weight: .semibold))
                .widgetURL(Self.quickCameraURL)
                .accessibilityLabel("Open Food Camera")

        case .accessoryRectangular:
            calorieProgressAccessory
            .accessibilityElement(children: .combine)
            .accessibilityLabel(calorieProgressAccessibilityLabel)

        default:
            smallDailyWidget
            .accessibilityElement(children: .combine)
            .accessibilityLabel(smallWidgetAccessibilityLabel)
        }
    }

    private static let cameraURL = URL(string: "foodapp://camera")!
    private static let quickCameraURL = URL(string: "foodapp://quick-camera")!
    private static let voiceURL = URL(string: "foodapp://voice")!

    private var smallDailyWidget: some View {
        let consumed = max(0, entry.calories?.consumedCalories ?? 0)
        let target = max(0, entry.calories?.targetCalories ?? 0)
        let fraction = target > 0 ? min(consumed / target, 1) : 0

        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.060, blue: 0.085),
                    Color(red: 0.090, green: 0.075, blue: 0.125),
                    Color(red: 0.060, green: 0.085, blue: 0.115)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.48, blue: 0.14).opacity(0.18),
                    Color(red: 0.42, green: 0.37, blue: 1.0).opacity(0.14),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Int(consumed.rounded()).formatted())")
                        .font(.system(size: 29, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.70)
                        .foregroundStyle(.white)
                    Text("cal")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.16))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.44, blue: 0.12),
                                        Color(red: 1.00, green: 0.72, blue: 0.26)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, proxy.size.width * fraction))
                    }
                }
                .frame(height: 6)

                HStack(spacing: 7) {
                    macroStat(label: "P", value: entry.calories?.consumedProtein, color: Color(red: 0.420, green: 0.369, blue: 1.0))
                    macroStat(label: "C", value: entry.calories?.consumedCarbs, color: Color(red: 0.106, green: 0.620, blue: 0.353))
                    macroStat(label: "F", value: entry.calories?.consumedFat, color: Color(red: 0.000, green: 0.478, blue: 1.0))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .padding(.top, 2)

                Spacer(minLength: 2)

                HStack(spacing: 22) {
                    Link(destination: Self.cameraURL) {
                        actionIcon(
                            "camera.fill",
                            label: "Open camera",
                            tint: Color(red: 1.00, green: 0.48, blue: 0.12)
                        )
                    }

                    Link(destination: Self.voiceURL) {
                        actionIcon(
                            "mic.fill",
                            label: "Start voice logging",
                            tint: Color(red: 0.38, green: 0.32, blue: 0.96)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(15)
        }
    }

    private var calorieProgressAccessory: some View {
        let consumed = max(0, entry.calories?.consumedCalories ?? 0)
        let target = max(0, entry.calories?.targetCalories ?? 0)
        let fraction = target > 0 ? min(consumed / target, 1) : 0

        // 2026-05-22: dropped the leading fork.knife badge from this layout.
        // On iPhone SE / mini lock screens the badge + spacer left the
        // calorie Text too little horizontal room and SwiftUI was clipping
        // 3-digit numbers ("842" rendered as "8…"). Two-line stack with
        // minimumScaleFactor keeps the value readable across all devices,
        // and the system already paints the widget glyph above the layout.
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(consumed.rounded()).formatted())")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text("kcal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.28))
                    Capsule()
                        .fill(.orange)
                        .frame(width: max(3, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)

            Text(target > 0 ? "of \(Int(target.rounded()).formatted())" : "Today")
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.secondary)
        }
    }

    private func macroStat(label: String, value: Double?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 13.5, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)

            Text("\(Int(max(0, value ?? 0).rounded()))g")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func actionIcon(_ systemImage: String, label: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(
                LinearGradient(
                    colors: [
                        .white.opacity(0.18),
                        tint.opacity(0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.32),
                                tint.opacity(0.70)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(0.16), radius: 7, x: 0, y: 3)
            .accessibilityLabel(label)
    }

    private var calorieProgressAccessibilityLabel: String {
        let consumed = Int(max(0, entry.calories?.consumedCalories ?? 0).rounded())
        let target = Int(max(0, entry.calories?.targetCalories ?? 0).rounded())
        guard target > 0 else {
            return "Today, \(consumed) calories logged"
        }
        return "Today, \(consumed) of \(target) calories logged"
    }

    private var smallWidgetAccessibilityLabel: String {
        let consumed = Int(max(0, entry.calories?.consumedCalories ?? 0).rounded())
        let target = Int(max(0, entry.calories?.targetCalories ?? 0).rounded())
        let protein = Int(max(0, entry.calories?.consumedProtein ?? 0).rounded())
        let carbs = Int(max(0, entry.calories?.consumedCarbs ?? 0).rounded())
        let fat = Int(max(0, entry.calories?.consumedFat ?? 0).rounded())

        if target > 0 {
            return "\(consumed) of \(target) calories. Protein \(protein) grams, carbs \(carbs) grams, fat \(fat) grams. Camera and voice logging available."
        }
        return "\(consumed) calories today. Protein \(protein) grams, carbs \(carbs) grams, fat \(fat) grams. Camera and voice logging available."
    }
}

struct FoodCameraWidget: Widget {
    let kind = "FoodCameraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoodCameraWidgetProvider()) { entry in
            FoodCameraWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Food App")
        .description("See today's calories or open the quick camera.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

@available(iOS 18.0, *)
struct FoodCameraControl: ControlWidget {
    let kind = "FoodCameraControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind) {
            ControlWidgetButton(action: OpenFoodCameraControlIntent()) {
                Label("Food Camera", systemImage: "fork.knife")
            }
            .tint(.orange)
        }
        .displayName("Food Camera")
        .description("Open Food App directly to the quick camera.")
    }
}

@available(iOS 18.0, *)
enum FoodCameraControlTarget: String, AppEnum {
    case camera

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food Camera")
    static var caseDisplayRepresentations: [FoodCameraControlTarget: DisplayRepresentation] = [
        .camera: DisplayRepresentation(title: "Food Camera")
    ]
}

@available(iOS 18.0, *)
struct OpenFoodCameraControlIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Food Camera"
    static var description = IntentDescription("Opens Food App directly to the quick camera logger.")

    @Parameter(title: "Target")
    var target: FoodCameraControlTarget

    init() {
        self.target = .camera
    }

    init(target: FoodCameraControlTarget) {
        self.target = target
    }
}

enum FoodCameraURL {
    nonisolated static let camera = URL(string: "foodapp://camera")!
}

@main
struct FoodCameraWidgetBundle: WidgetBundle {
    var body: some Widget {
        FoodCameraWidget()
        if #available(iOS 18.0, *) {
            FoodCameraControl()
        }
    }
}
