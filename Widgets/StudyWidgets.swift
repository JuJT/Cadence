import SwiftUI
import WidgetKit

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CadenceSemaine", provider: TodayProvider()) { entry in
            WeekWidgetView(entry: entry).containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Ma semaine")
        .description("Sept jours de cours et de révisions, avec les estimations séparées.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextCourseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CadenceProchainCours", provider: TodayProvider()) { entry in
            NextCourseWidgetView(entry: entry).containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Prochain cours")
        .description("La matière et l’horaire de votre prochain cours synchronisé.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AccessoryStudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CadenceTempsDuJour", provider: TodayProvider()) { entry in
            AccessoryStudyWidgetView(entry: entry).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Temps d’étude")
        .description("Les durées mesurées et confirmées du jour sur l’écran verrouillé.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
