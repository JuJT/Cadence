# Atelier Liquid Glass — design system à implémenter en natif

## Objectif

Application qui semble créée par Apple : sobriété, hiérarchie, surfaces natives, typographie SF, animations fluides, séparation claire entre données et actions. **« Liquid Glass au maximum » signifie adopter toutes les surfaces système pertinentes**, pas appliquer du flou sur chaque carte. Apple recommande explicitement d'utiliser le verre surtout pour les **contrôles et la navigation**, non comme fond de tous les contenus.

Références Apple :
- https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/design/human-interface-guidelines/materials

## Matériaux et navigation

- Utiliser `TabView` et `NavigationStack` natifs iOS 26+ ; pas de barre d'onglets HTML réimplémentée ni de fond opaque personnalisé par-dessus celle du système.
- Sur iPad : `NavigationSplitView`, colonnes fluides, pas d'étirement d'une interface iPhone.
- `toolbar`, `Menu`, `confirmationDialog`, `.sheet`, `.popover`, `.searchable`, `Picker`, `DatePicker` natifs, avec coins concentriques et respect des safe areas.
- Bouton principal « Démarrer une révision »/« Nouvelle séance » : style natif **glassProminent** dans le SDK récent (si disponible) ; secondaire `.glass` et surfaces système. Les couleurs de matières ne servent que d'accent local.
- `GlassEffectContainer` pour un groupe de contrôles custom interactifs ; `glassEffect` seulement là où le composant natif ne fournit pas déjà l'effet. Vérifier la version d'API exacte dans le SDK du runner.
- Ne pas reconstituer une Dynamic Island dans l'application native : c'est le système qui affiche la Live Activity. La maquette HTML montre uniquement un aperçu.
- Fond contenu : `Color(uiColor: .systemGroupedBackground)` / `secondarySystemGroupedBackground`, blanc optique bleuté subtil ; couleurs sémantiques (primary/secondary), cartes lisibles. Éviter une avalanche de panneaux transparents.
- Mode sombre automatique, contrastes et textures adaptés, `Reduce Transparency`, `Reduce Motion`, Dynamic Type, VoiceOver, gros boutons 44pt+, SF Symbols.

## Direction graphique choisie

- **Accent système** bleu lumineux : `#2776F8` (adapter à accentColor/contraste).
- **Cours** bleu : `#258BFF`, **Révision** indigo : `#7668F6` ; matières via petits marqueurs en couleur distincte. Toujours associer texte/icône à la couleur.
- Gradients légers uniquement en arrière-plan derrière les contrôles et dans les grands graphiques ; pas d'effets saturés sur le contenu du tableau.
- SF Pro / SF Rounded pour grands compteurs si approprié, `monospacedDigit()` sur temps.
- Grands titres, densité typographique Apple, panneaux non tapageurs. Ombres douces et épaisseurs de bordure fines dans la maquette, mais UI native doit privilégier les styles système.
- Haptique sur démarrage, pause, terminaison et bascule Cours/Révision (respecter réglages système).

## Structure exacte de l'interface

Onglets : `Accueil`, `Cours`, `Révision`, `Statistiques` ; `Réglages` dans la barre de navigation (ou cinquième onglet si ergonomique sur iPad). Pas de doublon d'un onglet « Session » : les commandes de cours sont accessibles depuis cours importé et « Révision » pilote le minuteur.

### Accueil

Grand titre Cadence ; total du jour **Cours / Révisions** séparés ; carte « En cours » uniquement si session active ; carte « Prochain cours » avec heure et provenance calendrier ; bouton primaire « Nouvelle séance » ouvrant choix `Cours` / `Révision` ; historique récent et état de synchronisation. Dans le détail, séparations de temps **estimé d'après emploi du temps** et **mesuré**.

### Cours — calendrier et manuel

`Semaine`/`Jour`/`Liste` via segmented Picker ; dates native ; planning avec événements importés et cours ajoutés manuellement ; badge `Calendrier`/`Manuel`, statut `À venir`, `Estimé`, `Confirmé`, `Absent`, `Modifié`, `À vérifier` ; bouton `+ Cours` ; panneau « Calendrier lié » et « dernière mise à jour ». Toucher un événement : matière, titre, horaires, provenance, `Confirmer`, `Modifier`, `Absence`, `Chronométrer`, `Associer à séance manuelle`.

### Révision

Sélection matière/chapitre ; énorme minuteur lisible ; état `En cours`/`Pause`; boutons pause/reprise/terminer, démarrage rapide ; notes a posteriori ; temps écoulé calculé depuis dates, pas `Timer` en arrière-plan ; appui prolongé facultatif pour prévenir une fin accidentelle.

### Statistiques

Filtres `Cours` / `Révisions` / `Tout`, période jour/semaine/mois, histogramme (Charts), répartition matières, distinction **temps mesuré** vs **temps estimé par le planning**, heures non confirmées ; les cours non commencés ne comptent jamais dans les heures réalisées.

### Réglages

Source calendrier (un ou plusieurs calendriers iOS), permission, règles d'association automatique, crédit automatique cours, édition matières et alias, export/import, diagnostic extensions, gestion Live Activities et notifications, entrée Raccourcis et limitations de la signature gratuite.

## Surface système : spécifications compactes

- **Dynamic Island** : icône livre / matière + durée `01:24` en compact ; nom, mode et actions disponibles en expanded ; clock basée sur dates, pas mises à jour/s serveur.
- **Live Activity écran verrouillé** : type, matière, durée, état pause/active et bouton « Ouvrir ». Peut expirer à 8 h sans terminer la session.
- **Widgets** : petit « aujourd'hui : cours x / révisions y » ; moyen « prochaine heure de cours + séance active + séparation type » ; actions facultatives et conditionnées aux droits.
- **Watch** : Smart Stack d'abord ; application dédiée plus tard.

## Disponibilité OS

Cible de compilation SDK récent, minimum iOS 17 conseillé pour iPad personnel/scolaire. Sur iOS 26+ conserver composants natifs Liquid Glass ; sur 17–25, fallback matériaux et boutons standards avec `#available`, **sans dégrader la lisibilité**. Documentation de compatibilité requise après le premier build réel.
