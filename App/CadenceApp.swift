import SwiftUI
import AppIntents

@main
struct CadenceApp: App {
    @StateObject private var store = AppStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CadenceShortcuts.updateAppShortcutParameters()
        TimetableNotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--uitesting-widget-preview") {
                WidgetDesignPreviewScreen().environment(\.locale, Locale(identifier: "fr_FR"))
            } else { mainContent }
            #else
            mainContent
            #endif
        }
        .backgroundTask(.appRefresh(TimetableNotificationService.taskID)) {
            await AppStore.shared.refreshScheduleInBackground()
        }
    }

    @ViewBuilder private var mainContent: some View {
            #if CADENCE_SPIKE
            SpikeView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .task { await store.foreground() }
                .onOpenURL { _ in Task { await store.foreground() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.foreground() } }
                }
            #else
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .tint(Color(red: 39 / 255, green: 118 / 255, blue: 248 / 255))
                .onOpenURL { url in
                    guard url.scheme == "cadence" else { return }
                    switch url.host {
                    case "cours": store.route = "cours"
                    case "notes": store.route = "notes"
                    case "revision": store.route = "revision"
                    case "statistiques": store.route = "statistiques"
                    case "devoirs": store.route = "devoirs"
                    default: store.route = "accueil"
                    }
                }
                .task { await store.foreground() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(300)) } catch { return }
                        if TimetableNotificationService.shared.enabled { await store.refreshSchool(force: false) }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.foreground() } }
                    if phase == .background { TimetableNotificationService.shared.scheduleNextRefresh() }
                }
            #endif
    }
}
