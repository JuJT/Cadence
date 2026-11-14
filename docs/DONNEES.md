# Données et sauvegardes

## Stockage

Aucune donnée scolaire n’est fournie dans l’installation. Les matières initiales sont des noms génériques modifiables. Les séances, notes, choix de calendriers et alias restent dans le conteneur local de l’application. Aucun serveur, télémétrie, compte Google OAuth, CloudKit ou identifiant Apple n’est utilisé par le code.

L’écriture est atomique. La génération précédente est conservée. Si le fichier ne peut pas être lu ou validé, il n’est pas écrasé silencieusement ; l’application bloque les modifications et permet une restauration explicite. Une réinstallation après suppression peut effacer toutes les données : le fichier local précédent n’est pas une sauvegarde externe.

## JSON

Depuis Réglages, exporter puis enregistrer le JSON dans Fichiers ou un emplacement choisi via la feuille système. Le document version 2 contient `schemaVersion`, `exportedAt`, `subjects`, `sessions`, `occurrences` et `settings`. Les identifiants UUID restent stables ; les associations session/occurrence sont bidirectionnelles. Les dates représentent des instants UTC. La session active et ses pauses font partie de la sauvegarde.

L’import **remplace l’état courant après confirmation** ; ce n’est pas une fusion entre deux appareils. Avant remplacement, la génération locale antérieure est conservée. Le fichier est validé en entier : taille maximale 20 Mo, version connue, UUID uniques, références existantes, une seule session active, ordre temporel et associations cohérentes. En cas de refus, l’état courant reste intact. Le format v1 du kit est migré vers v2 ; aucune donnée fictive du kit n’est importée au lancement.

Une sauvegarde contient des noms et identifiants de calendriers ainsi que des notes privées : partager le fichier seulement avec les destinataires choisis. Les workflows de compilation n’ont pas besoin de vos exports réels et ne doivent pas en recevoir.

## CSV

Le CSV UTF-8 avec BOM comporte : identifiant, type, matière, début et fin UTC, secondes actives, origine, statut, chapitre, notes et cours associé. Les guillemets et retours à la ligne sont échappés. Un texte susceptible d’être interprété comme formule de tableur est neutralisé. Une occurrence liée à une séance n’est pas exportée une seconde fois avec son estimation. Les cours planifiés peuvent être présents avec zéro seconde et un statut explicite.

Le CSV est destiné à la consultation et ne sert pas à restaurer la base. Le JSON est la sauvegarde complète.

## Comptabilisation

- Le réglage d’estimation automatique est désactivé tant que vous ne l’activez pas explicitement.
- Un cours passé estimé est distinct d’un cours confirmé ou mesuré.
- Une mesure associée remplace l’estimation, même si sa durée diffère.
- Les révisions restent manuelles et comptent séparément.
- Un événement source supprimé ne supprime jamais une séance ou ses notes.
- La suppression explicite d’une séance liée ne fait pas réapparaître automatiquement un ancien crédit estimé.

Conserver un export avant changement de variante, renouvellement de signature, restauration ou désinstallation. Le renouvellement à sept jours doit se faire par-dessus la même application avec la même identité ; sa conservation des données exige un essai réel.
