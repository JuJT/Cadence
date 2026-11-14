# Calendrier iOS + cours manuels — spécification métier impérative

## Principe d'intégration : EventKit d'abord

Le compte Google de l'utilisateur est déjà synchronisé dans Calendrier Apple. L'application lit les événements **visibles dans Calendrier iOS/iPadOS** avec `EventKit` (EKEventStore) après autorisation. Elle n'a besoin d'**aucun OAuth Google, API Google, serveur ni token externe** pour ce parcours. L'utilisateur choisit un ou plusieurs calendriers sources, par exemple calendrier Google « cours » ou calendrier Apple local.

- Ajouter `NSCalendarsFullAccessUsageDescription` dans l'Info.plist, expliquer en français « Cadence lit vos créneaux de cours pour les intégrer à votre suivi ; aucune donnée n'est envoyée. »
- Appeler `requestFullAccessToEvents` uniquement après activation explicite de « Synchroniser mon emploi du temps » ; iOS 17+ demande **full access** pour lire les événements, il n'existe pas un accès lecture seule EventKit. **Ne jamais modifier ou supprimer les événements Calendar** : lecture seule contractuelle côté application.
- Lister uniquement les calendriers disponibles, laisser choisir ceux à importer ; un calendrier Google/ICS peut apparaître comme un calendrier iOS, selon le compte et les réglages de l'appareil. Si calendrier non visible, expliquer comment activer son affichage dans Calendrier Apple ou proposer un import .ics facultatif P2.
- Synchronisation `EKEventStoreChanged`, au lancement, au retour au premier plan, refresh manuel, rafraîchissement système opportuniste ; **pas de promesse de synchronisation périodique garantie en arrière-plan** sous iOS.
- Les événements restent en cache local utilisable hors connexion ; la synchro réseau Google ↔ Calendrier est gérée par iOS, pas par Cadence.

## Types et états — ne pas confondre

`SessionKind = course | revision` est un axe distinct de `Origin = calendar | manual | timer | shortcut | watch`. **Ne jamais inférer « cours » simplement parce qu'un événement existe dans Calendrier** ; ne traiter que calendriers explicitement sélectionnés et événements acceptés par l'utilisateur.

`CourseOccurrenceStatus` :
- `scheduled` : événement à venir ; **0 minute comptabilisée**.
- `inProgressScheduled` : événement en cours dans agenda ; non mesuré automatiquement en arrière-plan. Si réglage auto activé, l'app peut montrer un aperçu, mais aucune minuterie cachée n'est promise.
- `estimated` : horaire passé converti automatiquement en durée théorique ; **badge Estimé**, temps comptabilisé dans une colonne « cours estimés » distincte, jamais présenté comme réellement chronométré.
- `confirmed` : durée validée manuellement par l'utilisateur, comptabilisée cours réalisés.
- `measured` : séance réellement chronométrée, liée à l'événement ou créée librement.
- `absent` : séance non suivie, **0 minute**.
- `cancelled` / `ignored` : aucune minute créditée.
- `needsReview` : conflit / changement d'horaires / mapping incertain ; conserver valeur précédente tant qu'une décision n'est pas prise.

**Préférence par défaut produit** : `autoCreditCourses = ON` après consentement explicite dans l'onboarding ; créer une `estimated` pour les créneaux de cours passés lors de l'import/rafraîchissement. L'interface montre une séparation nette **Cours estimés** / **Cours confirmés ou mesurés** et offre l'action « Marquer absent ». Si refus, laisser simplement l'agenda planifié, sans crédit automatique. L'utilisateur peut modifier la préférence ultérieurement.

## Révisions

- Les sessions de **révision** sont manuelles : lancement minuteur, pause/reprise/fin, ajout d'une durée passée, via Raccourcis et éventuellement Watch.
- Un événement de calendrier contenant « révision » ne doit PAS devenir un cours ; l'utilisateur peut le rattacher volontairement à une révision manuelle si souhaité (P2).
- Les statistiques `Tout = Cours + Révisions` utilisent des ensembles disjoints ; aucun dédoublement du même cours ou de la même minuterie.

## Normaliser les matières

1. L'utilisateur définit les matières (Mathématiques, Physique-Chimie, SVT, etc.), modifiables.
2. `SubjectAlias` : mots-clés / préfixes par matière, p. ex. `MATH`, `Maths`→Mathématiques ; `PC`, `Physique`→Physique-Chimie ; `H-G`→Histoire-Géographie.
3. Le classifieur local déterministe propose la matière. Si incertain, statut `needsReview`, liste explicite à classer ; ne jamais attribuer silencieusement une matière arbitraire.
4. Les exceptions utilisateur (alias spécifiques) l'emportent sur les heuristiques ; possibilité « ne jamais importer événements comportant X ».
5. Traiter les récurrences par occurrence séparée (y compris décalages et cours annulés), ne pas créer une session unique pour toute la série.

## Rapprochement et dédoublonnage

Source d'identité d'occurrence : `calendarIdentifier`, `eventIdentifier`, `calendarItemExternalIdentifier?`, `occurrenceStartUTC`, `occurrenceEndUTC`, `sourceTitle`, `lastSeenAt`. Les identifiants Apple peuvent changer lors d'une resynchronisation : **ne pas les utiliser comme seule clé**. Stocker un `sourceFingerprint` + logique de rapprochement contrôlée ; correspondance : identifiant stable quand possible, sinon calendrier + titre normalisé + heure avec tolérance conservatrice ; un lien décidé par l'utilisateur (`manualLink`) est prioritaire. **Aucune fusion automatique ambiguë**.

Import idempotent : relire le même calendrier 20 fois ne crée aucune nouvelle occurrence ni aucun double crédit. Sur événement modifié : mettre à jour l'horaire planifié s'il n'y a pas eu d'édition manuelle ; si séance confirmée/mesurée, conserver la session et demander arbitrage. Sur suppression : ne jamais supprimer de données de sessions personnelles ; marquer l'événement « n'apparaît plus au calendrier » / cancelled ou needsReview. Sur calendrier désactivé : conserver l'historique, ne plus importer de nouveaux cours, proposer désassociation facultative.

Si un cours manuel chevauche un cours importé (même matière et fenêtre similaire), proposer « Associer à ce cours » : l'occurrence importée devient **un seul enregistrement de séance**, avec durée mesurée prioritaire sur la durée estimée. Ne jamais sommer mesuré + estimé pour la même occurrence. Si l'utilisateur ajoute manuellement un cours supplémentaire distinct, autoriser un chevauchement intentionnel après confirmation.

## Paramètres par défaut et consentement

Première connexion : (1) bouton « Autoriser Calendrier » ; (2) choix du/des calendriers ; (3) règles/alias de matières ; (4) option « Après l'heure de fin, compter ces cours comme estimés » activable explicitement ; (5) aperçu import avec nombre de cours et valeurs incertaines ; (6) bouton « Importer ». Toutes ces actions sont réversibles.

Aucune donnée calendrier envoyée dans GitHub Actions, aucun stockage distant. Les screenshots du kit sont fictifs.

## Tests obligatoires

- Imported recurring single course is 1 occurrence per day; 2 imports = same record.
- Google calendar visible via Apple Calendar; user selects source; no Google login popup.
- Calendar permission denied -> manual course and revisions fully work.
- Subject alias ambiguous -> needsReview not mistaken automatic match.
- Event modified from 08:00 to 09:00 -> scheduled occurrence updates; measured session preserved.
- Event deleted -> confirmed session and notes retained.
- Past estimated course later measured manually -> **replace estimate**, not add twice.
- Missing/absent marked -> 0; future planned -> 0.
- Daylight saving / timezone / midnight / overlapping events / recurrence exceptions tested.
- Force-quit app during school day -> no guarantee of background auto-refresh; recalculate missed occurrences on next foreground.
- Calendar category separation: class calendar never silently classified as revision.
