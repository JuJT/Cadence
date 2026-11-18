# Architecture de Cadenza 0.4

PRONOTE ↔ Pawnote embarqué sur l’iPhone → service Swift ordonné → cache scolaire local → domaine CadenceCore → interface SwiftUI et résumé minimal des extensions.

Le moteur JavaScriptCore ne charge que le bundle produit depuis `Runtime/src` et les dépendances épinglées. Sa file série n’est pas MainActor. Foundation fournit le réseau privé, Security l’entropie et le trousseau privé. Les jetons sont stockés avant l’étape suivante du protocole ; les callbacks tardifs sont fermés après déconnexion. Le pont borne requêtes, réponses, minuteurs et attentes, sans chaîne illimitée de travaux.

AppStore reste le seul écrivain du suivi personnel. La réconciliation scolaire travaille sur une copie hors du fil principal et vérifie la version d’état avant publication, afin de préserver une pause ou une fin de séance survenue entre-temps. Une mutation inchangée ne réécrit pas le fichier. Le cache des rubriques PRONOTE utilise un acteur séparé et des écritures ordonnées.

CadenceCore reste indépendant des frameworks Apple. Il conserve les identités locales, les associations de cours, les segments de devoir et les sauvegardes anciennes. Le résumé des widgets ne contient ni session PRONOTE ni base complète. Les Live Activities utilisent les dates de séance et ne maintiennent pas une lecture audio artificielle.

L’intégration EventKit et le lecteur Supabase historiques restent des sources de compatibilité, mais aucun des deux n’est appelé pour synchroniser les cours de cette version. Les services hébergés préexistants restent inchangés. Les identifiants d’app et chemins de stockage demeurent stables pour l’installation par-dessus l’app actuelle.
