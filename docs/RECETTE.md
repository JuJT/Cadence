# Recette et limites de validation

Le programme d’essai initial a été validé par l’utilisateur sur son iPhone. Ce retour ne valide pas automatiquement Cadenza 0.4.0, la connexion directe PRONOTE ou le partage des widgets après resignature. Le [rapport de vérification](VERIFICATION.md) distingue les tests automatisés, la démo publique et les essais sur appareil. La version iPad est abandonnée.

| Niveau | Vérification | Résultat attendu | État initial |
|---|---|---|---|
| Noyau | Deux démarrages successifs | Une seule séance active | Voir VERIFICATION.md |
| Noyau | 12:00 départ, 12:15 pause, 12:20 reprise, 12:45 fin | 40 minutes actives | Voir VERIFICATION.md |
| Noyau | Séance 23:50–00:10 | 10 minutes par jour | Voir VERIFICATION.md |
| Noyau | Changement d’heure été/hiver | Durée absolue exacte et totaux cohérents | Voir VERIFICATION.md |
| Noyau | JSON aller-retour, pause/restauration | Identifiants et segments préservés | Voir VERIFICATION.md |
| Noyau | Répéter une synchronisation scolaire | Même occurrence, pas de double crédit | Voir VERIFICATION.md |
| Noyau | Récurrence et occurrence déplacée | Occurrences distinctes, identité conservée | Voir VERIFICATION.md |
| Noyau | Alias ambigus / titre révision | À vérifier / non importé comme cours | Voir VERIFICATION.md |
| Noyau | Cours automatique de 60 min puis mesure liée de 45 min | 45 min dans Cours, sans double crédit | Voir VERIFICATION.md |
| Noyau | Événement supprimé, séance conservée | Notes et durée maintenues | Voir VERIFICATION.md |
| CI | Compilation device et inventaire IPA | App arm64 et extension selon variante | Réussi : quatre IPA |
| Simulateur iPhone | Navigation et minuteur sans Calendrier | Démarrer, pause, reprise, fin ; cinq onglets accessibles | Voir VERIFICATION.md |
| Simulateur iPhone | Captures natives | Images XCTest en clair/sombre et grandes polices | Voir VERIFICATION.md |
| iPhone | Connexion PRONOTE : annuaire par ville, position facultative ou URL | Authentification élève, cours/devoirs/portail et cache disponibles | Démo publique + essais avec le compte réel à faire |
| iPhone | Synchroniser après avoir travaillé un devoir ou chronométré un cours | Travail local conservé, aucun doublon ni double crédit | Noyau et moteur testés ; contrôle du compte réel à faire |
| iPhone | Comparer Religion après actualisation | Une occurrence valide par séance, exclusions locales conservées | Noyau testé ; contrôle du relevé réel à faire |
| iPhone | Autoriser Apple Music, choisir deux morceaux, passer au suivant | Morceau et état de Musique mis à jour | À essayer sur iPhone |
| iPhone | Ouvrir un lien Spotify puis connecter un compte Premium | Lecteur intégré, titre et commandes sur l’appareil Spotify Connect actif | À essayer avec un compte autorisé |
| iPhone | Changer plusieurs fois d’onglet et prolonger une séance | Navigation stable, enregistrement continu, chauffe à observer | Parcours simulateur réussis ; mesure sur appareil à faire |
| iPhone | App fermée pendant session / pause | Restauration correcte | À faire |
| iPhone | Widget et Live Activity / Island | Présence après resignature et durée correcte | À faire |
| iPhone | Raccourcis : démarrer, pause, reprendre, fin, totaux | Actions visibles, retours réels | À faire |
| iPhone | Renouveler par-dessus l’app | Données conservées | À faire |
| iPhone | Sombre, gros texte, réduire transparence/mouvement | Commandes lisibles et accessibles | Parcours simulateur + contrôle physique selon réglages personnels |
| Watch | Live Activity relayée dans Smart Stack | Dépend de watchOS et de la signature | À faire |

Le guide [SPIKE_IPHONE.md](SPIKE_IPHONE.md) décrit les six essais historiques du premier spike ; ses parcours de calendrier ne constituent plus le flux scolaire de la 0.4.0. L’application watchOS dédiée n’est pas incluse dans cette livraison.
