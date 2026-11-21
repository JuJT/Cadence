# Historique

## 0.7.0 — Révision et vie scolaire

- Révision et Statistiques accessibles dès l’accueil. Accès à la séance en cours depuis les autres onglets.
- Horaires mieux séparés, notes regroupées par matière et actions de devoirs réunies sur les cartes d’échéance.
- Chronomètre actualisé dès l’ouverture d’une séance depuis un devoir, et recalé au retour au premier plan.
- Connexion PRONOTE intégrée au démarrage, avec identifiants directs, QR et parcours ENT compatibles.
- Autorisation des alertes de changements de cours à la fin de la présentation de Cadenza.
- Téléchargement et partage de l’IPA publique depuis Mises à jour pour l’installer via Sideloadly.

## 0.6.0 — La journée scolaire — 20 novembre 2026

- Onglet Notes, accès immédiat aux rubriques scolaires depuis l’accueil et Statistiques dans Révision.
- Emploi du temps compact avec bandeau de jours. Contenus classés par matière sur l’année scolaire, puis par date croissante.
- Consignes complètes, pièces jointes et actions sur chaque carte de devoir.
- Récupération du détail des informations avec le destinataire PRONOTE et prise en charge des articles en plusieurs blocs.
- Widgets Moyenne générale et Devoirs à venir. Détection des droits partagés d’après les signatures de l’app et de l’extension.
- Alertes sur les changements du planning à chaque synchronisation. Actualisation en arrière-plan selon la disponibilité accordée par iOS.
- Commandes Apple Music, lecteur de liens Spotify et Spotify Connect avec un compte autorisé. Retrait de la fonction Concentration.
- Transition entre les écrans de bienvenue et de nouveautés.

## 0.5.0 — Scolarité intégrée — 19 novembre 2026

- Notes, informations et absences accessibles depuis l’accueil ; contenus de cours regroupés par matière.
- HTML scolaire nettoyé dans les flux et les anciens caches ; actions Valider / Démarrer sur les cartes de devoirs.
- Période actuelle propre à chaque écran PRONOTE ; moyennes officielles prioritaires et estimations clairement identifiées.
- Lecture des informations PRONOTE 2026 corrigée en présence de natures et catégories personnelles, sans dépendre des métadonnées facultatives d’accusé.
- Absences structurées par dates, durée, motif et justification ; première installation et nouveautés versionnées en trois étapes.
- Appels Raccourcis Concentration retirés ; volume système/AirPlay conservés, lecteur universel expliqué dans le Centre de contrôle.
- Recherche des versions publiques dans Réglages ; compatibilité du renouvellement Sideloadly conservée.

## 0.4.0 — PRONOTE direct et fluidité — 18 novembre 2026

- Connexion directe Pawnote, annuaire facultatif et portail scolaire avec cache.
- Cours/Révisions réunissent toutes les durées, réparation des cours remplacés et conservation des choix locaux et du travail sur les devoirs.
- Devoirs par dates limites exactes, navigation et calculs de graphiques optimisés, fond suspendu hors écran et en cas de chauffe.
- Raccourci Concentration signé prêt à ajouter, volume et sortie audio système ; import MP3 et lien Deezer supprimés.
- Sources de la bibliothèque et notices incluses. Résultats exacts et limites matérielles dans docs/VERIFICATION.md.

## 0.3.0 — Synchronisation scolaire et devoirs — 17 novembre 2026

- Lecture Supabase sécurisée, cours et devoirs en cache hors connexion ; plus de dépendance au calendrier PRONOTE de l’iPhone.
- Migration préservant les séances, alias et notes ; rapprochement des doublons sans double crédit et cours passés automatiquement comptés comme estimés.
- Devoirs liés aux séances, attribution du temps hors pauses et état de réalisation local conservé.
- Correction des destinations Keychain des widgets et isolation des jetons d’authentification dans le groupe privé de l’app.
- Musique depuis Fichiers, intégration Concentration par raccourci initial, halos animés et transitions ; carte informative Révision supprimée.
- API réelle vérifiée ; 65 tests Swift, 13 Python, contrôles de résumé/signature et 11 parcours natifs réussis. Les tests après resignature sur iPhone restent distincts.

## 0.2.0 — Cadenza pour iPhone — 15 novembre 2026

- Renommage visible en Cadenza et abandon de l’interface, des tests et du workflow dédiés à l’iPad ; identifiants de mise à jour, données et alias conservés.
- Refonte Atelier Liquid Glass : fond atmosphérique, surfaces translucides, accueil, agenda, grand minuteur circulaire, statistiques, formulaires et apparence claire/sombre.
- Nouvelle icône en C de verre bleu, avec original et prompt conservés.
- Widgets Aujourd’hui, Ma semaine, Prochain cours et Temps d’étude ; résumé local et diagnostic de lecture réelle par l’extension.
- Vérification finale et captures natives : voir `docs/VERIFICATION.md`.

## Livraison vérifiée — 15 novembre 2026

- Quatre IPA compilées avec Xcode 26.6 : essai minimal, autonome, extensions et App Group facultatif.
- 34 tests métier et 6 tests de scripts réussis ; parcours iPhone clair/sombre et iPad paysage exécutés en simulateur.
- Neuf captures natives vérifiées, avec contrôle ciblé de la capture plein écran iPad.
- Empreintes SHA-256 des IPA vérifiées ; guides et matrice mis à jour. Signature gratuite et installation physique restant à valider.

## 0.1.0 — 14 novembre 2026

- Construction du projet SwiftUI à partir du kit Atelier Liquid Glass V2.
- Ajout du noyau Foundation testable : sessions, pauses, matières, alias, import calendrier, rapprochement, statistiques et sauvegardes.
- Interface française native iPhone/iPad : accueil, cours, révision, statistiques, historique, matières et réglages.
- Intégration EventKit en lecture uniquement avec consentement et aperçu ; estimations facultatives séparées des mesures.
- App Intents, widgets, Live Activity et Dynamic Island ; variantes autonome, extensions, partage expérimental et essai minimal.
- Projet XcodeGen, workflow macOS sans secrets Apple, diagnostics IPA et recette Windows/Sideloadly.
- Résultats de compilation et de simulateur, limites de signature et tests physiques consignés dans le rapport de vérification.
