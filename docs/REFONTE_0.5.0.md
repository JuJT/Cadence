# Cadenza 0.5.0 — la scolarité au quotidien

Les notes, informations et absences sont accessibles directement depuis l’accueil. L’onglet Cours donne accès aux contenus rangés par matière, puis par date. Les onglets natifs, les surfaces Liquid Glass et le suivi des séances sont conservés.

## Corrections PRONOTE

- Les consignes HTML des devoirs, leçons et informations deviennent du texte lisible. Le traitement s’applique aussi aux anciens caches, sans charger de contenu web ni exécuter du code.
- Chaque carte de devoir contient Valider et Démarrer ; une séance existante peut être conservée et associée au devoir. La réalisation reste locale à Cadenza, comme dans les versions précédentes.
- La période actuelle utilise le réglage de l’écran PRONOTE concerné. La période annuelle qui recouvre le trimestre ne prend plus sa place par hasard.
- Les moyennes officielles sont prioritaires. Si elles ne sont pas fournies, Cadenza affiche séparément une moyenne indicative calculée sur les notes disponibles : coefficients des devoirs, barèmes, notes non numériques et bonus traités explicitement. Les matières ont le même poids pour l’estimation générale. Ce calcul peut différer de celui du professeur ou du bulletin.
- L’adaptation des informations PRONOTE 2026 reconnaît les catégories personnelles et les natures présentes simultanément. L’absence de métadonnées facultatives d’accusé de réception ne bloque plus le texte. Aucun accusé n’est envoyé sans les références nécessaires et une confirmation explicite.
- Les absences présentent d’abord leur intervalle, la durée de cours manquée, le motif et les états Justifiée / Régularisée. Les retards et observations restent séparés.

## Mise en route et fonctions iOS

La première installation guide la présentation, la connexion PRONOTE puis la prise en main. Après changement de version ou de build, trois écrans présentent les nouveautés. Annuler la connexion laisse l’utilisateur dans le parcours.

Le raccourci Concentration est retiré : aucun départ vers une autre app au début ou à la fin d’une séance. Une programmation Concentration par app peut être configurée dans iOS ; elle suit l’usage de Cadenza, pas exactement le chronomètre.

Le lecteur universel du Centre de contrôle n’est pas exposé comme composant intégrable par les API publiques Apple. Cadenza fournit le volume système et AirPlay, ainsi que l’accès expliqué au véritable lecteur iOS. Voir les [capacités et sources Apple](CAPACITES_NATIVES.md).

Réglages → Mises à jour recherche la dernière version **publiée** sur GitHub. Un brouillon CI n’est pas proposé au public. Une nouvelle IPA doit être installée avec Sideloadly ; l’app ne peut pas se remplacer ni prolonger elle-même sa signature Apple. Le renouvellement automatique est déjà configuré sur le PC audité le 19 novembre 2026. Voir [installation et renouvellement](RENOUVELLEMENT_ET_SESSION.md). TestFlight permettrait des versions à distance après configuration Apple Developer et App Store Connect.

## Vérification

Les tests du moteur couvrent les périodes par écran, les moyennes et les réponses PRONOTE 2026. Les tests natifs couvrent les devoirs, les ressources par matière, les absences, les informations, le son et les parcours de mise en route. Les données scolaires des tests sont fictives ; un succès en simulateur ne valide pas le compte personnel, le matériel audio ou la resignature sur iPhone. Les résultats effectifs sont fournis avec le livrable.
