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
    @State private var showSettings = false
    @State private var introductionCompletedThisLaunch = false
    @AppStorage("cadence.appearance") private var appearance = "system"
    @AppStorage("cadence.introduction.lastSeenRelease") private var lastSeenRelease = ""

    private var statisticsPresented: Bool { store.route == "statistiques" }
    private var selected: CadenceSection {
        statisticsPresented ? .revision : CadenceSection(rawValue: store.route) ?? .accueil
    }

    var body: some View {
        TabView(selection: Binding(get: { selected }, set: { section in
            if store.route != section.rawValue { store.route = section.rawValue }
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
                        .navigationDestination(isPresented: Binding(get: { statisticsPresented }, set: { presented in
                            if !presented && statisticsPresented { store.route = "revision" }
                        })) { StatisticsView() }
                case .notes:
                    if store.pronoteProfile == nil && store.pronotePortal.profile == nil && !store.pronotePortal.sections.keys.contains(where: { $0.hasPrefix("grades") }) {
                        AtelierPage {
                            EmptyCard(title: "Vos résultats scolaires", symbol: "chart.bar", description: "Connectez PRONOTE pour retrouver vos notes et vos moyennes par période.")
                            NavigationLink("Connecter PRONOTE") { SchoolConnectionView() }.buttonStyle(.borderedProminent)
                        }.navigationTitle("Notes")
                    } else { PronoteSectionView(section: .grades) }
                }
            }
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
        .id(section == .revision ? store.revisionNavigationID : nil)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selected == section && (section != .revision || statisticsPresented), let session = store.state.activeSession {
                ActiveSessionBar(session: session, subject: Atelier.subject(session.subjectID, in: store.state)) {
                    store.openRevisionRoot()
                }
            }
        }
        .environment(\.cadenceTabIsActive, selected == section && !showSettings && introductionMode == nil)
    }
    private var brandMark: some View {
        HStack(spacing: 7) {
            Image("CadenceMark").resizable().frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
            Text("Cadenza").font(.subheadline.weight(.semibold)).foregroundStyle(CadenceColors.secondary)
        }.fixedSize(horizontal: true, vertical: false).accessibilityElement(children: .combine)
    }
}

private struct ActiveSessionBar: View {
    let session: StudySession
    let subject: Subject?
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: session.isPaused ? "pause.circle.fill" : "timer")
                    .font(.title3)
                    .foregroundStyle(Atelier.blue)
                    .accessibilityHidden(true)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        sessionInfo
                        elapsed
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    sessionInfo.lineLimit(1)
                    Spacer(minLength: 0)
                    elapsed
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .cadenceReadingSurface(radius: 16, tint: Atelier.blue)
        }
        .buttonStyle(.plain)
        .tint(Atelier.blue)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .accessibilityIdentifier("session.banner")
        .accessibilityHint("Ouvre le chronomètre de la séance")
    }

    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subject?.name ?? session.kind.label).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Text(session.isPaused ? "Séance en pause" : "\(session.kind.label) en cours")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var elapsed: some View {
        SessionElapsedText(session: session)
            .font(.subheadline.weight(.semibold)).foregroundStyle(Atelier.blue)
            .fixedSize(horizontal: true, vertical: false)
    }
}
