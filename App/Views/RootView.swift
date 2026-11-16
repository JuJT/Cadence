import SwiftUI
import CadenceCore

private enum CadenceSection: String, CaseIterable, Identifiable {
    case accueil, cours, devoirs, revision, statistiques
    var id: String { rawValue }
    var title: String {
        switch self { case .accueil: return "Accueil"; case .cours: return "Cours"; case .devoirs: return "Devoirs"; case .revision: return "Révision"; case .statistiques: return "Statistiques" }
    }
    var symbol: String {
        switch self { case .accueil: return "house"; case .cours: return "calendar"; case .devoirs: return "checklist"; case .revision: return "timer"; case .statistiques: return "chart.bar" }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selected: CadenceSection = .accueil
    @State private var showSettings = false
    @AppStorage("cadence.appearance") private var appearance = "system"
    var body: some View {
        TabView(selection: $selected) {
            ForEach(CadenceSection.allCases) { section in
                navigation(section).tabItem { Label(section.title, systemImage: section.symbol) }.tag(section)
            }
        }
        .background(CadenceBackground(animated: false))
        .tint(Atelier.blue)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .fullScreenCover(isPresented: Binding(get: { !store.needsRecovery && !store.state.settings.onboardingCompleted }, set: { _ in })) {
            OnboardingView()
        }
        .alert("Cadenza", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Compris", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "Une erreur est survenue.") }
        .onChange(of: store.route) { _, route in
            if let section = CadenceSection(rawValue: route) { selected = section }
        }
        .onChange(of: selected) { _, section in store.route = section.rawValue }
        .onAppear { if let section = CadenceSection(rawValue: store.route) { selected = section } }
        .sensoryFeedback(.selection, trigger: store.state.activeSession?.id)
        .sensoryFeedback(.selection, trigger: store.state.activeSession?.isPaused)
    }
    private func navigation(_ section: CadenceSection) -> some View {
        NavigationStack {
            Group {
                switch section {
                case .accueil: HomeView()
                case .cours: CoursesView()
                case .devoirs: HomeworkView()
                case .revision: RevisionView()
                case .statistiques: StatisticsView()
                }
            }
            .modifier(CadenceTabEntrance(isSelected: selected == section))
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

private struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var page = 0
    @State private var showCalendar = false
    var body: some View {
        NavigationStack {
            AtelierPage {
                Spacer(minLength: 24)
                Image(systemName: page == 0 ? "chart.bar.xaxis" : "calendar.badge.clock")
                    .font(.system(size: 64, weight: .light)).foregroundStyle(Atelier.blue)
                    .frame(maxWidth: .infinity).accessibilityHidden(true)
                Text(page == 0 ? "Votre temps,\nvotre cadence." : "Un agenda qui\nvous ressemble.")
                    .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                Text(page == 0 ? "Gardez un suivi distinct de vos cours et de vos révisions. Vos séances personnelles restent sur cet appareil." : "Connectez votre espace scolaire sécurisé pour retrouver automatiquement vos cours et vos devoirs, même hors connexion après synchronisation.")
                    .font(.title3).foregroundStyle(.secondary)
                AtelierCard {
                    Label(page == 0 ? "Cours et révisions séparés" : "Connexion initiale sécurisée", systemImage: page == 0 ? "books.vertical" : "lock.shield")
                    Label(page == 0 ? "Des matières personnalisables" : "Cours passés comptés automatiquement", systemImage: page == 0 ? "pencil" : "checkmark.shield")
                    Label(page == 0 ? "Des sauvegardes que vous contrôlez" : "Retirez les cours qui n’ont pas eu lieu", systemImage: page == 0 ? "square.and.arrow.up" : "calendar.badge.minus")
                }
                if page == 0 {
                    ProminentAction(title: "Continuer", symbol: "arrow.right") { page = 1 }
                } else {
                    ProminentAction(title: "Connecter mon espace scolaire", symbol: "graduationcap") { showCalendar = true }
                    SecondaryAction(title: "Commencer avec le suivi manuel", symbol: "arrow.right") { complete() }
                }
            }
            .navigationTitle("Bienvenue sur Cadenza").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCalendar, onDismiss: { complete() }) { NavigationStack { SchoolConnectionView() } }
        }.interactiveDismissDisabled()
    }
    private func complete() { var settings = store.state.settings; settings.onboardingCompleted = true; store.updateSettings(settings) }
}
