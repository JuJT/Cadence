# Connexion à PRONOTE

Le parcours est proposé à la première ouverture et dans **Réglages → Connexion PRONOTE**. Il peut être passé pendant la configuration initiale.

1. Pour trouver l’établissement, chercher une ville ou un code postal, choisir « Autour de moi », ou coller l’adresse HTTPS de l’espace **Élève** PRONOTE. La localisation approximative est demandée uniquement pour « Autour de moi ». La recherche passe par l’annuaire Index Éducation.
2. Après avoir choisi l’établissement, saisir ses identifiants PRONOTE ou choisir l’ENT. L’ENT/EduConnect s’ouvre sur la page de connexion habituelle si le portail permet la validation pour PRONOTE mobile. Le nom de domaine de la page de connexion apparaît en haut.
3. Pour utiliser un QR code, ouvrir son espace élève PRONOTE sur un autre appareil, générer le QR avec le bouton prévu à cet effet, le scanner et saisir le code à quatre chiffres choisi lors de la génération. Cette méthode reste accessible quand l’ENT direct est indisponible.

Si PRONOTE demande une vérification de sécurité supplémentaire, suivre les champs affichés. L’écran Web ENT utilise un stockage éphémère. Seule une validation mobile émise depuis la page PRONOTE de l’établissement choisi est transmise au moteur de connexion. Le QR et son code restent en mémoire le temps de la connexion.

L’authentification et le chiffrement PRONOTE s’exécutent dans Pawnote, sur une file JavaScriptCore dédiée hors du fil principal. Les requêtes restent limitées à l’hôte HTTPS de l’établissement ; les redirections ne transmettent pas les identifiants à un autre hôte. Les cookies restent privés à cette connexion. Aucun code JavaScript provenant d’une page distante n’est exécuté dans le moteur.

Seul le jeton rotatif lié à cet appareil, son identifiant et les informations nécessaires à sa réutilisation sont enregistrés dans le trousseau privé. Le mot de passe n’est pas sauvegardé. Un jeton dont une requête consommante a été interrompue n’est pas réessayé aveuglément : une reconnexion peut alors être nécessaire. Une déconnexion ferme immédiatement les callbacks et retire les identifiants du trousseau ; un échec de suppression reste signalé.

L’app actualise au lancement, au retour au premier plan et sur demande, avec limitation des retours rapprochés. Elle ne promet pas une synchronisation d’arrière-plan permanente. Le cache reste disponible hors connexion et un échec réseau ne vide pas les données locales.

Le cahier de textes regroupe les cours par matière depuis la rentrée indiquée par l’établissement. Dans chaque matière, les séances apparaissent du premier cours au plus récent. Cadenza récupère les entrées par intervalles et ouvre les documents au choix d’une leçon. Les menus conservent leur sélecteur de semaine.

Les informations PRONOTE 2026 chargent leur détail à l’ouverture. La requête de lecture associe l’identifiant de l’article à celui du destinataire. Les paragraphes et pièces jointes apparaissent dans l’ordre de publication. Les contenus d’un cours sont liés par `lessonResourceID`. Les documents ouverts utilisent HTTPS. Un nouveau message, une réponse ou un accusé de réception exige une confirmation. Les devoirs validés dans Cadenza restent locaux.

Le calendrier Apple et Supabase ne participent plus à la récupération scolaire. Les anciennes données et les séances personnelles sont conservées, avec réparation des occurrences remplacées et des identités de devoirs. Les services Supabase existants restent inchangés et indépendants.
