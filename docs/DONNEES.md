# Données, migration et sauvegardes

Le suivi d’étude garde son fichier `Application Support/Cadence/cadence-state.json`, son format compatible et une génération précédente récupérable. Les séances, matières, alias, notes et associations restent conservés. Les anciennes sauvegardes sont toujours lisibles.

La version 0.4 répare les occurrences scolaires remplacées en conservant l’historique. Une ancienne annulation de source n’est plus confondue avec un choix explicite de l’utilisateur. Les occurrences archivées peuvent garder leurs séances mesurées ; ces séances restent éditables. La salle et le professeur ne définissent pas l’identité d’un cours.

Les devoirs possèdent une identité locale stable et les identités distantes successives. Une transition Supabase → Pawnote ne doit pas effacer une réalisation locale, une matière corrigée ou les segments déjà travaillés. Les rapprochements ambigus restent séparés.

L’affichage regroupe toutes les durées de cours dans Cours et garde Révisions séparément. La durée mesurée associée à un cours remplace son créneau compté automatiquement. Une annulation, absence ou exclusion ne crée pas de crédit automatique. Les cours futurs ne sont pas comptés.

Le cache de portail `pronote-portal.json` est séparé du suivi et peut être récupéré à nouveau depuis PRONOTE. Les rubriques déjà lues restent accessibles hors connexion. Les jetons de connexion ne font pas partie de ce cache ni des sauvegardes : ils restent dans le trousseau privé de l’app. Les documents scolaires peuvent contenir des liens d’accès temporaires et restent des données privées.

Exporter une sauvegarde JSON dans Fichiers avant toute désinstallation, restauration ou changement de variante. Mettre à jour par-dessus l’app avec le même compte Sideloadly ; ne pas désinstaller pour renouveler la signature. Les quatre schémas partagent le même identifiant et se remplacent.
