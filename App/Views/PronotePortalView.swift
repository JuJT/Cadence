import SwiftUI
import CadenceCore

private enum PronotePortalSection: String, CaseIterable, Identifiable {
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

private struct PronoteSectionView: View {
    let section: PronotePortalSection
    @EnvironmentObject private var store: AppStore
    @State private var periodID = ""
    private var periods: [PronotePeriod] {
        (store.pronoteProfile ?? store.pronotePortal.profile)?.periods.sorted { $0.startDate > $1.startDate } ?? []
    }
    private var cacheKey: String { section.rawValue + (periodID.isEmpty ? "" : ":" + periodID) }
    private var value: SchoolJSON? { store.pronotePortal.sections[cacheKey] }
    private var loading: Bool { store.pronotePortalLoading.contains(cacheKey) || store.pronotePortalLoading.contains(section.rawValue) }
    private var error: String? { store.pronotePortalErrors[cacheKey] ?? store.pronotePortalErrors[section.rawValue] }

    var body: some View {
        AtelierPage(lazy: true) {
            if section.usesPeriod && !periods.isEmpty { periodPicker }
            PronoteCacheStatus(date: store.pronotePortal.updatedAt[cacheKey], loading: loading, error: error)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading).accessibilityLabel("Actualiser " + section.title.lowercased())
            }
        }
    }

    private var periodPicker: some View {
        HStack {
            Text("Période").font(.subheadline).foregroundStyle(CadenceColors.secondary)
            Spacer()
            Picker("Période", selection: $periodID) {
                Text("Période actuelle").tag("")
                ForEach(periods) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu)
        }.padding(.horizontal, 4)
    }

    private func reload() async { await store.loadPronoteSection(section.rawValue, periodID: periodID.isEmpty ? nil : periodID) }

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
    private var averages: [SchoolJSON] { value["subjectsAverages"]?.arrayValues ?? [] }
    private var grades: [SchoolJSON] {
        PronoteText.items(value, keys: ["grades"]).sorted { PronoteText.dateValue($0["date"]) > PronoteText.dateValue($1["date"]) }
    }
    var body: some View {
        if value["overallAverage"] != nil || value["classAverage"] != nil {
            AtelierCard {
                CadenceSectionHeader(title: "Moyenne générale")
                if let average = value["overallAverage"] { PronoteValueRow(title: "Votre moyenne", value: PronoteText.grade(average)) }
                if let average = value["classAverage"] { PronoteValueRow(title: "Classe", value: PronoteText.grade(average)) }
            }
        }
        if !averages.isEmpty {
            AtelierCard {
                CadenceSectionHeader(title: "Par matière")
                ForEach(Array(averages.enumerated()), id: \.offset) { index, average in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(PronoteText.subject(average)).font(.headline)
                        if let grade = average["student"] { PronoteValueRow(title: "Votre moyenne", value: PronoteText.grade(grade, outOf: average["outOf"])) }
                        if let grade = average["class_average"] { PronoteValueRow(title: "Classe", value: PronoteText.grade(grade, outOf: average["outOf"])) }
                    }
                }
            }
        }
        CadenceSectionHeader(title: "Évaluations", subtitle: "\(grades.count) résultat\(grades.count == 1 ? "" : "s")")
        ForEach(Array(grades.enumerated()), id: \.offset) { _, grade in PronoteGradeCard(value: grade) }
        if grades.isEmpty && averages.isEmpty {
            EmptyCard(title: "Pas encore de note", symbol: "chart.bar.xaxis", description: "Les résultats publiés par vos professeurs apparaîtront ici.")
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
    var body: some View {
        ForEach(groups, id: \.0) { key, title in
            let items = value[key]?.arrayValues ?? []
            if !items.isEmpty {
                CadenceSectionHeader(title: title)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    AtelierCard { PronoteReadableFields(value: item) }
                }
            }
        }
        if groups.allSatisfy({ value[$0.0]?.arrayValues?.isEmpty != false }) {
            EmptyCard(title: "Aucun élément de vie scolaire", symbol: "checkmark.circle", description: "Aucune absence, aucun retard ni aucune observation pour cette période.")
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
            }.buttonStyle(.plain)
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
    var body: some View {
        AtelierPage(lazy: true) {
            AtelierCard {
                CadenceSectionHeader(title: PronoteText.text(value["title"]) ?? "Information", subtitle: PronoteText.text(value["author"]))
                if let date = value["creationDate"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
                if let content = PronoteText.text(value["content"]), !content.isEmpty { Text(content).textSelection(.enabled) }
                if let question = value["question"], let content = PronoteText.text(question["content"]), !content.isEmpty { Text(content).textSelection(.enabled) }
                PronoteAttachments(value: value["attachments"] ?? .array([]))
            }
            ForEach(Array((value["questions"]?.arrayValues ?? []).enumerated()), id: \.offset) { _, question in
                AtelierCard {
                    PronoteReadableFields(value: question, labels: ["title": "Question", "content": "Détail", "textInputAnswer": "Votre réponse"])
                    PronoteAttachments(value: question["attachments"] ?? .array([]))
                }
            }
            if value["is"]?.stringValue == "survey" {
                Text("Ce sondage est consultable ici. Les réponses se font depuis PRONOTE.").font(.caption).foregroundStyle(CadenceColors.secondary)
            }
            if value["needToAcknowledge"]?.boolValue == true {
                if acknowledged || value["acknowledged"]?.boolValue == true {
                    Label("Réception confirmée", systemImage: "checkmark.circle.fill").foregroundStyle(CadenceColors.positive)
                } else if id != nil {
                    ProminentAction(title: sending ? "Envoi…" : "Accuser réception", symbol: "checkmark.message") { confirming = true }
                        .disabled(sending)
                }
            }
            if failed { Text("La confirmation n’a pas pu être envoyée. Réessayez lorsque la connexion est disponible.").font(.caption).foregroundStyle(CadenceColors.secondary) }
        }
        .navigationTitle("Information").navigationBarTitleDisplayMode(.inline)
        .alert("Confirmer la réception ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("Accuser réception") { Task { await acknowledge() } }
        } message: { Text("Un accusé de réception sera envoyé à votre établissement dans PRONOTE.") }
    }
    private func acknowledge() async {
        guard let id, !sending else { return }
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
    private var items: [SchoolJSON] { PronoteText.items(value, keys: ["resources", "items", "contents"]) }
    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            if let id = item["id"]?.stringValue, item["subject"] != nil {
                NavigationLink { PronoteResourceView(resourceID: id, seed: item) } label: {
                    AtelierCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(PronoteText.subject(item)).font(.headline)
                                if let date = item["startDate"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
                                if let names = PronoteText.text(item["teachers"]), !names.isEmpty { Text(names).font(.caption).foregroundStyle(CadenceColors.secondary) }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(CadenceColors.secondary)
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("pronote.resource." + id)
            } else { PronoteLessonContentCard(value: item) }
        }
        if items.isEmpty { EmptyCard(title: "Aucun contenu publié", symbol: "books.vertical", description: "Les leçons et ressources partagées par vos professeurs apparaîtront ici.") }
    }
}

private struct PronoteResourceView: View {
    let resourceID: String
    let seed: SchoolJSON
    @EnvironmentObject private var store: AppStore
    private var cacheKey: String { "resource:" + resourceID }
    private var value: SchoolJSON { store.pronotePortal.sections[cacheKey] ?? seed }
    var body: some View {
        AtelierPage(lazy: true) {
            PronoteCacheStatus(date: store.pronotePortal.updatedAt[cacheKey], loading: store.pronotePortalLoading.contains(cacheKey), error: store.pronotePortalErrors[cacheKey])
            AtelierCard {
                CadenceSectionHeader(title: PronoteText.subject(value), subtitle: PronoteText.text(value["teachers"]))
                if let date = value["startDate"] { Text(PronoteText.date(date)).font(.caption).foregroundStyle(CadenceColors.secondary) }
            }
            ForEach(Array((value["contents"]?.arrayValues ?? []).enumerated()), id: \.offset) { _, content in PronoteLessonContentCard(value: content) }
            if value["contents"]?.arrayValues?.isEmpty != false {
                EmptyCard(title: "Aucun détail de leçon", symbol: "doc.text", description: "Votre professeur n’a pas encore partagé de contenu pour ce cours.")
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
            if let description = PronoteText.text(value["description"]), !description.isEmpty { Text(description).textSelection(.enabled) }
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
        if let n = value.numberValue { return number(n) }
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
        let max = outOf?["points"]?.numberValue ?? outOf?.numberValue
        return number(points) + (max.map { $0.isFinite && $0 > 0 ? " / " + number($0) : "" } ?? "")
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
        var text = input.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div|li|h[1-6]|tr)\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</?[A-Za-z][^>]*>", with: "", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9A-Fa-f]+|[0-9]+);") {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let digitsRange = Range(match.range(at: 1), in: text), let fullRange = Range(match.range, in: text) else { continue }
                let digits = String(text[digitsRange]); let hex = digits.hasPrefix("x")
                if let number = UInt32(hex ? String(digits.dropFirst()) : digits, radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) {
                    text.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
