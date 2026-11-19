# Son et Concentration : possibilités publiques iOS

Vérification documentaire du 19 novembre 2026. L’interface **Son et concentration** utilise les contrôles Apple de volume et de sortie audio. Elle ne démarre aucune session audio et ne publie aucune métadonnée Now Playing.

## Le lecteur média d’iOS

Le besoin est bien le lecteur universel du Centre de contrôle, quelle que soit l’origine du média. Ce lecteur est une interface privilégiée du système ; il n’existe pas de composant public permettant de l’intégrer dans une app iOS ordinaire ni d’en récupérer universellement le titre, la progression et les commandes.

Les API Apple consultées distinguent ces usages :

- `MPMusicPlayerController.systemMusicPlayer` pilote l’app Music et partage son état. Son nom ne désigne pas le lecteur universel du Centre de contrôle.
- `MPNowPlayingInfoCenter` permet de publier les métadonnées de la lecture de **notre** app.
- `MPRemoteCommandCenter` permet à **notre** lecteur de recevoir les commandes envoyées par le système et les accessoires. Il ne relaie pas ces commandes vers tous les lecteurs des autres apps.
- `MPVolumeView` fournit le véritable contrôle du volume système ; `AVRoutePickerView` fournit le choix de sortie audio, notamment AirPlay.

Cadenza présente donc le volume et la sortie, puis une courte aide pour accéder au vrai lecteur dans le Centre de contrôle. Aucune intégration Deezer n’est nécessaire. Les boutons lecture/pause, les pistes et la progression universels restent dans le lecteur iOS ; aucun bouton inopérant ni contenu fictif n’est affiché. La validation du volume et du routage réels demande un iPhone ; le simulateur ne suffit pas.

Sources Apple : [systemMusicPlayer](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/systemmusicplayer), [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter), [événements des lecteurs](https://developer.apple.com/documentation/mediaplayer/handling-external-player-events-notifications), [MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview), [AVRoutePickerView](https://developer.apple.com/documentation/avkit/avroutepickerview).

## Concentration sans quitter Cadenza

La version 0.5.0 **retire l’intégration Raccourcis**. Le début, la pause, la reprise et la fin d’une séance ne lancent plus d’URL `shortcuts://`. Les anciens réglages automatiques sont retirés au lancement ; un éventuel mode déjà actif reste intact. Les anciens callbacks sont absorbés sans effet. L’app ne tente pas de désactiver un mode lors de la migration, car cela recréerait précisément l’aller-retour refusé par l’utilisateur.

`INFocusStatusCenter` renseigne sur le statut partagé de Concentration et `SetFocusFilterIntent` adapte le comportement de notre app lorsqu’un mode change. Ces API ne constituent pas une commande publique d’activation globale de Ne pas déranger.

L’alternative native est la **programmation par app** dans Réglages iOS → Concentration → mode choisi → Ajouter une programmation → App → Cadenza. Elle est configurée une fois par l’utilisateur et s’exécute dans iOS, sans ouvrir Raccourcis. Elle suit l’utilisation de l’app, pas l’identité de notre chronomètre ; un fonctionnement identique à « uniquement pendant une séance » ne doit pas être promis. Une activation manuelle depuis le Centre de contrôle reste possible.

Sources Apple : [Focus et filtres d’app](https://developer.apple.com/documentation/appintents/focus), [INFocusStatusCenter](https://developer.apple.com/documentation/intents/infocusstatuscenter), [activer ou programmer un mode Concentration](https://support.apple.com/en-mt/guide/iphone/iph5c3f5b77b/ios).

## Parcours d’installation et nouveautés

La première installation comporte trois écrans : présentation, connexion PRONOTE, prise en main. Annuler la feuille de connexion conserve l’étape en cours ; l’utilisateur choisit explicitement de connecter son compte ou de le faire plus tard. Les autorisations de localisation ne sont jamais demandées par la simple présentation de ce parcours.

Après une mise à jour, trois écrans présentent les nouveautés. L’identifiant réel `version (build)` du bundle est enregistré lorsque le parcours est terminé. Il n’est pas stocké dans la sauvegarde des séances : une restauration de sauvegarde ne rejoue pas artificiellement une ancienne annonce. Un parcours interrompu reste proposé au prochain lancement. La version 0.5.0 présente la scolarité, les actions directes sur les devoirs et les séances sans aller-retour.

`IntroductionUITests` couvre l’annulation de la connexion, la poursuite manuelle, les trois nouveautés et le retour aux onglets. Les tests ordinaires ignorent les annonces avec `--uitesting` ; des arguments simulateur explicites permettent de tester chacun des deux parcours. Les résultats de compilation et de capture effectifs sont fournis par la CI, pas déduits de la présence de ces tests.
