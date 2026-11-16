# Cadenza — Atelier Liquid Glass pour iPhone

Application native SwiftUI pour iPhone, interface française, iOS 17 minimum. Cours et révisions séparés, données locales, cache scolaire privé Supabase et séances personnelles locales. La synchronisation scolaire utilise une connexion initiale sécurisée. La version iPad est abandonnée. Les noms techniques du projet Cadence et les identifiants de stockage restent stables pour préserver les mises à jour.

La version **0.3.0** conserve le design Atelier, ajoute les cours et devoirs Supabase, le suivi de chaque devoir dans les séances, des halos mobiles, un lecteur de fichiers audio et une intégration Concentration par Raccourcis. Les cours passés comptent automatiquement, sans confirmation systématique. Voir [les changements et fichiers](docs/FONCTIONNALITES_0.3.0.md), [la connexion scolaire](docs/SUPABASE_CADENZA.md) et [les résultats vérifiés](docs/VERIFICATION.md).

Voir la [galerie des captures natives](Verification/0.3.0/APERCU.html).

## Commencer depuis Windows

1. Ouvrir [le guide Windows](docs/INSTALLATION_WINDOWS.md). Le projet est généré sur GitHub Actions avec XcodeGen ; aucun Mac personnel ni secret Apple n’est requis par la CI.
2. Pour mettre à jour l’app déjà testée, installer **Cadenza-iPhone-0.3.0.ipa** avec Sideloadly, le même compte et les mêmes options, par-dessus l’installation existante. Le programme d’essai **CadenceSpike** reste disponible pour un nouvel appareil ; voir [les six essais iPhone](docs/SPIKE_IPHONE.md).
3. Le fichier principal correspond au schéma **CadenceExtensions** : app complète, widgets et Live Activity. **Cadence** reste le mode autonome ; **CadenceShared** est l’option App Group, qui requiert des droits effectivement provisionnés. Le [guide des widgets](docs/WIDGETS_WINDOWS.md) explique la vérification après resignature.
4. Sauvegarder régulièrement le JSON dans Fichiers. Renouveler la signature par-dessus la même application et garder le même identifiant de bundle. La conservation des données au renouvellement doit être testée sur l’appareil.

Tous les schémas partagent le même identifiant d’application : **ils se remplacent sur l’iPhone**. Une sauvegarde doit précéder le passage d’une variante à l’autre. Le mode autonome conserve son propre stockage et ne dépend pas du conteneur d’un widget.

Le workflow `.github/workflows/build-unsigned-ipa.yml` compile les changements de code sur la branche principale d’un dépôt public avec un runner standard gratuit. Les sorties sont placées dans une release **brouillon** ; aucun cache ni artefact Actions payant n’est envoyé sur push. L’envoi facultatif vers les artefacts Actions requiert un lancement manuel et la vérification du quota. Sur un dépôt privé, le calcul reste bloqué tant que le quota gratuit et le blocage de l’usage payant n’ont pas été vérifiés puis explicitement activés. Dépôt demandé : [JuJT/Cadence](https://github.com/JuJT/Cadence).

## Fonctions implémentées

- Chronomètre unique, pauses et reprise à partir des dates persistées, historique modifiable, matières et alias configurables.
- Cours, devoirs et contenus lus depuis une API Supabase authentifiée ; aucun calendrier Apple ou ICS nécessaire au flux scolaire.
- Rapprochement des occurrences, récurrences et modifications ; conservation des séances personnelles lors des suppressions de source.
- Cours passés automatiquement estimés, hors annulation, dispense ou exclusion ; temps mesuré prioritaire sur l’estimation d’un cours associé.
- Statistiques natives Charts, ventilation des cours confirmés/mesurés, des cours estimés et des révisions.
- Devoirs : filtres, échéances, état local indépendant de PRONOTE et segments de travail dans une séance nouvelle ou déjà active.
- Sauvegarde JSON schéma 3, lecture des versions 1 et 2, copie avant migration et export CSV français.
- App Intents et App Shortcuts réels ouvrant l’application ; widgets et Live Activities avec repli explicite si le partage n’est pas disponible.
- Apparence Système/Claire/Sombre, Dynamic Type et composants Liquid Glass sur iOS 26 avec repli iOS 17.

L’application Watch dédiée reste hors de cette livraison. La présence d’une extension compilée ne prouve pas sa signature ni son fonctionnement après resignature. Les rapports et références historiques peuvent encore mentionner l’ancien nom ou l’iPad ; la configuration actuelle cible uniquement l’iPhone.

## Structure

```text
App/                 Application, vues SwiftUI, EventKit, persistance, App Intents
Sources/CadenceCore/  Domaine Swift pur, rapprochement calendrier, exports, calculs
Tests/               Tests métier et parcours UI pour simulateur
Widgets/             WidgetKit et régions de la Dynamic Island
Shared/              Attributs ActivityKit et copie minimale facultative pour widget
Config/              Plists, confidentialité et droits de la variante expérimentale
Scripts/             Compilation unsigned, simulateur et diagnostic des bundles
Reference/           Références originales du kit, absentes des ressources de l’app
docs/                Installation, données, architecture, recette et statut
project.yml          Projet XcodeGen
Package.swift        Noyau testable avec swift test
```

Voir [l’architecture](docs/ARCHITECTURE.md), [les données](docs/DONNEES.md), [la recette](docs/RECETTE.md) et [les changements](CHANGELOG.md).
