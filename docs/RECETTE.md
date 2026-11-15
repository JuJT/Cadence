# Recette et limites de validation

Les tests matériels restent « À faire » tant qu’un retour utilisateur ou une preuve pertinente n’est pas reçu. Un workflow réussi ne les valide pas.

| Niveau | Vérification | Résultat attendu | État initial |
|---|---|---|---|
| Noyau | Deux démarrages successifs | Une seule séance active | Voir VERIFICATION.md |
| Noyau | 12:00 départ, 12:15 pause, 12:20 reprise, 12:45 fin | 40 minutes actives | Voir VERIFICATION.md |
| Noyau | Séance 23:50–00:10 | 10 minutes par jour | Voir VERIFICATION.md |
| Noyau | Changement d’heure été/hiver | Durée absolue exacte et totaux cohérents | Voir VERIFICATION.md |
| Noyau | JSON aller-retour, pause/restauration | Identifiants et segments préservés | Voir VERIFICATION.md |
| Noyau | Répéter le même import | Même occurrence, pas de double crédit | Voir VERIFICATION.md |
| Noyau | Récurrence et occurrence déplacée | Occurrences distinctes, identité conservée | Voir VERIFICATION.md |
| Noyau | Alias ambigus / titre révision | À vérifier / non importé comme cours | Voir VERIFICATION.md |
| Noyau | 60 min estimées puis mesure liée 45 min | 45 min mesurées et zéro estimation | Voir VERIFICATION.md |
| Noyau | Événement supprimé, séance conservée | Notes et durée maintenues | Voir VERIFICATION.md |
| CI | Compilation device et inventaire IPA | App arm64 et extension selon variante | Réussi : quatre IPA |
| Simulateur iPhone | Navigation et minuteur sans Calendrier | Démarrer, pause, reprise, fin ; trois onglets accessibles | Réussi |
| Simulateurs | Captures natives | Images XCTest en clair/sombre et iPad paysage | Neuf images contrôlées |
| iPhone | Refuser Calendrier | Création manuelle entièrement utilisable | À faire |
| iPhone | Choisir calendrier Google visible dans Apple | Import sans connexion Google supplémentaire | À faire |
| iPhone | App fermée pendant session / pause | Restauration correcte | À faire |
| iPhone | Widget et Live Activity / Island | Présence après resignature et durée correcte | À faire |
| iPhone | Raccourcis : démarrer, pause, reprendre, fin, totaux | Actions visibles, retours réels | À faire |
| iPhone | Renouveler par-dessus l’app | Données conservées | À faire |
| iPhone/iPad | Sombre, gros texte, réduire transparence/mouvement | Commandes lisibles et accessibles | À faire |
| Simulateur iPad | Vue en colonnes et rotation | Navigation en paysage | Réussi ; installation physique à faire |
| iPad MDM | Installation autorisée par l’établissement | Dépend du MDM | Non garanti |
| Watch | Live Activity relayée dans Smart Stack | Dépend de watchOS et de la signature | À faire |

Le guide [SPIKE_IPHONE.md](SPIKE_IPHONE.md) réduit la première validation à six essais. L’application watchOS dédiée n’est pas incluse dans la V1.
