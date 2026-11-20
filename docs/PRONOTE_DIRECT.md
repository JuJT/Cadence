# Connexion PRONOTE directe

Depuis Réglages → Connexion PRONOTE, choisir un établissement dans l’annuaire ou saisir son URL HTTPS. « Autour de moi » demande la localisation à ce moment seulement, avec une précision large ; la ville/adresse reste une alternative. Cadenza ne conserve pas la position. La requête de recherche est adressée à l’annuaire officiel PRONOTE, pas à Supabase.

Cette version utilise l’espace **Élève** et les identifiants PRONOTE directs. Les parcours ENT/EduConnect et QR ne sont pas présentés comme pris en charge. Saisir le mot de passe uniquement dans l’app sur l’iPhone. Si PRONOTE impose un code PIN ou une vérification de sécurité, suivre les champs affichés ; un nouveau mot de passe n’est demandé que si le serveur l’exige.

L’authentification et le chiffrement PRONOTE s’exécutent dans Pawnote, sur une file JavaScriptCore dédiée hors du fil principal. Les requêtes restent limitées à l’hôte HTTPS de l’établissement ; les redirections ne transmettent pas les identifiants à un autre hôte. Les cookies restent privés à cette connexion. Aucun code JavaScript provenant d’une page distante n’est exécuté dans le moteur.

Seul le jeton rotatif lié à cet appareil, son identifiant et les informations nécessaires à sa réutilisation sont enregistrés dans le trousseau privé. Le mot de passe n’est pas sauvegardé. Un jeton dont une requête consommante a été interrompue n’est pas réessayé aveuglément : une reconnexion peut alors être nécessaire. Une déconnexion ferme immédiatement les callbacks et retire les identifiants du trousseau ; un échec de suppression reste signalé.

L’app actualise au lancement, au retour au premier plan et sur demande, avec limitation des retours rapprochés. Elle ne promet pas une synchronisation d’arrière-plan permanente. Le cache reste disponible hors connexion et un échec réseau ne vide pas les données locales.

Le cahier de textes regroupe les cours par matière depuis la rentrée indiquée par l’établissement. Dans chaque matière, les séances apparaissent du premier cours au plus récent. Cadenza récupère les entrées par intervalles et ouvre les documents au choix d’une leçon. Les menus conservent leur sélecteur de semaine.

Les informations PRONOTE 2026 chargent leur détail à l’ouverture. La requête de lecture associe l’identifiant de l’article à celui du destinataire. Les paragraphes et pièces jointes apparaissent dans l’ordre de publication. Les contenus d’un cours sont liés par `lessonResourceID`. Les documents ouverts utilisent HTTPS. Un nouveau message, une réponse ou un accusé de réception exige une confirmation. Les devoirs validés dans Cadenza restent locaux.

Le calendrier Apple et Supabase ne participent plus à la récupération scolaire. Les anciennes données et les séances personnelles sont conservées, avec réparation des occurrences remplacées et des identités de devoirs. Les services Supabase existants restent inchangés et indépendants.
