# Historique

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
