import SwiftUI
import WidgetKit

struct SchoolWidgetBundle: WidgetBundle {
    var body: some Widget {
        GradeWidget()
        HomeworkWidget()
        AccessoryStudyWidget()
    }
}

struct GradeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CadenzaMoyenne", provider: TodayProvider()) { entry in
            GradeWidgetView(entry: entry).containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Moyenne générale")
        .description("Votre moyenne pour la période actuelle de PRONOTE.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CadenzaDevoirs", provider: TodayProvider()) { entry in
            HomeworkWidgetView(entry: entry).containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Devoirs à venir")
        .description("Les devoirs à faire et votre prochaine échéance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CadenceSemaine", provider: TodayProvider()) { entry in
            WeekWidgetView(entry: entry).containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Ma semaine")
        .description("Sept jours de cours et de révisions.")
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
        .description("Votre temps de cours et de révisions du jour sur l’écran verrouillé.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
