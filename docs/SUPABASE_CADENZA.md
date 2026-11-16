# Synchronisation scolaire Cadenza 0.3

PRONOTE continue d’alimenter les tables existantes. Cadenza lit uniquement l’API `cadenza-school`, authentifiée par Supabase Auth. Le calendrier Apple et les anciens fichiers ICS ne sont plus des sources de synchronisation scolaire. Les séances personnelles ne sont pas envoyées à Supabase.

## Connexion initiale

Dans Réglages → Connexion PRONOTE via Supabase, utiliser l’adresse du compte propriétaire déjà autorisé côté serveur. Demander le message de connexion, puis coller le code ou copier le lien du message dans l’app **sans ouvrir ce lien au préalable**. Cela conserve les modèles d’e-mail et les réglages des autres services du projet. Le jeton est envoyé en POST au seul endpoint de vérification du projet. Les identifiants de session restent dans le trousseau privé de l’app ; ils sont exclus du résumé widgets, des sauvegardes et du dépôt.

L’application recharge les données au lancement, au premier plan et sur actualisation manuelle. Les retours rapprochés au premier plan sont limités à une lecture toutes les cinq minutes. Le cache persistant reste utilisable hors connexion ; une erreur ne vide aucun cours ni devoir. L’exécution en arrière-plan n’est pas garantie par iOS.

## Cours et devoirs

Les horaires sans fuseau de PRONOTE sont convertis en Europe/Paris par PostgreSQL, avant transmission de dates absolues à l’iPhone. Les identifiants `event_id` sont conservés, avec rapprochement prudent des anciennes occurrences et des changements d’identifiants. Les cours passés sont comptés automatiquement comme estimés, séparément des mesures. Un cours annulé, dispensé, absent ou retiré ne crédite pas de temps ; une mesure associée remplace son estimation.

Le classement des matières et les alias personnels restent prioritaires. La migration conserve les UUID, les séances et les notes. Une copie `cadence-before-school-v3.json` est conservée avant la première lecture d’une ancienne version, en plus de la sauvegarde atomique précédente. Les doublons absorbés restent en stockage avec une référence vers l’occurrence conservée.

Un devoir peut démarrer une révision ou être associé à une séance existante. Des segments attribuent uniquement le temps effectivement travaillé à chaque devoir, hors pauses ; ils ne s’ajoutent pas une deuxième fois aux totaux généraux. Valider un devoir détache son attribution active sans arrêter le chronomètre. La décision locale de réalisation reste distincte de `done` PRONOTE et survit aux synchronisations. Aucun état de devoir n’est renvoyé à PRONOTE.

Les pièces jointes ne deviennent cliquables que si les données contiennent réellement un lien HTTP(S). Les contenus de cours sont associés exclusivement par égalité de `lesson_resource_id` et `resource_id`. L’audit initial n’a trouvé aucune correspondance exacte dans les données actuelles ; aucun chapitre n’est inventé.

## Sécurité et déploiement

La migration crée uniquement `cadenza_private.reader_access`, sans accès `anon`, `authenticated` ou `service_role`. Les tables, politiques et tâches PRONOTE existantes restent inchangées. Le lecteur Edge utilise les droits serveur, mais vérifie d’abord le JWT auprès d’Auth, l’adresse vérifiée, la session encore présente et une autorisation privée. Les métadonnées utilisateur modifiables ne servent jamais à autoriser une lecture.

Le fichier de migration et la fonction sont versionnés ; l’adresse autorisée est provisionnée hors du dépôt public. La fonction utilise `postgres@3.4.5`, un accès en lecture seule, une limite de durée et des réponses sans cache. Aucun secret administratif n’est nécessaire dans l’app ou GitHub Actions.

Les tests réseau réels ont validé l’accès autorisé, les refus 401/403, l’inaccessibilité du schéma privé, puis la révocation de la session de test. Le rapport agrégé est dans `Verification/0.3.0/SUPABASE_AUDIT.json` ; il ne contient aucune ligne scolaire ni identifiant personnel. Les avertissements globaux d’Advisors relatifs à `pg_net` et à la protection des mots de passe ne sont pas modifiés : ce flux utilise des liens/codes d’e-mail, et les autres services du projet restent hors du périmètre. Les tables privées sans politique RLS sont volontairement fermées à tout accès client.

Références : [authentification Edge](https://supabase.com/docs/guides/functions/auth-headers), [liens et codes e-mail](https://supabase.com/docs/guides/auth/auth-email-templates), [politiques RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Advisors sécurité](https://supabase.com/docs/guides/database/database-linter).
