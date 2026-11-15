# Cadence 0.1.1 — corrections après essai iPhone

Les flèches du calendrier disposent chacune de leur propre zone de clic et d’une action indépendante dans la liste. Elles déplacent la date d’un jour en mode Jour et de sept jours en mode Semaine. Les intervalles excluent le début du jour ou de la semaine suivante.

Les cours classés affichent le nom de leur matière dans la liste, le détail, le prochain cours et les sélecteurs d’association. Les titres du calendrier restent conservés dans les données et consultables dans « Détails du calendrier ». Les cours sans matière conservent leur titre pour permettre leur classement. Les alias personnels et la synchronisation existante restent conservés : Accompagnement personnalisé et Vie de classe peuvent ainsi tous deux apparaître sous Français.

Après la première association et l’import confirmé, les calendriers activés sont relus au lancement, au retour au premier plan et lors des changements signalés par Calendrier pendant que l’app s’exécute. Aucun import hebdomadaire manuel n’est nécessaire. La source doit elle-même être à jour dans Calendrier Apple ; une mise à jour permanente pendant que Cadence est suspendue n’est pas garantie par iOS.

« Nouvelle séance » ouvre une feuille native avec le choix Cours/Révision, puis le formulaire dans la même feuille. La confirmation de fin et les autres confirmations binaires utilisent une alerte centrée avec une action d’annulation.

La Dynamic Island réserve une colonne au chronomètre et place la matière sous la zone caméra, avec des marges et un lien d’ouverture plus courts. Le rendu exact reste à contrôler sur l’iPhone après mise à jour.

Les widgets distinguent les formats petit et moyen. Dans CadenceExtensions, sans App Group, ils servent de raccourci d’ouverture et ne présentent aucun faux total. Les données de suivi dans les widgets nécessitent CadenceShared et un profil de signature autorisant l’App Group ; cette possibilité n’est pas garantie par une signature personnelle gratuite. Le message technique de repli a été remplacé par une présentation adaptée à la taille du widget.

## Installation

Utiliser l’IPA CadenceExtensions 0.1.1 dans Sideloadly avec le même compte et les mêmes options que pour l’installation actuelle. L’identifiant de l’app est conservé. Installer par-dessus l’app existante ; ne pas la désinstaller. Une exportation JSON depuis Réglages peut être conservée avant la mise à jour.

## Recette sur l’iPhone

1. Dans Cours → Jour, avancer puis reculer : les dates et les cours doivent suivre. Vérifier également Semaine.
2. Vérifier que les matières reconnues portent leur nom court, notamment Anglais et Français pour les alias personnels.
3. Ouvrir Nouvelle séance : une feuille doit apparaître depuis le bas. Démarrer, terminer, puis annuler la confirmation : la séance doit rester active. Confirmer ensuite son enregistrement.
4. Contrôler la Dynamic Island en appui long, séance active puis en pause, avec une matière longue.
5. Contrôler les widgets petit et moyen. Si l’ancien rendu persiste, retirer le widget puis l’ajouter à nouveau, sans supprimer l’app.

La refonte esthétique générale selon le kit initial est prévue à l’étape suivante.
