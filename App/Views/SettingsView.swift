import SwiftUI
import UniformTypeIdentifiers
import CadenceCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument = CadenceExportDocument(data: Data())
    @State private var exportType = UTType.json
    @State private var exportName = "Cadenza-sauvegarde"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showRestoreConfirmation = false
    @State private var pendingRestore: Data?
    @AppStorage("cadence.appearance") private var appearance = "system"
    var body: some View {
        List {
            Section("Apparence") {
                Picker("Ambiance", selection: $appearance) {
                    Text("Système").tag("system")
                    Text("Claire").tag("light")
                    Text("Sombre").tag("dark")
                }
            }
            Section("Votre organisation") {
                NavigationLink { CalendarSettingsView() } label: { Label("Calendriers et emploi du temps", systemImage: "calendar") }
                NavigationLink { SubjectsView() } label: { Label("Matières et mots-clés", systemImage: "books.vertical") }
                Picker("Matière par défaut", selection: Binding(get: { store.state.settings.defaultSubjectID }, set: { id in var settings = store.state.settings; settings.defaultSubjectID = id; store.updateSettings(settings) })) {
                    Text("Première matière disponible").tag(nil as UUID?)
                    ForEach(store.state.subjects.filter { !$0.isArchived }) { subject in Text(subject.name).tag(Optional(subject.id)) }
                }
            }
            Section {
                Button("Exporter une sauvegarde JSON", systemImage: "square.and.arrow.up") { prepareExport(csv: false) }
                Button("Exporter les durées en CSV", systemImage: "tablecells") { prepareExport(csv: true) }
                Button("Restaurer une sauvegarde JSON", systemImage: "square.and.arrow.down") { showImporter = true }
            } header: { Text("Vos données") } footer: {
                Text("Sauvegardez avant un renouvellement de signature. Une restauration remplace les données actuelles après confirmation. Aucun fichier n’est envoyé à un serveur.")
            }
            Section("Intégrations Apple") {
                Toggle("Live Activities", isOn: Binding(get: { store.state.settings.liveActivityEnabled }, set: { enabled in var settings = store.state.settings; settings.liveActivityEnabled = enabled; store.updateSettings(settings) }))
                NavigationLink { IntegrationsHelpView() } label: { Label("Widgets, Raccourcis et Apple Watch", systemImage: "square.stack.3d.up") }
            }
            Section("Diagnostic") {
                Text(store.storageDiagnostic).font(.footnote).textSelection(.enabled)
                Text("La disponibilité des extensions dépend de la signature de votre installation. La lecture réelle des widgets se vérifie sur votre iPhone.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Text("Cadenza · Atelier Liquid Glass\nDonnées locales · iOS 17 et versions ultérieures").font(.footnote).foregroundStyle(.secondary) }
        }
        .cadenceListStyle()
        .navigationTitle("Réglages")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: exportType, defaultFilename: exportName) { result in
            if case .failure(let error) = result { store.errorMessage = "Export impossible : \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                _ = try BackupCodec.decode(data)
                pendingRestore = data; showRestoreConfirmation = true
            } catch { store.errorMessage = "Lecture de sauvegarde impossible : \(error.localizedDescription)" }
        }
        .alert("Remplacer les données de Cadenza par cette sauvegarde ?", isPresented: $showRestoreConfirmation) {
            Button("Restaurer et remplacer", role: .destructive) { if let data = pendingRestore { store.restoreBackup(data) }; pendingRestore = nil }
            Button("Annuler", role: .cancel) { pendingRestore = nil }
        } message: { Text("Exportez d’abord vos données actuelles si vous souhaitez les conserver.") }
    }
    private func prepareExport(csv: Bool) {
        do {
            let data: Data
            if csv { data = try store.csvData() } else { data = try store.backupData() }
            exportDocument = CadenceExportDocument(data: data)
            exportType = csv ? .commaSeparatedText : .json
            exportName = csv ? "Cadenza-durees" : "Cadenza-sauvegarde"
            showExporter = true
        } catch { store.errorMessage = error.localizedDescription }
    }
}

private struct CadenceExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CalendarSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var previewPrepared = false
    @State private var keywords = ""
    @State private var confirmDisconnect = false
    var body: some View {
        List {
            Section {
                Label(store.calendarPermissionDescription, systemImage: "calendar")
                Button("Autoriser Calendrier") { Task { working = true; await store.requestCalendarAccess(); working = false } }.disabled(working)
                Text("Cadenza lit les calendriers déjà synchronisés dans iOS. Apple demande un accès complet pour permettre la lecture ; Cadenza ne modifie jamais vos événements.").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("1 · Autorisation") }
            Section {
                if store.calendarSources.isEmpty {
                    Text("Aucun calendrier disponible. Après autorisation, vérifiez vos comptes et calendriers dans les réglages de l’iPhone.").foregroundStyle(.secondary)
                }
                ForEach(store.calendarSources) { source in
                    Toggle(isOn: Binding(get: { store.state.settings.selectedCalendarIDs.contains(source.id) }, set: { selected in
                        var settings = store.state.settings
                        if selected { if !settings.selectedCalendarIDs.contains(source.id) { settings.selectedCalendarIDs.append(source.id) } }
                        else { settings.selectedCalendarIDs.removeAll { $0 == source.id } }
                        store.updateSettings(settings); previewPrepared = false
                    })) { VStack(alignment: .leading, spacing: 4) { Text(source.title); Text(source.sourceTitle).font(.caption).foregroundStyle(.secondary) } }
                }
            } header: { Text("2 · Choisir les sources de cours") } footer: { Text("Sélectionnez uniquement les calendriers de cours. Un calendrier Google doit déjà apparaître dans Calendrier Apple.") }
            Section {
                NavigationLink("Matières et alias") { SubjectsView() }
                TextField("Mots à exclure, séparés par des virgules", text: $keywords).onSubmit { saveKeywords() }
                Button("Enregistrer les exclusions") { saveKeywords() }
                Toggle("Compter les cours passés comme estimés", isOn: Binding(get: { store.state.settings.autoCreditCourses }, set: { enabled in
                    var settings = store.state.settings; settings.autoCreditCourses = enabled; store.updateSettings(settings)
                }))
            } header: { Text("3 · Classement et comptabilisation") } footer: {
                Text("Cette option est désactivée au départ. Si vous l’activez, les horaires terminés sont comptés comme estimés, séparément du temps mesuré. Une absence compte toujours pour zéro.")
            }
            Section {
                Button {
                    Task { working = true; await store.previewCalendarImport(); previewPrepared = store.errorMessage == nil; working = false }
                } label: { Label(working ? "Préparation…" : "Préparer l’aperçu", systemImage: "eye") }.disabled(working || store.state.settings.selectedCalendarIDs.isEmpty)
                if previewPrepared {
                    Text("\(store.calendarPreview.count) événements examinés, dont \(retainedCount) cours retenus, sur les 30 jours passés et les 30 jours à venir.").font(.subheadline)
                    ForEach(Array(store.calendarPreview.enumerated()), id: \.offset) { _, event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.title).font(.headline)
                            Text(event.start.cadenceFormatted(date: .abbreviated, time: .shortened) + " – " + event.end.cadenceFormatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            Text(event.calendarName).font(.caption).foregroundStyle(.secondary)
                            StatusBadge(title: previewStatus(event).title, color: previewStatus(event).color)
                        }
                    }
                    Button("Importer les cours retenus", systemImage: "checkmark.circle.fill") { store.importCalendarPreview(); if store.errorMessage == nil { previewPrepared = false } }.fontWeight(.semibold)
                    Text("Les matières incertaines seront à classer dans Cours. Les événements de révision et les journées entières sont exclus du suivi de cours.").font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("4 · Vérifier puis importer") }
            if store.state.settings.calendarEnabled {
                Section {
                    Button("Actualiser maintenant", systemImage: "arrow.clockwise") { Task { working = true; await store.refreshCalendars(); working = false } }.disabled(working)
                    if let sync = store.lastSyncAt { LabeledContent("Dernier import", value: sync.cadenceFormatted(date: .abbreviated, time: .shortened)) }
                    Button("Désactiver la synchronisation", role: .destructive) { confirmDisconnect = true }
                } footer: { Text("iOS ne garantit pas les actualisations en arrière-plan. Le planning est rapproché à la réouverture de Cadenza.") }
            }
        }
        .cadenceListStyle()
        .navigationTitle("Calendriers").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        .onAppear { keywords = store.state.settings.excludedKeywords.joined(separator: ", ") }
        .alert("Désactiver les prochains imports ?", isPresented: $confirmDisconnect) {
            Button("Désactiver") { var settings = store.state.settings; settings.calendarEnabled = false; store.updateSettings(settings) }
            Button("Annuler", role: .cancel) { }
        } message: { Text("Votre historique et vos séances restent conservés.") }
    }
    private var retainedCount: Int { store.calendarPreview.filter { previewStatus($0).retained }.count }
    private func previewStatus(_ event: CalendarEvent) -> (title: String, color: Color, retained: Bool) {
        if event.isAllDay { return ("Non importé · journée entière", .secondary, false) }
        if SubjectAliasResolver.isRevision(event.title) { return ("Non importé · révision", Atelier.revision, false) }
        if store.state.settings.excludedKeywords.contains(where: {
            let keyword = SubjectAliasResolver.normalize($0)
            return !keyword.isEmpty && SubjectAliasResolver.normalize(event.title).contains(keyword)
        }) { return ("Non importé · règle d’exclusion", .secondary, false) }
        if let id = SubjectAliasResolver.subjectID(for: event.title, subjects: store.state.subjects), let subject = Atelier.subject(id, in: store.state) {
            return (subject.name, Atelier.blue, true)
        }
        return ("Matière à classer après import", .orange, true)
    }
    private func saveKeywords() { var settings = store.state.settings; settings.excludedKeywords = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }; store.updateSettings(settings); previewPrepared = false }
}

struct SubjectsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNew = false
    var body: some View {
        List {
            ForEach(store.state.subjects.sorted { $0.position < $1.position }) { subject in
                NavigationLink { SubjectEditorView(subject: subject) } label: {
                    HStack {
                        SubjectMark(subject: subject)
                        VStack(alignment: .leading, spacing: 4) { Text(subject.name).font(.headline); Text(subject.isArchived ? "Archivée" : subject.aliases.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section { Text("Les mots-clés servent à proposer une matière lors d’un import. Si plusieurs matières correspondent, le cours reste à vérifier.").font(.footnote).foregroundStyle(.secondary) }
        }.cadenceListStyle().navigationTitle("Matières")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Nouvelle matière", systemImage: "plus") { showNew = true } } }
            .sheet(isPresented: $showNew) { NavigationStack { SubjectEditorView(subject: nil) } }
    }
}

private struct SubjectEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let subject: Subject?
    @State private var name: String
    @State private var aliases: String
    @State private var colorHex: String
    @State private var symbol: String
    @State private var archived: Bool
    @State private var confirmDelete = false
    private let colors = ["#2776F8", "#7668F6", "#27835D", "#B46B26", "#BC426C", "#347D93"]
    private let symbols = ["book.closed", "function", "atom", "leaf", "globe.europe.africa", "text.book.closed", "character.bubble", "music.note"]
    init(subject: Subject?) {
        self.subject = subject
        _name = State(initialValue: subject?.name ?? ""); _aliases = State(initialValue: subject?.aliases.joined(separator: ", ") ?? "")
        _colorHex = State(initialValue: subject?.colorHex ?? "#2776F8"); _symbol = State(initialValue: subject?.symbol ?? "book.closed"); _archived = State(initialValue: subject?.isArchived ?? false)
    }
    var body: some View {
        Form {
            Section("Matière") {
                TextField("Nom de la matière", text: $name)
                Picker("Symbole", selection: $symbol) { ForEach(Array(symbols.enumerated()), id: \.element) { index, item in Label(["Livre", "Mathématiques", "Atome", "Feuille", "Globe", "Texte", "Langues", "Musique"][index], systemImage: item).tag(item) } }
                Picker("Couleur", selection: $colorHex) { ForEach(Array(colors.enumerated()), id: \.element) { index, value in Text(["Bleu", "Indigo", "Vert", "Ocre", "Rose", "Turquoise"][index]).tag(value) } }
                Toggle("Archiver la matière", isOn: $archived)
            }
            Section { TextField("Ex. MATH, Maths", text: $aliases, axis: .vertical).lineLimit(2...5) } header: { Text("Mots-clés du calendrier") } footer: { Text("Séparez les alias par une virgule. Le nom complet de la matière est également reconnu.") }
            if subject != nil { Section { Button("Supprimer la matière", role: .destructive) { confirmDelete = true } } footer: { Text("Une matière déjà utilisée sera archivée pour préserver son historique.") } }
        }.cadenceListStyle().navigationTitle(subject == nil ? "Nouvelle matière" : "Modifier la matière").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if subject == nil { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("Supprimer cette matière ?", isPresented: $confirmDelete) {
                Button("Supprimer ou archiver", role: .destructive) { if let subject { store.deleteSubject(subject.id); if store.errorMessage == nil { dismiss() } } }
                Button("Annuler", role: .cancel) { }
            }
    }
    private func save() {
        let value = Subject(id: subject?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), colorHex: colorHex, symbol: symbol,
            aliases: aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }, isArchived: archived, position: subject?.position ?? store.state.subjects.count)
        store.saveSubject(value); if store.errorMessage == nil { dismiss() }
    }
}

private struct IntegrationsHelpView: View {
    var body: some View {
        List {
            Section("Live Activities") {
                Text("Démarrez une séance puis verrouillez l’iPhone. Si les activités en direct sont autorisées et l’extension correctement signée, la séance peut apparaître sur l’écran verrouillé et dans la Dynamic Island.")
                Text("L’affichage système peut expirer sans interrompre votre séance. Sa durée est retrouvée à la réouverture.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Widgets") {
                Text("Ajoutez Cadenza depuis la galerie de widgets. Aujourd’hui, Ma semaine et Prochain cours utilisent votre résumé local. La signature doit autoriser le partage entre l’app et ses widgets. Le diagnostic indique leur dernière lecture réelle.")
            }
            Section("Raccourcis Apple") {
                Text("Les actions Cadenza permettent de démarrer une révision, ajouter un cours, mettre en pause, reprendre, terminer, consulter les durées du jour et ouvrir l’emploi du temps.")
                Link("Ouvrir Raccourcis", destination: URL(string: "shortcuts://")!)
            }
            Section("Apple Watch") {
                Text("Le relais d’une Live Activity sur la Watch dépend du système. L’application Watch dédiée est prévue après validation de l’installation iPhone.")
            }
            Section("Signature gratuite") {
                Text("Une installation avec un Apple ID gratuit doit généralement être renouvelée après sept jours. Gardez le même identifiant d’app et sauvegardez vos données avant toute réinstallation.")
            }
        }.cadenceListStyle().navigationTitle("Intégrations").navigationBarTitleDisplayMode(.inline)
    }
}
