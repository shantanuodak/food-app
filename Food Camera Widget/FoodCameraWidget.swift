import SwiftUI
import WidgetKit

struct FoodCameraWidgetEntry: TimelineEntry {
    let date: Date
}

struct FoodCameraWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodCameraWidgetEntry {
        FoodCameraWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (FoodCameraWidgetEntry) -> Void) {
        completion(FoodCameraWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodCameraWidgetEntry>) -> Void) {
        let entry = FoodCameraWidgetEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
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
                .widgetURL(Self.cameraURL)
                .accessibilityLabel("Open Food Camera")

        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Food Camera")
                        .font(.headline)
                    Text("Tap to log")
                        .font(.caption2)
                }
            }
            .widgetURL(Self.cameraURL)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open Food Camera")

        default:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.86, blue: 0.45),
                        Color(red: 0.98, green: 0.48, blue: 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.55), in: Circle())

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Food Camera")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                        Text("Tap to capture")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.68))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(14)
            }
            .widgetURL(Self.cameraURL)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open Food Camera")
        }
    }

    private static let cameraURL = URL(string: "foodapp://camera")!
}

struct FoodCameraWidget: Widget {
    let kind = "FoodCameraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoodCameraWidgetProvider()) { entry in
            FoodCameraWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Food Camera")
        .description("Open Food App directly to the quick camera.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct FoodCameraWidgetBundle: WidgetBundle {
    var body: some Widget {
        FoodCameraWidget()
    }
}
