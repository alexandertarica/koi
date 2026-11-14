import WidgetKit
import SwiftUI

private struct BalanceEntry: TimelineEntry {
    let date: Date
    let balance: Int
}

private struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry { BalanceEntry(date: .now, balance: 0) }
    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(BalanceEntry(date: .now, balance: UserDefaults(suiteName: "group.com.alexandertarica.koi")?.integer(forKey: "balance.today") ?? 0))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let entry = BalanceEntry(date: .now, balance: UserDefaults(suiteName: "group.com.alexandertarica.koi")?.integer(forKey: "balance.today") ?? 0)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 30))))
    }
}

private struct BalanceWidgetView: View {
    let entry: BalanceEntry
    var body: some View {
        ZStack {
            Color(red: 0x2B / 255, green: 0x40 / 255, blue: 0x67 / 255)
            VStack(alignment: .leading, spacing: 5) {
                Text("BALANCE").font(.system(size: 10, design: .monospaced)).tracking(2)
                Text("\(entry.balance)%").font(.system(size: 34, weight: .light, design: .rounded))
            }
            .foregroundStyle(Color(red: 0xF0 / 255, green: 0xE8 / 255, blue: 0xDB / 255))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
        }
        .containerBackground(.clear, for: .widget)
    }
}

@main
struct KoiWidget: Widget {
    let kind = "KoiBalance"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Koi Balance")
        .description("Your balance for today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
