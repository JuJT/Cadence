# Statut de vérification — 14 novembre 2026

| Niveau | Statut et preuve |
|---|---|
| Sources | Projet SwiftUI/XcodeGen, moteur, tests et intégrations écrits |
| Syntaxe locale | Analyse Swift tree-sitter, YAML, JSON, plists et scripts ; détail dans `Verification/local-checks.json` |
| Diagnostic IPA | 3 tests Python exécutés et réussis sur Windows |
| Tests métier Swift | 32 tests XCTest écrits ; exécution locale impossible, WSL a renvoyé ERROR_TIMEOUT avant le lancement du compilateur |
| Compilation Xcode / IPA appareil | En attente de GitHub Actions dans JuJT/Cadence |
| Tests et captures simulateur | Non exécutés à ce stade |
| Installé et testé sur iPhone | Non effectué |
| Signature gratuite, widget, Live Activity, Raccourcis | Implémentés, fonctionnement réel non validé |
| iPad / MDM / Watch | Non testé ; Watch dédiée reportée |

Le dépôt demandé est [JuJT/Cadence](https://github.com/JuJT/Cadence). Il ne contenait qu’un README lors de sa lecture initiale. Aucune donnée scolaire réelle ni secret Apple n’est ajouté au projet.

L’essai de compilation locale sous Ubuntu WSL a été interrompu après une erreur de délai du service WSL. Aucun paquet système n’a été installé et aucun service n’a été modifié. Une toolchain Swift provisoire peut rester dans `/var/tmp/cadence-swift` de cette distribution ; elle ne fait pas partie du livrable.

Les tests automatisés ne remplacent pas la checklist physique. Les captures d’origine dans `Reference/Design` sont des maquettes, jamais des captures d’une application compilée. Les captures natives et inventaires de `.app/PlugIns` seront produits uniquement par un run CI réel.
