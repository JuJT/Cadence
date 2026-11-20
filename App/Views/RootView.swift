import SwiftUI
import CadenceCore

private enum CadenceSection: String, CaseIterable, Identifiable {
    case accueil, cours, devoirs, notes, revision
    var id: String { rawValue }
    var title: String {
        switch self { case .accueil: return "Accueil"; case .cours: return "Cours"; case .devoirs: return "Devoirs"; case .revision: return "Révision"; case .notes: return "Notes" }
    }
    var symbol: String {
        switch self { case .accueil: return "house"; case .cours: return "calendar"; case .devoirs: return "checklist"; case .revision: return "timer"; case .notes: return "chart.bar" }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selected: CadenceSection = .accueil
    @State private var showStatistics = false
    @State private var showSettings = false
    @State private var introductionCompletedThisLaunch = false
    @AppStorage("cadence.appearance") private var appearance = "system"
    @AppStorage("cadence.introduction.lastSeenRelease") private var lastSeenRelease = ""
    var body: some View {
        TabView(selection: Binding(get: { selected }, set: { section in
            selected = section
            if section == .revision { showStatistics = false }
            store.route = section.rawValue
        })) {
            ForEach(CadenceSection.allCases) { section in
                navigation(section).tabItem { Label(section.title, systemImage: section.symbol) }.tag(section)
            }
        }
        .background(CadenceBackground(animated: false))
        .tint(Atelier.blue)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .fullScreenCover(isPresented: Binding(get: { introductionMode != nil }, set: { _ in })) {
            if let mode = introductionMode {
                AppIntroductionView(mode: mode) {
                    if mode == .setup {
                        var settings = store.state.settings
                        settings.onboardingCompleted = true
                        store.updateSettings(settings)
                    }
                    lastSeenRelease = AppIntroductionView.releaseID
                    introductionCompletedThisLaunch = true
                }
            }
        }
        .alert("Cadenza", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Compris", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "Une erreur est survenue.") }
        .onChange(of: store.route, initial: true) { _, route in
            if route == "statistiques" {
                selected = .revision
                showStatistics = true
            } else if let section = CadenceSection(rawValue: route) {
                selected = section
                if section == .revision { showStatistics = false }
            }
        }
        .onChange(of: showStatistics) { _, presented in
            if !presented && store.route == "statistiques" { store.route = "revision" }
        }
        .sensoryFeedback(.selection, trigger: store.state.activeSession?.id)
        .sensoryFeedback(.selection, trigger: store.state.activeSession?.isPaused)
    }
    private var introductionMode: AppIntroductionMode? {
        guard !store.needsRecovery, !introductionCompletedThisLaunch else { return nil }
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitesting-onboarding") { return .setup }
        if arguments.contains("--uitesting-whats-new") { return .update }
        if arguments.contains("--uitesting") { return nil }
        #endif
        if !store.state.settings.onboardingCompleted { return .setup }
        return lastSeenRelease != AppIntroductionView.releaseID ? .update : nil
    }
    private func navigation(_ section: CadenceSection) -> some View {
        NavigationStack {
            Group {
                switch section {
                case .accueil: HomeView()
                case .cours: CoursesView()
                case .devoirs: HomeworkView()
                case .revision:
                    RevisionView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Statistiques", systemImage: "chart.bar") { store.route = "statistiques" }
                                    .accessibilityIdentifier("revision.statistics")
                            }
                        }
                        .navigationDestination(isPresented: $showStatistics) { StatisticsView() }
                case .notes:
                    if store.pronoteProfile == nil && store.pronotePortal.profile == nil && !store.pronotePortal.sections.keys.contains(where: { $0.hasPrefix("grades") }) {
                        AtelierPage {
                            EmptyCard(title: "Vos résultats scolaires", symbol: "chart.bar", description: "Connectez PRONOTE pour retrouver vos notes et vos moyennes par période.")
                            NavigationLink("Connecter PRONOTE") { SchoolConnectionView() }.buttonStyle(.borderedProminent)
                        }.navigationTitle("Notes")
                    } else { PronoteSectionView(section: .grades) }
                }
            }
            .environment(\.cadenceTabIsActive, selected == section && !showSettings && introductionMode == nil)
            .background(CadenceBackground(animated: false))
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if section == .accueil {
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarLeading) { brandMark }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarLeading) { brandMark }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Réglages", systemImage: "gearshape") { showSettings = true }
                }
            }
        }
    }
    private var brandMark: some View {
        HStack(spacing: 7) {
            Image("CadenceMark").resizable().frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
            Text("Cadenza").font(.subheadline.weight(.semibold)).foregroundStyle(CadenceColors.secondary)
        }.fixedSize(horizontal: true, vertical: false).accessibilityElement(children: .combine)
    }
}
