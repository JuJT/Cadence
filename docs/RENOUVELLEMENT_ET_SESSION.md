# Renouvellement, musique et concentration

## Renouvellement Sideloadly constaté le 16 novembre 2026

L’audit local en lecture seule a confirmé les éléments suivants : Sideloadly et son daemon fonctionnaient, une entrée de démarrage Windows existait, et l’installation Cadenza 0.2.0 était inscrite au renouvellement automatique, sans échec enregistré. Sa dernière mise à jour indiquée était le 16 novembre à 07:34, avec une validité de sept jours. Aucun compte Apple, identifiant d’appareil, profil, certificat ou mot de passe n’est conservé dans ce document ou dans le dépôt.

Cela automatise la **resignature** ; cela ne rend pas le certificat gratuit permanent. Selon la [FAQ officielle Sideloadly](https://sideloadly.io/faq), le PC doit pouvoir joindre l’iPhone en USB ou par Wi-Fi pour renouveler une app proche de l’expiration. Pour le Wi-Fi, le PC et l’iPhone doivent être sur le même réseau et la synchronisation Wi-Fi iTunes doit être configurée une fois. Un PC éteint ou un téléphone inaccessible pendant toute la période peut donc encore laisser l’app expirer.

À chaque mise à jour de Cadenza, conserver le même compte, le même identifiant d’application et l’option de renouvellement automatique dans Sideloadly, puis installer par-dessus. Le daemon remplace alors son IPA en cache. Ne pas désinstaller l’app pour renouveler sa signature. Le code iOS ne peut ni renouveler son propre profil Apple ni prolonger ses sept jours.

## Musique

La feuille **Musique et concentration** permet d’ajouter explicitement des fichiers audio depuis le sélecteur Fichiers. Cadenza garde une copie privée, une liste locale, les commandes lecture/pause, précédent/suivant, la position et le volume de son lecteur. Les pistes ne sont envoyées ni à Supabase ni au widget. Les fichiers audio ne font pas partie de la sauvegarde JSON des séances.

La session audio est activée uniquement lorsque l’utilisateur lance un fichier, avec les API publiques AVAudioPlayer, AVAudioSession et les commandes système de son propre lecteur. Le mode audio d’arrière-plan permet de continuer écran verrouillé ; il n’est pas utilisé pour maintenir artificiellement le chronomètre en exécution. Le chronomètre reste fondé sur les dates persistées.

Le bouton Deezer ouvre son lien public ; une piste Cadenza en cours est mise en pause. La navigation peut ouvrir Deezer ou son site selon les associations de l’iPhone. Les commandes de Deezer et de Fichiers déjà lancées restent dans le Centre de contrôle et sur l’écran verrouillé. Aucun titre global fictif ni bouton prétendant piloter une autre app n’est affiché : [systemMusicPlayer contrôle l’app Music](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/systemmusicplayer), tandis que [MPRemoteCommandCenter reçoit les commandes du lecteur de l’app](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter).

## Concentration : une configuration initiale iOS

iOS expose le statut Concentration en lecture et permet de réagir à ses changements, mais ne fournit pas à Cadenza de setter public pour activer Ne pas déranger. L’intégration utilise le [schéma d’URL Raccourcis documenté par Apple](https://support.apple.com/en-euro/guide/shortcuts/apd624386f42/10.0/ios/27), avec [retour x-callback-url](https://support.apple.com/en-euro/guide/shortcuts/apdcd7f20a6f/10.0/ios/27).

Créer une fois dans Raccourcis **Cadenza Concentration**, ou choisir son nom dans la feuille :

1. Si **Entrée du raccourci** vaut `on`, obtenir la concentration actuelle. Si un mode est déjà actif, ne pas le modifier et terminer avec une action Texte contenant `kept`.
2. Sinon, activer **Ne pas déranger** jusqu’à désactivation, puis terminer cette branche avec le texte `enabled`.
3. Si l’entrée vaut `off`, désactiver spécifiquement **Ne pas déranger**, puis terminer avec le texte `disabled`.

Ne pas ajouter d’action Ouvrir l’app en fin de raccourci : Cadenza fournit le retour automatique. Activer ensuite **Appeler mon raccourci automatiquement** dans l’app. Le raccourci est appelé au début d’une nouvelle séance chronométrée, de cours ou de révision, et à sa fin. Une pause ne le désactive pas. Une restauration au lancement mémorise la séance sans ouvrir Raccourcis de manière inattendue.

Le résultat `enabled` signifie que le raccourci a déclaré avoir activé le mode ; Cadenza ne prétend pas avoir vérifié directement le réglage système. `kept` indique qu’un mode préexistant a été conservé : Cadenza ne demandera pas sa désactivation à la fin. Une erreur ou une annulation n’affecte jamais le chronomètre. L’iPhone peut demander une autorisation initiale et l’app ne peut ni créer ce raccourci personnel ni accorder ses autorisations à la place de l’utilisateur.

## Widgets après resignature

Le transport ne reconstruit plus un groupe de trousseau en supposant que seul son préfixe a changé. Il lit les groupes exacts dans les métadonnées XML de la signature de son propre exécutable, puis utilise aussi les candidats par défaut et du profil. Cette lecture est bornée et ne valide pas la signature : Security vérifie chaque destination. Un format non pris en charge, notamment DER seul, utilise les autres candidats sans inventer d’autorisation. Le widget recherche son service et son compte exacts dans tous ses groupes autorisés et choisit la copie valide la plus récente. Le diagnostic ne révèle aucun préfixe personnel et ne confond pas publication privée et lecture par un widget.

Le parseur de format public est testé sur des exécutables fictifs : groupes renommés, architectures FAT32/FAT64, données tronquées, offsets malformés et limites de ressources. Ces tests n’accèdent pas au trousseau du runner. Références de format : [Mach-O Apple](https://github.com/apple-oss-distributions/cctools/blob/main/include/mach-o/loader.h), [blobs de signature Apple](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h).

La variante Extensions demande deux groupes à l’app : son identifiant privé en premier, puis le groupe de résumé. L’extension ne demande que le groupe de résumé. Les jetons de connexion Supabase utilisent explicitement le groupe privé effectif de l’app, jamais le groupe partagé. La préparation de l’IPA et le diagnostic `authIsolation` vérifient cette séparation dans les métadonnées des exécutables ; les signatures ad-hoc restent des modèles sans certificat ni profil Apple. La resignature Sideloadly doit adapter les identifiants et conserver les droits réels : ce point ne peut pas être garanti par la présence d’un fichier `CadenceSigningIntent.plist`.

La photo « Relier mes données » confirme qu’aucun résumé utilisable n’a été lu par le widget de l’installation précédente. L’iPhone n’était pas connecté au PC pendant cet audit ; les droits effectifs de sa signature ne peuvent donc pas être déclarés validés. Le reçu **Dernière lecture réelle par un widget** reste le contrôle matériel déterminant après installation. Un exécutable signé sans groupe commun ne peut pas contourner iOS ; aucune base scolaire publique ni réseau dans les widgets n’est ajouté pour masquer ce problème.
