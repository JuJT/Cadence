import SwiftUI
import CadenceCore

private enum CadenceSection: String, CaseIterable, Identifiable {
    case accueil, cours, revision, statistiques
    var id: String { rawValue }
    var title: String {
        switch self { case .accueil: return "Accueil"; case .cours: return "Cours"; case .revision: return "Révision"; case .statistiques: return "Statistiques" }
    }
    var symbol: String {
        switch self { case .accueil: return "house"; case .cours: return "calendar"; case .revision: return "timer"; case .statistiques: return "chart.bar" }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selected: CadenceSection = .accueil
    @State private var showSettings = false
    @AppStorage("cadence.appearance") private var appearance = "system"
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    List {
                        ForEach(CadenceSection.allCases) { section in
                            Button { selected = section } label: {
                                Label(section.title, systemImage: section.symbol)
                                    .foregroundStyle(selected == section ? Atelier.blue : .primary)
                            }.listRowBackground(selected == section ? Atelier.blue.opacity(0.1) : Color.clear)
                        }
                        Button { showSettings = true } label: { Label("Réglages", systemImage: "gearshape") }
                    }.navigationTitle("Cadence").cadenceListStyle()
                } detail: { navigation(selected) }
            } else {
                TabView(selection: $selected) {
                    ForEach(CadenceSection.allCases) { section in
                        navigation(section).tabItem { Label(section.title, systemImage: section.symbol) }.tag(section)
                    }
                }
            }
        }
        .background(CadenceBackground())
        .tint(Atelier.blue)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .environment(\.locale, Locale(identifier: "fr_FR"))
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .fullScreenCover(isPresented: Binding(get: { !store.needsRecovery && !store.state.settings.onboardingCompleted }, set: { _ in })) {
            OnboardingView()
        }
        .alert("Cadence", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
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
                case .revision: RevisionView()
                case .statistiques: StatisticsView()
                }
            }
            .background(CadenceBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if section == .accueil {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 7) {
                            Image("CadenceMark").resizable().frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
                            Text("Cadence").font(.subheadline.weight(.semibold)).foregroundStyle(CadenceColors.secondary)
                        }.accessibilityElement(children: .combine)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Réglages", systemImage: "gearshape") { showSettings = true }
                }
            }
        }
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
                Text(page == 0 ? "Gardez un suivi distinct de vos cours et de vos révisions. Vos données restent sur cet appareil, sans compte ni abonnement." : "Liez les calendriers déjà présents sur votre iPhone, y compris Google. Cadence les consulte sans modifier vos événements.")
                    .font(.title3).foregroundStyle(.secondary)
                AtelierCard {
                    Label(page == 0 ? "Cours et révisions séparés" : "Connexion facultative", systemImage: page == 0 ? "books.vertical" : "hand.raised")
                    Label(page == 0 ? "Des matières personnalisables" : "Aucun cours estimé sans votre accord", systemImage: page == 0 ? "pencil" : "checkmark.shield")
                    Label(page == 0 ? "Des sauvegardes que vous contrôlez" : "Le chronomètre fonctionne sans calendrier", systemImage: page == 0 ? "square.and.arrow.up" : "timer")
                }
                if page == 0 {
                    ProminentAction(title: "Continuer", symbol: "arrow.right") { page = 1 }
                } else {
                    ProminentAction(title: "Choisir mes calendriers", symbol: "calendar") { showCalendar = true }
                    SecondaryAction(title: "Commencer sans calendrier", symbol: "arrow.right") { complete() }
                }
            }
            .navigationTitle("Bienvenue sur Cadence").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCalendar, onDismiss: { complete() }) { NavigationStack { CalendarSettingsView() } }
        }.interactiveDismissDisabled()
    }
    private func complete() { var settings = store.state.settings; settings.onboardingCompleted = true; store.updateSettings(settings) }
}
