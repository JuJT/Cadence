# Cadenza 0.2.0 — Atelier lumineux pour iPhone

La livraison finale porte le nom **Cadenza** et vise uniquement l’iPhone, conformément à la dernière demande. L’interface et les contrôles spécifiques à l’iPad ont été retirés. Les noms techniques historiques `CadenceCore`, les identifiants de bundles, les groupes de partage, les URLs `cadence://` et le dossier de stockage existant restent inchangés pour préserver la mise à jour et les données.

## Audit et direction retenue

La version précédente privilégiait des listes et des cartes système opaques. Elle conservait la fonctionnalité native, mais le fond presque plat, les panneaux uniformes et le minuteur rectangulaire restaient éloignés des trois maquettes du kit. Le nouveau brief demande explicitement davantage de matière sur les cartes : cette consigne remplace la recommandation « verre limité aux contrôles » de l’ancienne charte, avec un maintien du contraste et des surfaces opaques lorsque Réduire la transparence est activé.

## Système visuel

`App/Design/CadenceTheme.swift` centralise les couleurs, espacements et rayons (`CadenceColors`, `CadenceSpacing`, `CadenceRadius`, `CadenceTheme`). `CadenceBackground` compose des champs de lumière statiques bleu glacier, sans animation permanente coûteuse. `CadenceGlassStyle` et `cadenceSurface` réunissent matière native, voile clair, reflet fin et ombre douce. Les composants existants `AtelierCard`, `AtelierPage`, `ProminentAction`, `SecondaryAction`, `SubjectMark` et `MetricRow` utilisent ce système, complété par `CadenceSectionHeader`, `cadenceSegmentedStyle` et `cadenceListStyle`.

La navigation iPhone conserve `TabView` et `NavigationStack`. Sur iOS 26, la barre basse et les actions utilisent leur verre natif ; les versions antérieures gardent un repli système. Les contrôles, titres, alertes et feuilles restent de vrais composants SwiftUI. Réglages → Apparence permet de choisir Système, Claire ou Sombre, sans modifier le format de sauvegarde des séances.

## Écrans

- **Accueil** : Bonjour, carte du jour avec anneau de répartition réelle Cours/Révisions, prochain cours, action Nouvelle séance, histogramme de la semaine et historique. Aucun pourcentage d’objectif inventé.
- **Emploi du temps** : sélection native Semaine/Jour/Liste, date et flèches indépendantes, journées en panneaux lumineux, colonne d’horaires et cours bleutés, état de synchronisation et ajout manuel conservés.
- **Révision** : anneau lumineux autour de la matière et du temps écoulé, commandes Pause/Reprendre/Terminer, type de séance et chiffres réels du jour et de la matière. L’anneau de séance est décoratif et ne représente pas un objectif absent du modèle. Les très grandes polices utilisent une carte souple pour garder toutes les actions accessibles.
- **Statistiques** : résumé plus lisible, anneau de répartition, histogramme doux, unités adaptées aux données et répartition par matière. Les estimations restent distinctes des durées mesurées et confirmées.
- **Formulaires et réglages** : fonds et matériaux harmonisés, confirmations centrées et feuille de Nouvelle séance conservées.

Les fichiers concernés sont les vues dans `App/Views`, le thème, les assets de marque et les vues de widgets dans `Shared`. La logique `Sources/CadenceCore`, les alias personnels, l’import calendrier et le schéma JSON de sauvegarde restent conservés.

## Icône

Un C en ruban de verre bleu remplace le livre générique ; un pli discret évoque une page. L’icône est une création originale réalisée avec **imagegen intégré**. Le PNG opaque 1024 × 1024 est intégré à AppIcon. L’original et le prompt exact sont conservés dans `Reference/Brand`.

## Widgets

Aujourd’hui, Ma semaine, Prochain cours et Temps d’étude utilisent un résumé réel publié par Cadence. La variante Extensions ajoute le partage de trousseau autorisé par iOS ; App Group reste une autre variante. La conservation effective des droits pendant la resignature Sideloadly et la lecture sur l’iPhone se vérifient avec le reçu d’extension dans le diagnostic. Le guide [WIDGETS_WINDOWS.md](WIDGETS_WINDOWS.md) détaille ce contrôle. Aucun chiffre fictif n’est affiché si le partage est indisponible.

## Vérification du rendu

Les parcours de régression restent présents. Des données de démonstration sont ajoutées uniquement sous `targetEnvironment(simulator)` et un argument XCTest explicite, dans le stockage isolé des tests. Elles permettent de capturer les vrais écrans remplis sans charger les données personnelles. Une galerie QA emploie exactement les composants SwiftUI des widgets : ses captures sont des aperçus de composants, et non la preuve d’une installation WidgetKit sur l’écran d’accueil ou d’une signature valide.

Les résultats de compilation, les captures natives et leurs limites sont consignés dans `VERIFICATION.md` à la fin de la compilation.
