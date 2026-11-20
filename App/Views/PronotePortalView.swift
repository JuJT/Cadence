import SwiftUI
import CadenceCore

enum PronotePortalSection: String, CaseIterable, Identifiable {
    case grades, evaluations, attendance, news, discussions, menus, contents, gradebook, account, homepage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grades: return "Notes"
        case .evaluations: return "Compétences"
        case .attendance: return "Vie scolaire"
        case .news: return "Informations"
        case .discussions: return "Messagerie"
        case .menus: return "Menus"
        case .contents: return "Contenus des cours"
        case .gradebook: return "Bulletin"
        case .account: return "Mon compte"
        case .homepage: return "Liens de l’établissement"
        }
    }
    var symbol: String {
        switch self {
        case .grades: return "chart.bar.xaxis"
        case .evaluations: return "checkmark.seal"
        case .attendance: return "person.crop.circle.badge.clock"
        case .news: return "bell"
        case .discussions: return "bubble.left.and.bubble.right"
        case .menus: return "fork.knife"
        case .contents: return "books.vertical"
        case .gradebook: return "doc.text"
        case .account: return "person.crop.circle"
        case .homepage: return "building.2"
        }
    }
    var subtitle: String {
        switch self {
        case .grades: return "Vos résultats et moyennes"
        case .evaluations: return "Acquis et évaluations"
        case .attendance: return "Absences, retards et observations"
        case .news: return "Actualités de votre établissement"
        case .discussions: return "Lire et répondre à vos échanges"
        case .menus: return "Les repas de la semaine"
        case .contents: return "Leçons et documents partagés"
        case .gradebook: return "Appréciations par période"
        case .account: return "Coordonnées de votre compte scolaire"
        case .homepage: return "Les services de votre établissement"
        }
    }
    var usesPeriod: Bool { [.grades, .evaluations, .attendance, .gradebook].contains(self) }
    var usesWeek: Bool { self == .menus }
}

struct PronotePortalView: View {
    @EnvironmentObject private var store: AppStore

    private var profile: PronoteProfile? { store.pronoteProfile ?? store.pronotePortal.profile }
    private var sections: [PronotePortalSection] {
        PronotePortalSection.allCases.filter { section in
            profile?.capabilities.contains(section.rawValue) == true ||
            store.pronotePortal.sections.keys.contains { $0 == section.rawValue || $0.hasPrefix(section.rawValue + ":") }
        }
    }

    var body: some View {
        AtelierPage(lazy: true) {
            if let profile {
                AtelierCard {
                    Label(profile.displayName, systemImage: "person.crop.circle.fill").font(.title3.bold())
                    Text([profile.establishment, profile.className].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(CadenceColors.secondary)
                }
            }
            if sections.isEmpty {
                EmptyCard(title: "Votre espace scolaire", symbol: "graduationcap",
                          description: "Connectez PRONOTE pour retrouver vos notes, les informations et les ressources partagées par vos professeurs.")
                NavigationLink { SchoolConnectionView() } label: {
                    Label("Connexion PRONOTE", systemImage: "person.badge.key")
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            ForEach(sections) { section in
                NavigationLink { PronoteSectionView(section: section) } label: {
                    AtelierCard {
                        HStack(spacing: 14) {
                            Image(systemName: section.symbol).font(.title2).foregroundStyle(Atelier.blue).frame(width: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(section.title).font(.headline).foregroundStyle(CadenceColors.ink)
                                Text(section.subtitle).font(.subheadline).foregroundStyle(CadenceColors.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CadenceColors.secondary)
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("pronote.portal." + section.rawValue)
            }
            if !sections.isEmpty {
                Text("Les rubriques déjà consultées restent disponibles hors connexion.")
                    .font(.caption).foregroundStyle(CadenceColors.secondary)
            }
        }
        .navigationTitle("Mon espace scolaire")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("pronote.portal")
    }
}

/// The same school destinations are available from the daily overview and the course tab.
struct PronoteQuickLinksView: View {
    let sections: [PronotePortalSection]
    @EnvironmentObject private var store: AppStore
    private var available: [PronotePortalSection] {
        let profile = store.pronoteProfile ?? store.pronotePortal.profile
        return sections.filter { section in
            profile?.capabilities.contains(section.rawValue) == true ||
            store.pronotePortal.sections.keys.contains { $0 == section.rawValue || $0.hasPrefix(section.rawValue + ":") }
        }
    }
    var body: some View {
        if !available.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 147), spacing: 10)], spacing: 10) {
                ForEach(available) { section in
                    NavigationLink { PronoteSectionView(section: section) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: section.symbol).foregroundStyle(Atelier.blue)
                                .frame(width: 24).accessibilityHidden(true)
                            Text(section.title).font(.subheadline.weight(.semibold)).foregroundStyle(CadenceColors.ink)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 4).cadenceSurface(radius: 17)
                    }.buttonStyle(.plain).accessibilityIdentifier("pronote.quick." + section.rawValue)
                }
            }
        }
    }
}

struct PronoteShortcutRow: View {
    let section: PronotePortalSection
    var body: some View {
        NavigationLink { PronoteSectionView(section: section) } label: {
            AtelierCard {
                HStack(spacing: 14) {
                    Image(systemName: section.symbol).font(.title2).foregroundStyle(Atelier.blue).frame(width: 32).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(section.title).font(.headline).foregroundStyle(CadenceColors.ink)
                        Text(section.subtitle).font(.subheadline).foregroundStyle(CadenceColors.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CadenceColors.secondary)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("pronote.shortcut." + section.rawValue)
    }
}

struct PronoteSectionView: View {
    let section: PronotePortalSection
    @EnvironmentObject private var store: AppStore
    @State private var periodID = ""
    @State private var weekDate = Date()
    @State private var showComposer = false
    private var profile: PronoteProfile? { store.pronoteProfile ?? store.pronotePortal.profile }
    private var periods: [PronotePeriod] {
        profile?.periods(for: section.rawValue).sorted { $0.startDate > $1.startDate } ?? []
    }
    private var effectivePeriodID: String? {
        if !periodID.isEmpty { return periodID }
        return section.usesPeriod ? profile?.currentPeriodID(for: section.rawValue) : nil
    }
    private var cacheKey: String { section.rawValue + (effectivePeriodID.map { ":" + $0 } ?? "") }
    private var value: SchoolJSON? {
        store.pronotePortal.sections[cacheKey] ?? (periodID.isEmpty ? store.pronotePortal.sections[section.rawValue] : nil)
    }
    private var loading: Bool { store.pronotePortalLoading.contains(cacheKey) || store.pronotePortalLoading.contains(section.rawValue) }
    private var error: String? { store.pronotePortalErrors[cacheKey] ?? store.pronotePortalErrors[section.rawValue] }
    private var canCompose: Bool { (store.pronoteProfile ?? store.pronotePortal.profile)?.capabilities.contains("compose") == true }

    var body: some View {
        AtelierPage(lazy: section != .grades) {
            if section.usesWeek { weekPicker }
            if section.usesPeriod && !periods.isEmpty { periodPicker }
            PronoteCacheStatus(date: store.pronotePortal.updatedAt[cacheKey] ?? (periodID.isEmpty ? store.pronotePortal.updatedAt[section.rawValue] : nil), loading: loading, error: error)
            if let value { sectionContent(value) }
            else if !loading {
                EmptyCard(title: "Aucun élément disponible", symbol: section.symbol,
                          description: "Cette rubrique n’a pas encore de données pour la période choisie. Vous pouvez l’actualiser en tirant vers le bas.")
            }
        }
        .navigationTitle(section.title).navigationBarTitleDisplayMode(.large)
        .task(id: cacheKey) { await reload() }
        .refreshable { await reload() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if section == .discussions && canCompose {
                    Button("Nouveau message", systemImage: "square.and.pencil") { showComposer = true }
                        .accessibilityIdentifier("pronote.compose.open")
                }
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading).accessibilityLabel("Actualiser " + section.title.lowercased())
            }
        }
        .sheet(isPresented: $showComposer) { NavigationStack { PronoteComposeView() } }
    }

    private var periodPicker: some View {
        HStack {
            Text("Période").font(.subheadline).foregroundStyle(CadenceColors.secondary)
            Spacer()
            Picker("Période", selection: $periodID) {
                Text(periods.first(where: { $0.id == profile?.currentPeriodID(for: section.rawValue) }).map { $0.name + " · actuelle" } ?? "Période actuelle").tag("")
                ForEach(periods) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu)
        }.padding(.horizontal, 4)
    }

    private var weekPicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { moveWeek(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Semaine précédente")
                .accessibilityIdentifier("pronote.week.previous")
                Spacer(minLength: 0)
                DatePicker("Choisir une semaine", selection: Binding(get: { weekDate }, set: selectWeek), displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden()
                    .environment(\.calendar, SchoolDateCodec.parisCalendar)
                    .environment(\.timeZone, SchoolDateCodec.parisCalendar.timeZone)
                    .accessibilityLabel("Choisir une date de la semaine")
                    .accessibilityIdentifier("pronote.week.date")
                Spacer(minLength: 0)
                Button { moveWeek(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Semaine suivante")
                .accessibilityIdentifier("pronote.week.next")
            }.tint(Atelier.blue).disabled(loading)
            Text(weekCaption).font(.subheadline).foregroundStyle(CadenceColors.secondary)
                .accessibilityIdentifier("pronote.week.range")
        }
    }

    private var weekStart: Date {
        SchoolDateCodec.parisCalendar.dateInterval(of: .weekOfYear, for: weekDate)?.start
            ?? SchoolDateCodec.parisCalendar.startOfDay(for: weekDate)
    }

    private var weekCaption: String {
        let end = SchoolDateCodec.parisCalendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "Du " + PronoteText.date(weekStart) + " au " + PronoteText.date(end)
    }

    private func moveWeek(_ offset: Int) {
        if let date = SchoolDateCodec.parisCalendar.date(byAdding: .day, value: offset * 7, to: weekDate) { selectWeek(date) }
    }

    private func selectWeek(_ date: Date) {
        weekDate = date
        let start = SchoolDateCodec.parisCalendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? SchoolDateCodec.parisCalendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = SchoolDateCodec.parisCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = SchoolDateCodec.parisCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        periodID = "week:" + formatter.string(from: start)
    }

    private func reload() async { await store.loadPronoteSection(section.rawValue, periodID: effectivePeriodID) }

    @ViewBuilder private func sectionContent(_ value: SchoolJSON) -> some View {
        switch section {
        case .grades: PronoteGradesPanel(value: value)
        case .evaluations: PronoteEvaluationsPanel(value: value)
        case .attendance: PronoteAttendancePanel(value: value)
        case .news: PronoteNewsPanel(value: value)
        case .discussions: PronoteDiscussionsPanel(value: value)
        case .menus: PronoteMenusPanel(value: value)
        case .contents: PronoteResourcesPanel(value: value)
        case .gradebook: PronoteGradebookPanel(value: value)
        case .account:
            AtelierCard { PronoteReadableFields(value: value, labels: PronoteText.accountLabels) }
        case .homepage:
            AtelierCard { PronoteAttachments(value: value["links"] ?? .array([])) }
        }
    }
}

private struct PronoteCacheStatus: View {
    let date: Date?
    let loading: Bool
    let error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading { HStack { ProgressView(); Text("Actualisation…").font(.subheadline) } }
            if let error { Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(CadenceColors.secondary) }
            if let date {
                Text("Mis à jour " + PronoteText.date(date, time: true))
                    .font(.caption).foregroundStyle(CadenceColors.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

private struct PronoteGradesPanel: View {
    let value: SchoolJSON
    @State private var selectedSubject = ""
    private var averages: [SchoolJSON] { value["subjectsAverages"]?.arrayValues ?? [] }
    private var grades: [SchoolJSON] {
        PronoteText.items(value, keys: ["grades"])
            .filter { selectedSubject.isEmpty || PronoteText.subject($0) == selectedSubject }
            .sorted { PronoteText.dateValue($0["date"]) > PronoteText.dateValue($1["date"]) }
    }
    private var subjectNames: [String] {
        Array(Set((averages + PronoteText.items(value, keys: ["grades"])).map { PronoteText.subject($0) }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var studentOverall: SchoolJSON? {
        PronoteText.validGrade(value["overallAverage"]) ? value["overallAverage"] : value["calculatedOverallAverage"]
    }
    private var classOverall: SchoolJSON? {
        PronoteText.validGrade(value["classAverage"]) ? value["classAverage"] : value["calculatedClassAverage"]
    }
    private var calculatedOverall: Bool { !PronoteText.validGrade(value["overallAverage"]) && PronoteText.validGrade(value["calculatedOverallAverage"]) }
    var body: some View {
        if PronoteText.validGrade(studentOverall) || PronoteText.validGrade(classOverall) {
            AtelierCard {
                CadenceSectionHeader(title: calculatedOverall ? "Moyenne indicative" : "Moyenne générale",
                                     subtitle: PronoteText.validGrade(studentOverall) ? (calculatedOverall ? "Calculée à partir de vos notes disponibles" : "Publiée par votre établissement") : nil)
                if PronoteText.validGrade(studentOverall) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(PronoteText.grade(studentOverall)).font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                            .foregroundStyle(Atelier.blue)
                        Text("/ 20").font(.title3).foregroundStyle(CadenceColors.secondary)
                        Spacer()
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("pronote.grades.overall")
                } else {
                    Text("Votre moyenne n’est pas disponible.").font(.subheadline).foregroundStyle(CadenceColors.secondary)
                }
                if PronoteText.validGrade(classOverall) {
                    PronoteValueRow(title: PronoteText.validGrade(value["classAverage"]) ? "Classe" : "Classe · indicative", value: PronoteText.grade(classOverall))
                }
                if calculatedOverall {
                    Text(PronoteText.text(value["calculationNotice"]) ?? "Estimation à partir des notes disponibles. Les matières ont le même poids ; le résultat peut différer du bulletin.")
                        .font(.caption).foregroundStyle(CadenceColors.secondary)
                }
            }
        } else if !grades.isEmpty {
            AtelierCard {
                Label("Moyennes non communiquées", systemImage: "info.circle").font(.subheadline.weight(.semibold))
                Text("Aucune moyenne n’est disponible pour cette période dans les données reçues. Vos notes restent consultables ci-dessous.")
                    .font(.subheadline).foregroundStyle(CadenceColors.secondary)
            }
        }
        if !subjectNames.isEmpty {
            HStack {
                Label("Matière", systemImage: "line.3.horizontal.decrease").font(.subheadline).foregroundStyle(CadenceColors.secondary)
                Spacer()
                Picker("Matière", selection: $selectedSubject) {
                    Text("Toutes les matières").tag("")
                    ForEach(subjectNames, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("pronote.grades.subject")
            }
        }
        if !averages.isEmpty {
            CadenceSectionHeader(title: "Moyennes par matière")
            ForEach(Array(averages.filter { selectedSubject.isEmpty || PronoteText.subject($0) == selectedSubject }.enumerated()), id: \.offset) { _, average in
                PronoteSubjectAverageCard(value: average)
            }
        }
        CadenceSectionHeader(title: "Évaluations", subtitle: "\(grades.count) résultat\(grades.count == 1 ? "" : "s")")
        ForEach(Array(grades.enumerated()), id: \.offset) { _, grade in PronoteGradeCard(value: grade) }
        if grades.isEmpty && averages.isEmpty {
            EmptyCard(title: "Pas encore de note", symbol: "chart.bar.xaxis", description: "Les résultats publiés par vos professeurs apparaîtront ici.")
        }
    }
}

private struct PronoteSubjectAverageCard: View {
    let value: SchoolJSON
    private var calculated: Bool { !PronoteText.validGrade(value["student"]) && PronoteText.validGrade(value["calculatedStudent"]) }
    private var average: SchoolJSON? { PronoteText.validGrade(value["student"]) ? value["student"] : value["calculatedStudent"] }
    private var classAverage: SchoolJSON? { PronoteText.validGrade(value["class_average"]) ? value["class_average"] : value["calculatedClassAverage"] }
    var body: some View {
        AtelierCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(PronoteText.subject(value)).font(.headline)
                Spacer(minLength: 4)
                Text(PronoteText.grade(average, outOf: calculated ? .number(20) : value["outOf"]))
                    .font(.title3.bold()).monospacedDigit().foregroundStyle(Atelier.blue).multilineTextAlignment(.trailing)
            }
            if calculated {
                Text("Moyenne indicative · calculée par Cadenza").font(.caption).foregroundStyle(CadenceColors.secondary)
            } else if !PronoteText.validGrade(average) {
                Text("Moyenne non communiquée").font(.caption).foregroundStyle(CadenceColors.secondary)
            }
            if PronoteText.validGrade(classAverage) {
                PronoteValueRow(title: PronoteText.validGrade(value["class_average"]) ? "Classe" : "Classe · indicative", value: PronoteText.grade(classAverage, outOf: PronoteText.validGrade(value["class_average"]) ? value["outOf"] : .number(20)))
            }
        }
    }
}

private struct PronoteGradeCard: View {
    let value: SchoolJSON
    var body: some View {
        AtelierCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(PronoteText.subject(value)).font(.headline)
                    if let date = value["date"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
                }
                Spacer(minLength: 8)
                Text(PronoteText.grade(value["value"], outOf: value["outOf"]))
                    .font(.title3.bold()).foregroundStyle(Atelier.blue).multilineTextAlignment(.trailing)
            }
            if let comment = PronoteText.text(value["comment"]), !comment.isEmpty { Text(comment).font(.subheadline) }
            if let comment = PronoteText.text(value["commentaireSurNote"]), !comment.isEmpty { Text(comment).font(.subheadline).foregroundStyle(CadenceColors.secondary) }
            if let coefficient = value["coefficient"]?.numberValue { Text("Coefficient " + PronoteText.number(coefficient)).font(.caption).foregroundStyle(CadenceColors.secondary) }
            if let average = value["average"] { PronoteValueRow(title: "Moyenne de la classe", value: PronoteText.grade(average, outOf: value["outOf"])) }
            if let file = value["subjectFile"] { PronoteAttachments(value: file) }
            if let file = value["correctionFile"] { PronoteAttachments(value: file) }
        }
    }
}

private struct PronoteEvaluationsPanel: View {
    let value: SchoolJSON
    private var items: [SchoolJSON] { PronoteText.items(value, keys: ["evaluations", "items"]) }
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            AtelierCard {
                CadenceSectionHeader(title: PronoteText.text(item["name"]) ?? PronoteText.subject(item), subtitle: PronoteText.subject(item))
                if let date = item["date"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
                if let text = PronoteText.text(item["description"]), !text.isEmpty { Text(text).font(.subheadline) }
                let levels = item["levels"]?.arrayValues ?? []
                ForEach(Array((item["skills"]?.arrayValues ?? []).enumerated()), id: \.offset) { _, skill in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(PronoteText.text(skill["itemName"]) ?? PronoteText.text(skill["domainName"]) ?? "Compétence").font(.subheadline.weight(.medium))
                        if let level = skill["level"]?.integerValue, levels.indices.contains(level), let label = PronoteText.text(levels[level]) {
                            Text(label).font(.caption).foregroundStyle(Atelier.blue)
                        } else if let label = PronoteText.text(skill["abbreviation"]) {
                            Text(label).font(.caption).foregroundStyle(Atelier.blue)
                        }
                    }
                }
            }
        }
        if items.isEmpty { EmptyCard(title: "Aucune compétence publiée", symbol: "checkmark.seal", description: "Les évaluations de cette période apparaîtront ici.") }
    }
}

private struct PronoteAttendancePanel: View {
    let value: SchoolJSON
    private let groups = [("absences", "Absences"), ("delays", "Retards"), ("observations", "Observations"), ("punishments", "Punitions"), ("precautionaryMeasures", "Mesures conservatoires")]
    private var absences: [SchoolJSON] { value["absences"]?.arrayValues ?? [] }
    private var delays: [SchoolJSON] { value["delays"]?.arrayValues ?? [] }
    private var pending: Int {
        (absences + delays).filter { $0["administrativelyFixed"]?.boolValue == false }.count
    }
    var body: some View {
        if !absences.isEmpty || !delays.isEmpty {
            AtelierCard {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    summary("Absence" + (absences.count == 1 ? "" : "s"), count: absences.count)
                    Rectangle().fill(CadenceColors.secondary.opacity(0.2)).frame(width: 1, height: 48).accessibilityHidden(true)
                    summary("Retard" + (delays.count == 1 ? "" : "s"), count: delays.count)
                }
                if pending > 0 {
                    Label("\(pending) événement\(pending == 1 ? "" : "s") à régulariser", systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.orange)
                } else if (absences + delays).allSatisfy({ $0["administrativelyFixed"]?.boolValue == true }) {
                    Label("Tout est régularisé", systemImage: "checkmark.shield")
                        .font(.subheadline).foregroundStyle(CadenceColors.positive)
                }
            }.accessibilityIdentifier("pronote.attendance.summary")
        }
        ForEach(groups, id: \.0) { key, title in
            let items = (value[key]?.arrayValues ?? []).sorted {
                PronoteText.dateValue($0["startDate"] ?? $0["date"] ?? $0["dateGiven"]) >
                PronoteText.dateValue($1["startDate"] ?? $1["date"] ?? $1["dateGiven"])
            }
            if !items.isEmpty {
                CadenceSectionHeader(title: title, subtitle: "\(items.count) événement\(items.count == 1 ? "" : "s")")
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    PronoteAttendanceCard(value: item, category: key)
                }
            }
        }
        if groups.allSatisfy({ value[$0.0]?.arrayValues?.isEmpty != false }) {
            EmptyCard(title: "Aucun élément de vie scolaire", symbol: "checkmark.circle", description: "Aucune absence, aucun retard ni aucune observation pour cette période.")
        }
    }
    private func summary(_ title: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(count)").font(.largeTitle.bold()).monospacedDigit().foregroundStyle(CadenceColors.ink)
            Text(title).font(.subheadline).foregroundStyle(CadenceColors.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PronoteAttendanceCard: View {
    let value: SchoolJSON
    let category: String
    private var isAbsence: Bool { category == "absences" }
    private var isDelay: Bool { category == "delays" }
    private var title: String {
        if isAbsence { return "Absence" }
        if isDelay { return "Retard" }
        return PronoteText.text(value["title"]) ?? PronoteText.text(value["name"]) ?? "Événement de vie scolaire"
    }
    private var reason: String? { PronoteText.text(value["reason"]) ?? PronoteText.text(value["reasons"]) }
    private var duration: String? {
        if isAbsence {
            if let hours = value["hoursMissed"]?.numberValue, hours >= 0 {
                let minutes = max(0, value["minutesMissed"]?.numberValue ?? 0)
                if hours > 0 || minutes > 0 { return Atelier.duration(hours * 3600 + minutes * 60) + " de cours manqués" }
            }
        }
        if let minutes = (isDelay ? value["minutes"] : value["durationMinutes"])?.numberValue, minutes > 0 {
            return Atelier.duration(minutes * 60)
        }
        return nil
    }
    var body: some View {
        AtelierCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAbsence ? "calendar.badge.minus" : isDelay ? "clock.badge.exclamationmark" : "text.bubble")
                    .font(.title2).foregroundStyle(Atelier.blue).frame(width: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(PronoteText.attendanceDates(value)).font(.subheadline).foregroundStyle(CadenceColors.secondary)
                    if let duration { Text(duration).font(.subheadline.weight(.semibold)).foregroundStyle(Atelier.blue) }
                }
                Spacer(minLength: 0)
            }
            if let reason, !reason.isEmpty { Text(reason).font(.body).textSelection(.enabled) }
            if let subject = value["subject"] { Label(PronoteText.subject(.object(["subject": subject])), systemImage: "book").font(.caption).foregroundStyle(CadenceColors.secondary) }
            if isAbsence || isDelay {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { statusBadges }
                    VStack(alignment: .leading, spacing: 8) { statusBadges }
                }
                if let justification = PronoteText.text(value["justification"]), !justification.isEmpty {
                    Text(justification).font(.subheadline).foregroundStyle(CadenceColors.secondary)
                }
            } else {
                PronoteReadableFields(value: value, labels: ["workToDo": "Travail demandé", "circumstances": "Circonstances", "comments": "Commentaire", "giver": "Décidé par"])
                PronoteAttachments(value: value["workToDoDocuments"] ?? .array([]))
                PronoteAttachments(value: value["circumstancesDocuments"] ?? .array([]))
            }
        }
    }
    @ViewBuilder private var statusBadges: some View {
        if let justified = value["justified"]?.boolValue {
            Label(justified ? (isAbsence ? "Justifiée" : "Justifié") : "À justifier", systemImage: justified ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption.weight(.semibold)).foregroundStyle(justified ? CadenceColors.positive : .orange)
        }
        if let regularized = value["administrativelyFixed"]?.boolValue {
            StatusBadge(title: regularized ? (isAbsence ? "Régularisée" : "Régularisé") : "À régulariser", color: regularized ? CadenceColors.secondary : .orange)
        }
    }
}

private struct PronoteNewsPanel: View {
    let value: SchoolJSON
    private var items: [SchoolJSON] { PronoteText.items(value, keys: ["items", "news"]) }
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            NavigationLink { PronoteNewsDetail(value: item) } label: {
                AtelierCard {
                    HStack {
                        Text(PronoteText.text(item["title"]) ?? "Information de l’établissement").font(.headline)
                        Spacer(minLength: 4)
                        if item["read"]?.boolValue == false { Circle().fill(Atelier.blue).frame(width: 8, height: 8).accessibilityLabel("Non lu") }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(CadenceColors.secondary)
                    }
                    if let author = PronoteText.text(item["author"]) { Text(author).font(.subheadline).foregroundStyle(CadenceColors.secondary) }
                    if let date = item["creationDate"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
                    if item["needToAcknowledge"]?.boolValue == true {
                        Label(item["acknowledged"]?.boolValue == true ? "Réception confirmée" : "Accusé de réception demandé", systemImage: "checkmark.message")
                            .font(.caption).foregroundStyle(Atelier.blue)
                    }
                }
            }.buttonStyle(.plain).accessibilityIdentifier("pronote.news." + (item["id"]?.stringValue ?? "unknown"))
        }
        if items.isEmpty { EmptyCard(title: "Aucune information", symbol: "bell", description: "Les messages de votre établissement apparaîtront ici.") }
    }
}

private struct PronoteNewsDetail: View {
    let value: SchoolJSON
    @EnvironmentObject private var store: AppStore
    @State private var confirming = false
    @State private var sending = false
    @State private var acknowledged = false
    @State private var failed = false
    private var id: String? { value["id"]?.stringValue }
    private var cacheKey: String { "news:" + (id ?? "") }
    private var listed: SchoolJSON? {
        guard let id, let list = store.pronotePortal.sections["news"] else { return nil }
        return PronoteText.items(list, keys: ["items", "news"]).first { $0["id"]?.stringValue == id }
    }
    private var current: SchoolJSON { store.pronotePortal.sections[cacheKey] ?? listed ?? value }
    private var loading: Bool { store.pronotePortalLoading.contains(cacheKey) }
    private var needsDetails: Bool { requiresDetails(current) }
    private var shouldFetchDetails: Bool { requiresDetails(listed ?? value) }
    private var articleText: String? {
        for entry in [current["content"], current["question"]?["content"]] {
            if let text = PronoteText.text(entry), !text.isEmpty { return text }
        }
        return nil
    }
    var body: some View {
        AtelierPage(lazy: true) {
            PronoteCacheStatus(date: store.pronotePortal.updatedAt[cacheKey], loading: loading, error: store.pronotePortalErrors[cacheKey])
            AtelierCard {
                CadenceSectionHeader(title: PronoteText.text(current["title"]) ?? "Information", subtitle: PronoteText.text(current["author"]))
                if let date = current["creationDate"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
                if let articleText {
                    Text(articleText).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("pronote.news.content")
                }
                if needsDetails {
                    Label(loading ? "Chargement de l’information…" : "Le texte de cette information n’a pas encore été téléchargé.", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline).foregroundStyle(CadenceColors.secondary)
                } else {
                    PronoteAttachments(value: current["attachments"] ?? .array([]))
                    if articleText == nil && current["questions"]?.arrayValues?.isEmpty != false && current["attachments"]?.links.isEmpty != false {
                        Text("Cette information ne contient pas de texte.").font(.subheadline).foregroundStyle(CadenceColors.secondary)
                    }
                }
            }
            if needsDetails && !loading, let id {
                SecondaryAction(title: "Réessayer le chargement", symbol: "arrow.clockwise") { Task { await store.loadPronoteNews(id) } }
            }
            ForEach(Array((needsDetails ? [] : current["questions"]?.arrayValues ?? []).enumerated()), id: \.offset) { _, question in
                AtelierCard {
                    PronoteReadableFields(value: question, labels: ["title": "Question", "content": "Détail", "textInputAnswer": "Votre réponse"])
                    PronoteAttachments(value: question["attachments"] ?? .array([]))
                }
            }
            if !needsDetails && current["is"]?.stringValue == "survey" {
                Text("Ce sondage est consultable ici. Les réponses se font depuis PRONOTE.").font(.caption).foregroundStyle(CadenceColors.secondary)
            }
            if !needsDetails && current["needToAcknowledge"]?.boolValue == true {
                if acknowledged || current["acknowledged"]?.boolValue == true {
                    Label("Réception confirmée", systemImage: "checkmark.circle.fill").foregroundStyle(CadenceColors.positive)
                } else if id != nil {
                    ProminentAction(title: sending ? "Envoi…" : "Accuser réception", symbol: "checkmark.message") { confirming = true }
                        .disabled(sending || loading)
                }
            }
            if failed { Text("La confirmation n’a pas pu être envoyée. Réessayez lorsque la connexion est disponible.").font(.caption).foregroundStyle(CadenceColors.secondary) }
        }
        .navigationTitle("Information").navigationBarTitleDisplayMode(.inline)
        .task(id: id) { if shouldFetchDetails, let id { await store.loadPronoteNews(id) } }
        .refreshable { if let id { await store.loadPronoteNews(id) } }
        .alert("Confirmer la réception ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("Accuser réception") { Task { await acknowledge() } }
        } message: { Text("Un accusé de réception sera envoyé à votre établissement dans PRONOTE.") }
    }
    private func requiresDetails(_ value: SchoolJSON) -> Bool {
        if let required = value["detailsRequired"]?.boolValue { return required }
        if let required = value["detailRequired"]?.boolValue { return required }
        return value["content"] == nil && value["question"] == nil && value["questions"] == nil && value["attachments"] == nil
    }
    private func acknowledge() async {
        guard let id, !sending, !needsDetails, !loading else { return }
        sending = true
        acknowledged = await store.acknowledgePronoteNews(id)
        failed = !acknowledged; sending = false
    }
}

private struct PronoteDiscussionsPanel: View {
    let value: SchoolJSON
    private var items: [SchoolJSON] { PronoteText.items(value, keys: ["items", "discussions"]) }
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            if let id = item["participantsMessageID"]?.stringValue {
                NavigationLink { PronoteThreadView(threadID: id, title: PronoteText.text(item["subject"]) ?? "Discussion", closed: item["closed"]?.boolValue == true) } label: {
                    AtelierCard {
                        HStack {
                            Text(PronoteText.text(item["subject"]) ?? "Discussion").font(.headline)
                            Spacer(minLength: 4)
                            if let unread = item["numberOfMessagesUnread"]?.integerValue, unread > 0 { Text("\(unread)").font(.caption.bold()).foregroundStyle(Atelier.blue) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(CadenceColors.secondary)
                        }
                        if let name = PronoteText.text(item["creator"]) ?? PronoteText.text(item["recipientName"]) { Text(name).font(.subheadline).foregroundStyle(CadenceColors.secondary) }
                        if let date = item["date"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("pronote.discussion." + id)
            }
        }
        if items.isEmpty { EmptyCard(title: "Aucune discussion", symbol: "bubble.left.and.bubble.right", description: "Vos échanges avec l’établissement apparaîtront ici.") }
    }
}

private struct PronoteThreadView: View {
    let threadID: String
    let title: String
    let closed: Bool
    @EnvironmentObject private var store: AppStore
    @State private var reply = ""
    @State private var confirming = false
    @State private var sending = false
    @State private var failed = false
    private var cacheKey: String { "discussion:" + threadID }
    private var value: SchoolJSON? { store.pronotePortal.sections[cacheKey] }
    private var messages: [SchoolJSON] { PronoteText.items(value ?? .null, keys: ["sents", "messages"]).sorted { PronoteText.dateValue($0["creationDate"]) < PronoteText.dateValue($1["creationDate"]) } }
    private var canReply: Bool { !closed && value?["sendAction"]?.integerValue != nil }
    var body: some View {
        AtelierPage(lazy: true) {
            PronoteCacheStatus(date: store.pronotePortal.updatedAt[cacheKey], loading: store.pronotePortalLoading.contains(cacheKey), error: store.pronotePortalErrors[cacheKey])
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                AtelierCard {
                    Text(PronoteText.text(message["author"]?["name"]) ?? store.pronoteProfile?.displayName ?? "Vous").font(.headline)
                    if let date = message["creationDate"] { Text(PronoteText.date(date, time: true)).font(.caption).foregroundStyle(CadenceColors.secondary) }
                    if let text = PronoteText.text(message["content"]) { Text(text).textSelection(.enabled) }
                    PronoteAttachments(value: message["files"] ?? .array([]))
                }
            }
            if canReply {
                AtelierCard {
                    Text("Votre réponse").font(.headline)
                    TextEditor(text: $reply).frame(minHeight: 130).scrollContentBackground(.hidden)
                        .accessibilityLabel("Texte de votre réponse").accessibilityIdentifier("pronote.thread.reply")
                    ProminentAction(title: sending ? "Envoi…" : "Envoyer la réponse", symbol: "paperplane") { confirming = true }
                        .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
            } else if value != nil {
                Text(closed ? "Cette discussion est clôturée." : "Les réponses ne sont pas disponibles pour cette discussion.")
                    .font(.caption).foregroundStyle(CadenceColors.secondary)
            }
            if failed { Text("Votre réponse n’a pas été envoyée. Le texte est conservé pour réessayer.").font(.caption).foregroundStyle(CadenceColors.secondary) }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task { await store.loadPronoteThread(threadID) }
        .refreshable { await store.loadPronoteThread(threadID) }
        .alert("Envoyer cette réponse ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("Envoyer") { Task { await send() } }
        } message: { Text("Votre message sera envoyé dans cette discussion PRONOTE.") }
    }
    private func send() async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sending, !text.isEmpty, canReply else { return }
        sending = true
        let success = await store.replyPronoteThread(threadID, text: text)
        if success { reply = "" }
        failed = !success; sending = false
    }
}

private struct PronoteComposeRecipient: Identifiable {
    let id: String
    let name: String
    let subjects: String?
}

private struct PronoteComposeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var search = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var confirming = false
    @State private var sending = false
    @State private var failed = false
    private var profile: PronoteProfile? { store.pronoteProfile ?? store.pronotePortal.profile }
    private var allowed: Bool { profile?.capabilities.contains("compose") == true }
    private var identity: String { [profile?.establishment, profile?.resourceID, profile?.displayName].compactMap { $0 }.joined(separator: "|") }
    private var recipients: [PronoteComposeRecipient] {
        let cache = store.pronotePortal.sections["recipients"]
        let values = cache?.arrayValues ?? cache?["recipients"]?.arrayValues ?? []
        var seen = Set<String>()
        return values.compactMap { value in
            guard value["kind"]?.integerValue == 3, let id = value["id"]?.stringValue, !id.isEmpty,
                  let name = PronoteText.text(value["name"]), !name.isEmpty, seen.insert(id).inserted else { return nil }
            return PronoteComposeRecipient(id: id, name: name, subjects: PronoteText.text(value["subjects"]))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var filteredRecipients: [PronoteComposeRecipient] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return recipients }
        return recipients.filter { $0.name.localizedStandardContains(search) || ($0.subjects?.localizedStandardContains(search) ?? false) }
    }
    private var selectedRecipients: [PronoteComposeRecipient] { recipients.filter { selectedIDs.contains($0.id) } }
    private var ready: Bool {
        allowed && !sending && !selectedIDs.isEmpty && selectedIDs.count <= 20 && selectedRecipients.count == selectedIDs.count &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && subject.utf16.count <= 200 &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 20_000
    }

    var body: some View {
        AtelierPage(lazy: true) {
            if allowed {
                recipientsCard
                messageCard
                if failed {
                    Label(store.pronotePortalErrors["compose"] ?? "Le message n’a pas pu être envoyé. Votre texte est conservé pour réessayer.", systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(CadenceColors.secondary)
                }
            } else {
                EmptyCard(title: "Création de message indisponible", symbol: "bubble.left", description: "Votre établissement ne permet pas de commencer une discussion avec ce compte.")
            }
        }
        .navigationTitle("Nouveau message").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }.disabled(sending).accessibilityIdentifier("pronote.compose.cancel")
            }
        }
        .interactiveDismissDisabled(sending)
        .task { await store.loadPronoteRecipients() }
        .refreshable { await store.loadPronoteRecipients() }
        .onChange(of: identity) { _, _ in selectedIDs = []; subject = ""; text = ""; confirming = false; failed = false }
        .alert("Envoyer ce message ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("Envoyer") { Task { await send() } }
        } message: {
            Text("À : " + selectedRecipients.map(\.name).joined(separator: ", ") + "\nObjet : " + subject.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private var recipientsCard: some View {
        AtelierCard {
            CadenceSectionHeader(title: "Destinataires", subtitle: selectedIDs.isEmpty ? "Choisissez un ou plusieurs enseignants" : "\(selectedIDs.count) enseignant\(selectedIDs.count > 1 ? "s" : "") sélectionné\(selectedIDs.count > 1 ? "s" : "")")
            TextField("Rechercher un enseignant", text: $search).autocorrectionDisabled()
            if store.pronotePortalLoading.contains("recipients") { ProgressView("Chargement des destinataires…") }
            if let error = store.pronotePortalErrors["recipients"] { Text(error).font(.caption).foregroundStyle(CadenceColors.secondary) }
            ForEach(filteredRecipients) { recipient in
                recipientButton(recipient)
            }
            if recipients.isEmpty && !store.pronotePortalLoading.contains("recipients") {
                Text("Aucun enseignant disponible. Actualisez les destinataires en tirant vers le bas.").font(.subheadline).foregroundStyle(CadenceColors.secondary)
            } else if filteredRecipients.isEmpty {
                Text("Aucun enseignant ne correspond à cette recherche.").font(.subheadline).foregroundStyle(CadenceColors.secondary)
            }
        }
    }

    private func recipientButton(_ recipient: PronoteComposeRecipient) -> some View {
        let selected = selectedIDs.contains(recipient.id)
        return Button {
            if selected { selectedIDs.remove(recipient.id) }
            else { selectedIDs.insert(recipient.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(Atelier.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipient.name).font(.subheadline.weight(.medium)).foregroundStyle(CadenceColors.ink)
                    if let subjects = recipient.subjects, !subjects.isEmpty { Text(subjects).font(.caption).foregroundStyle(CadenceColors.secondary) }
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(sending || (!selected && selectedIDs.count >= 20))
        .accessibilityValue(selected ? "Sélectionné" : "Non sélectionné")
        .accessibilityIdentifier("pronote.compose.recipient." + recipient.id)
    }

    private var messageCard: some View {
        AtelierCard {
            Text("Objet").font(.headline)
            TextField("Objet du message", text: $subject, axis: .vertical)
                .disabled(sending).accessibilityIdentifier("pronote.compose.subject")
            if subject.utf16.count > 200 { Text("L’objet doit contenir au maximum 200 caractères.").font(.caption).foregroundStyle(.orange) }
            Divider()
            Text("Message").font(.headline)
            TextEditor(text: $text).frame(minHeight: 180).scrollContentBackground(.hidden)
                .disabled(sending).accessibilityLabel("Texte du nouveau message")
                .accessibilityIdentifier("pronote.compose.text")
            if text.utf16.count > 20_000 { Text("Le message est trop long. Limitez-le à 20 000 caractères.").font(.caption).foregroundStyle(.orange) }
            ProminentAction(title: sending ? "Envoi…" : "Envoyer le message", symbol: "paperplane") { confirming = true }
                .disabled(!ready).accessibilityIdentifier("pronote.compose.send")
        }
    }

    private func send() async {
        guard ready else { return }
        sending = true; failed = false
        let success = await store.composePronoteMessage(recipientIDs: selectedRecipients.map(\.id), subject: subject, text: text)
        sending = false
        if success { dismiss() }
        else { failed = true }
    }
}

private struct PronoteMenusPanel: View {
    let value: SchoolJSON
    private var days: [SchoolJSON] { PronoteText.items(value, keys: ["days", "menus"]) }
    var body: some View {
        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
            AtelierCard {
                if let date = day["date"] { CadenceSectionHeader(title: PronoteText.date(date)) }
                ForEach([("lunch", "Déjeuner"), ("dinner", "Dîner")], id: \.0) { key, title in
                    if let meal = day[key], meal.objectValues != nil {
                        Text(PronoteText.text(meal["name"]) ?? title).font(.headline).foregroundStyle(Atelier.blue)
                        PronoteReadableFields(value: meal, labels: PronoteText.mealLabels)
                    }
                }
            }
        }
        if days.isEmpty { EmptyCard(title: "Aucun menu disponible", symbol: "fork.knife", description: "Les menus publiés par votre établissement apparaîtront ici.") }
    }
}

private struct PronoteResourcesPanel: View {
    let value: SchoolJSON
    var body: some View {
        let groups = Dictionary(grouping: PronoteText.items(value, keys: ["resources", "items", "contents"]), by: PronoteText.subject)
        let subjects = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if !subjects.isEmpty {
            CadenceSectionHeader(title: "Vos matières", subtitle: value["yearStart"].map { "Depuis le " + PronoteText.date($0) } ?? "Cours disponibles sur cet iPhone")
        }
        ForEach(subjects, id: \.self) { subject in
            let lessons = groups[subject] ?? []
            NavigationLink { PronoteSubjectContentsView(subject: subject, lessons: lessons) } label: {
                AtelierCard {
                    HStack(spacing: 14) {
                        Image(systemName: "books.vertical.fill").font(.title2).foregroundStyle(Atelier.blue)
                            .frame(width: 44, height: 44).background(Atelier.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(subject).font(.headline).foregroundStyle(CadenceColors.ink)
                            Text("\(lessons.count) cours")
                                .font(.subheadline).foregroundStyle(CadenceColors.secondary)
                            if let names = PronoteText.teacherNames(lessons), !names.isEmpty {
                                Text(names).font(.caption).foregroundStyle(CadenceColors.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CadenceColors.secondary)
                    }
                }
            }.buttonStyle(.plain).accessibilityIdentifier("pronote.contents.subject." + subject)
        }
        if subjects.isEmpty { EmptyCard(title: "Aucun contenu publié", symbol: "books.vertical", description: "Les leçons et les documents partagés par vos professeurs cette année apparaîtront ici.") }
    }
}

private struct PronoteSubjectContentsView: View {
    let subject: String
    let lessons: [SchoolJSON]
    private var items: [SchoolJSON] {
        lessons.sorted {
            let left = $0["startDate"]?.stringValue ?? "", right = $1["startDate"]?.stringValue ?? ""
            if left == right { return ($0["id"]?.stringValue ?? "") < ($1["id"]?.stringValue ?? "") }
            return left < right
        }
    }
    var body: some View {
        AtelierPage(lazy: true) {
            CadenceSectionHeader(title: "Cahier de textes", subtitle: "Du premier cours au plus récent.")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in lesson(item) }
        }
        .navigationTitle(subject).navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("pronote.contents.subject.detail")
    }
    @ViewBuilder private func lesson(_ item: SchoolJSON) -> some View {
            if let id = item["id"]?.stringValue, item["subject"] != nil {
                NavigationLink { PronoteResourceView(resourceID: id, seed: item) } label: {
                    AtelierCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let date = item["startDate"] { Text(PronoteText.date(date)).font(.headline).foregroundStyle(CadenceColors.ink) }
                                if let names = PronoteText.text(item["teachers"]), !names.isEmpty { Text(names).font(.caption).foregroundStyle(CadenceColors.secondary) }
                                let contents = item["contents"]?.arrayValues ?? []
                                if let first = contents.first, let title = PronoteText.text(first["title"]), !title.isEmpty {
                                    Text(title).font(.subheadline).foregroundStyle(CadenceColors.ink).lineLimit(2)
                                } else {
                                    Text("Consulter la leçon et les documents").font(.subheadline).foregroundStyle(CadenceColors.secondary)
                                }
                                if item["haveAssignment"]?.boolValue == true {
                                    Label("Travail à faire associé", systemImage: "checklist").font(.caption).foregroundStyle(Atelier.blue)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(CadenceColors.secondary)
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("pronote.resource." + id)
            } else { PronoteLessonContentCard(value: item) }
    }
}

private struct PronoteResourceView: View {
    let resourceID: String
    let seed: SchoolJSON
    @EnvironmentObject private var store: AppStore
    private var cacheKey: String { "resource:" + resourceID }
    private var value: SchoolJSON { store.pronotePortal.sections[cacheKey] ?? seed }
    private var loading: Bool { store.pronotePortalLoading.contains(cacheKey) }
    private var hasLoaded: Bool { store.pronotePortal.sections[cacheKey] != nil }
    var body: some View {
        AtelierPage(lazy: true) {
            PronoteCacheStatus(date: store.pronotePortal.updatedAt[cacheKey], loading: loading, error: store.pronotePortalErrors[cacheKey])
            AtelierCard {
                CadenceSectionHeader(title: PronoteText.subject(value), subtitle: PronoteText.text(value["teachers"]))
                if let date = value["startDate"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
            }
            ForEach(Array((value["contents"]?.arrayValues ?? []).enumerated()), id: \.offset) { _, content in PronoteLessonContentCard(value: content) }
            if hasLoaded && !loading && value["contents"]?.arrayValues?.isEmpty != false {
                EmptyCard(title: "Aucun détail de leçon", symbol: "doc.text", description: "Votre professeur n’a pas encore partagé de contenu pour ce cours.")
            } else if !hasLoaded && !loading {
                SecondaryAction(title: "Réessayer le chargement", symbol: "arrow.clockwise") { Task { await store.loadPronoteResource(resourceID) } }
            }
        }
        .navigationTitle("Contenu du cours").navigationBarTitleDisplayMode(.inline)
        .task { await store.loadPronoteResource(resourceID) }
        .refreshable { await store.loadPronoteResource(resourceID) }
    }
}

private struct PronoteLessonContentCard: View {
    let value: SchoolJSON
    var body: some View {
        AtelierCard {
            CadenceSectionHeader(title: PronoteText.text(value["title"]) ?? "Contenu du cours", subtitle: PronoteText.text(value["categoryText"]))
            if let description = PronoteText.text(value["description"]), !description.isEmpty {
                Text(description).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            PronoteAttachments(value: value["files"] ?? .array([]))
            if let themes = PronoteText.text(value["themes"]), !themes.isEmpty { Label(themes, systemImage: "tag").font(.caption).foregroundStyle(CadenceColors.secondary) }
        }
    }
}

private struct PronoteGradebookPanel: View {
    let value: SchoolJSON
    var body: some View {
        if let message = PronoteText.text(value["message"]), !message.isEmpty { AtelierCard { Text(message) } }
        let assessments = value["overallAssessments"]?.arrayValues ?? []
        if !assessments.isEmpty {
            AtelierCard {
                CadenceSectionHeader(title: "Appréciation générale")
                ForEach(Array(assessments.enumerated()), id: \.offset) { _, item in
                    if let name = PronoteText.text(item["name"]) { Text(name).font(.headline) }
                    if let text = PronoteText.text(item["value"]) { Text(text).font(.subheadline).textSelection(.enabled) }
                }
            }
        }
        ForEach(Array((value["subjects"]?.arrayValues ?? []).enumerated()), id: \.offset) { _, subject in
            AtelierCard {
                CadenceSectionHeader(title: PronoteText.subject(subject), subtitle: PronoteText.text(subject["teachers"]))
                if let average = subject["averages"]?["student"] { PronoteValueRow(title: "Votre moyenne", value: PronoteText.grade(average)) }
                if let average = subject["averages"]?["classOverall"] { PronoteValueRow(title: "Classe", value: PronoteText.grade(average)) }
                ForEach(Array((subject["assessments"]?.arrayValues ?? []).enumerated()), id: \.offset) { _, item in
                    if let text = PronoteText.text(item), !text.isEmpty { Text(text).font(.subheadline).textSelection(.enabled) }
                }
            }
        }
        PronoteAttachments(value: value["url"] ?? .null)
    }
}

private struct PronoteValueRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(CadenceColors.secondary)
            Spacer(minLength: 4)
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}

private struct PronoteAttachments: View {
    let value: SchoolJSON
    private var links: [SchoolResourceLink] {
        var seen = Set<String>()
        return value.links.filter {
            $0.url.scheme?.lowercased() == "https" && $0.url.user == nil && $0.url.password == nil && seen.insert($0.id).inserted
        }
    }
    var body: some View {
        ForEach(links) { link in
            Link(destination: link.url) {
                Label(PronoteText.plain(link.title), systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
            }.tint(Atelier.blue)
        }
    }
}

/// An allowlist makes an unfamiliar server field harmless: IDs, auth tokens and protocol objects are never rendered.
private struct PronoteReadableFields: View {
    let value: SchoolJSON
    var labels: [String: String] = PronoteText.schoolLabels
    private var fields: [(String, String)] { PronoteText.fields(value, labels: labels) }
    var body: some View {
        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
            VStack(alignment: .leading, spacing: 5) {
                Text(field.0).font(.caption).foregroundStyle(CadenceColors.secondary)
                Text(field.1).font(.subheadline).textSelection(.enabled)
            }
        }
    }
}

private enum PronoteText {
    static let accountLabels = ["address": "Adresse", "postalCode": "Code postal", "city": "Ville", "province": "Région", "country": "Pays", "email": "Adresse e-mail", "phone": "Téléphone"]
    static let mealLabels = ["entry": "Entrée", "main": "Plat", "side": "Accompagnement", "drink": "Boisson", "fromage": "Fromage", "dessert": "Dessert"]
    static let schoolLabels = ["title": "Intitulé", "name": "Intitulé", "date": "Date", "startDate": "Début", "endDate": "Fin", "dateGiven": "Date",
        "subject": "Matière", "reason": "Motif", "reasons": "Motifs", "justified": "Justifié", "justification": "Justification",
        "daysMissed": "Jours d’absence", "hoursMissed": "Heures d’absence", "minutesMissed": "Minutes d’absence", "minutes": "Minutes de retard",
        "durationMinutes": "Durée en minutes", "workToDo": "Travail demandé", "circumstances": "Circonstances", "comments": "Commentaire", "giver": "Décidé par",
        "exclusion": "Exclusion", "administrativelyFixed": "Régularisé", "description": "Détail"]

    static func items(_ value: SchoolJSON, keys: [String]) -> [SchoolJSON] {
        if let array = value.arrayValues { return array }
        for key in keys { if let array = value[key]?.arrayValues { return array } }
        return []
    }
    static func subject(_ value: SchoolJSON) -> String {
        text(value["subject"]?["name"]) ?? text(value["subject"]) ?? "Matière"
    }
    static func teacherNames(_ items: [SchoolJSON]) -> String? {
        var names = Set<String>()
        for item in items {
            for teacher in item["teachers"]?.arrayValues ?? [] {
                if let name = text(teacher), !name.isEmpty { names.insert(name) }
            }
        }
        return names.isEmpty ? nil : names.sorted().joined(separator: ", ")
    }
    static func text(_ value: SchoolJSON?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let text): return plain(text)
        case .number(let n): return n.isFinite ? number(n) : nil
        case .bool(let value): return value ? "Oui" : "Non"
        case .array(let items):
            let texts = items.prefix(100).compactMap { text($0) }.filter { !$0.isEmpty }
            return texts.isEmpty ? nil : texts.joined(separator: ", ")
        case .object:
            for key in ["name", "title", "label"] { if let text = text(value[key]), !text.isEmpty { return text } }
            return nil
        case .null: return nil
        }
    }
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...2)))
    }
    static func grade(_ value: SchoolJSON?, outOf: SchoolJSON? = nil) -> String {
        guard let value else { return "—" }
        let max = outOf?["points"]?.numberValue ?? outOf?.numberValue
        if let n = value.numberValue {
            return number(n) + (max.map { $0.isFinite && $0 > 0 ? " / " + number($0) : "" } ?? "")
        }
        let kind = value["kind"]?.integerValue ?? -1
        if kind != 0 {
            switch kind {
            case 1: return "Absent"
            case 2: return "Dispensé"
            case 3: return "Non noté"
            case 4: return "Inapte"
            case 5: return "Non rendu"
            case 6: return "Absent · 0"
            case 7: return "Non rendu · 0"
            case 8: return "Félicitations"
            default: return "—"
            }
        }
        guard let points = value["points"]?.numberValue, points.isFinite else { return "—" }
        return number(points) + (max.map { $0.isFinite && $0 > 0 ? " / " + number($0) : "" } ?? "")
    }
    static func validGrade(_ value: SchoolJSON?) -> Bool {
        guard let value else { return false }
        if let number = value.numberValue { return number.isFinite }
        return value["kind"]?.integerValue == 0 && value["points"]?.numberValue?.isFinite == true
    }
    static func attendanceDates(_ value: SchoolJSON) -> String {
        let first = value["startDate"] ?? value["date"] ?? value["dateGiven"]
        guard let first, let raw = first.stringValue, let start = SchoolDateCodec.date(from: raw) else { return "Date non précisée" }
        guard let endRaw = value["endDate"]?.stringValue, let end = SchoolDateCodec.date(from: endRaw), end > start else {
            return date(start, time: true)
        }
        if SchoolDateCodec.parisCalendar.isDate(start, inSameDayAs: end) {
            let time = DateFormatter()
            time.locale = Locale(identifier: "fr_FR"); time.timeZone = SchoolDateCodec.parisCalendar.timeZone
            time.dateFormat = "HH:mm"
            return date(start) + " · " + time.string(from: start) + "–" + time.string(from: end)
        }
        return "Du " + date(start, time: true) + "\nau " + date(end, time: true)
    }
    static func dateValue(_ value: SchoolJSON?) -> Date { value?.stringValue.flatMap { SchoolDateCodec.date(from: $0) } ?? .distantPast }
    static func date(_ value: SchoolJSON, time: Bool = false) -> String {
        guard let raw = value.stringValue, let parsed = SchoolDateCodec.date(from: raw) else { return "Date non précisée" }
        return date(parsed, time: time)
    }
    static func date(_ value: Date, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR"); formatter.timeZone = SchoolDateCodec.parisCalendar.timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = time ? .short : .none
        return formatter.string(from: value)
    }
    static func fields(_ value: SchoolJSON, labels: [String: String]) -> [(String, String)] {
        guard let object = value.objectValues else { return [] }
        return object.keys.sorted().compactMap { key in
            guard let label = labels[key], let value = object[key] else { return nil }
            let display = ["date", "startDate", "endDate", "dateGiven"].contains(key) ? date(value, time: true) : text(value)
            guard let display, !display.isEmpty else { return nil }
            return (label, display)
        }
    }
    /// Convert published HTML to plain text without loading web content or executing markup.
    static func plain(_ input: String) -> String {
        SchoolRichText.plain(input)
    }
}
