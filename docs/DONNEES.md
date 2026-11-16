# Données et sauvegardes

## Stockage

Aucune donnée scolaire réelle n’est fournie dans l’installation. Après connexion, les cours et devoirs sont lus depuis l’API privée Supabase et conservés en cache. Les séances personnelles, notes et alias restent sur l’iPhone et ne sont pas envoyés au serveur. Les jetons sont dans le trousseau privé, hors du JSON et du résumé widgets.

L’écriture est atomique. La génération précédente est conservée. Si le fichier ne peut pas être lu ou validé, il n’est pas écrasé silencieusement ; l’application bloque les modifications et permet une restauration explicite. Une réinstallation après suppression peut effacer toutes les données : le fichier local précédent n’est pas une sauvegarde externe.

## JSON

Depuis Réglages, exporter puis enregistrer le JSON dans Fichiers ou un emplacement choisi via la feuille système. Le document version 3 contient `schemaVersion`, `exportedAt`, `subjects`, `sessions`, `occurrences` `settings`, `homework`, `courseContents` et `schoolSync`. Les identifiants UUID restent stables ; les associations session/occurrence sont bidirectionnelles. Les dates représentent des instants UTC. La session active et ses pauses et ses segments par devoir font partie de la sauvegarde.

L’import **remplace l’état courant après confirmation** ; ce n’est pas une fusion entre deux appareils. Avant remplacement, la génération locale antérieure est conservée. Le fichier est validé en entier : taille maximale 20 Mo, version connue, UUID uniques, références existantes, une seule session active, ordre temporel et associations cohérentes. En cas de refus, l’état courant reste intact. Les formats v1 et v2 sont migrés vers v3 ; aucune donnée fictive du kit n’est importée au lancement. La première lecture d’un ancien stockage conserve aussi une copie cadence-before-school-v3.json avant modification.

Une sauvegarde contient le cache scolaire, des devoirs et des notes privées : ne la partager qu’avec les destinataires choisis. Les workflows de compilation ne doivent recevoir aucun export réel.

## CSV

Le CSV UTF-8 avec BOM comporte : identifiant, type, matière, début et fin UTC, secondes actives, origine, statut, chapitre, notes et cours associé. Les guillemets et retours à la ligne sont échappés. Un texte susceptible d’être interprété comme formule de tableur est neutralisé. Une occurrence liée à une séance n’est pas exportée une seconde fois avec son estimation. Les cours planifiés peuvent être présents avec zéro seconde et un statut explicite.

Le CSV est destiné à la consultation et ne sert pas à restaurer la base. Le JSON est la sauvegarde complète.

## Comptabilisation

- Les cours scolaires terminés sont automatiquement estimés, sauf annulation, dispense, absence ou exclusion locale ; aucune confirmation systématique n’est demandée.
- Un cours passé estimé est distinct d’un cours confirmé ou mesuré.
- Une mesure associée remplace l’estimation, même si sa durée diffère.
- Les révisions restent manuelles et comptent séparément.
- Un événement source supprimé ne supprime jamais une séance ou ses notes.
- La suppression explicite d’une séance liée ne fait pas réapparaître automatiquement un ancien crédit estimé.

Conserver un export avant changement de variante, renouvellement de signature, restauration ou désinstallation. Le renouvellement à sept jours doit se faire par-dessus la même application avec la même identité ; sa conservation des données exige un essai réel.
