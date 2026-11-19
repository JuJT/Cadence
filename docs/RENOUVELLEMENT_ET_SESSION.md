# Renouvellement de signature et nouvelles versions

## Situation vérifiée le 19 novembre 2026

L’audit local a trouvé le daemon Sideloadly actif et son démarrage Windows configuré. Cadenza 0.4.0 est inscrite au renouvellement automatique (`one_off=0`), avec extensions conservées (`drop_plugins=0`). Le cache annonce une validité de sept jours et un seuil de renouvellement à 96 heures. Sa dernière mise à jour enregistrée date du 18 novembre à 19 h 09, sans erreur enregistrée et avec un compteur d’échecs à zéro. Ce constat ne prouve pas un prochain renouvellement ni une disponibilité permanente du PC et de l’iPhone.

Le renouvellement automatique **est donc déjà configuré**. Le PC doit rester disponible et pouvoir joindre l’iPhone en USB ou par le Wi-Fi préalablement configuré. Selon la FAQ officielle Sideloadly, le daemon tente de renouveler les apps proches de leur expiration lorsqu’il détecte l’appareil.

Pour remplacer l’IPA par une nouvelle version, l’installer par-dessus avec **le même compte Apple, le même bundle ID et l’option d’auto-renouvellement activée**. Sideloadly remplace alors aussi la version qu’il conserve pour les renouvellements. Ne pas désinstaller l’app pour effectuer cette opération ; les données locales pourraient être supprimées. Exporter une sauvegarde avant un remplacement reste utile.

Source : [FAQ officielle Sideloadly — auto-renouvellement, nouvelles IPA et conservation des données](https://sideloadly.io/faq).

## Mise à jour à distance

La compilation distante GitHub Actions produit les IPA et des rapports dans une release **brouillon**. Cela permet de récupérer une version à distance, mais ne crée pas un canal d’installation automatique sur iPhone. Le code Swift embarqué doit être compilé et signé de nouveau ; une mise à jour du texte des annonces n’effectue pas cette opération. L’app ne possède aucun identifiant Apple ni certificat permettant de prolonger sa propre signature.

Les options concrètes sont :

| Canal | Nouvelles versions | Renouvellement et conditions |
|---|---|---|
| Sideloadly actuel | Charger la nouvelle IPA une fois sur le PC ; installation ensuite possible en USB ou Wi-Fi configuré | Daemon déjà configuré ; PC et iPhone joignables nécessaires, compte et bundle stables |
| TestFlight | Téléchargement distant et mises à jour automatiques activables sur iPhone | Compte Apple Developer Program, signature de distribution et canal App Store Connect à mettre en place ; chaque build de test est utilisable jusqu’à 90 jours |
| App Store | Distribution distante et mises à jour par le mécanisme système | Compte développeur, configuration de distribution et validation Apple |

Cette livraison conserve le canal Sideloadly existant. Elle ne crée ni abonnement développeur, ni publication App Store, ni accès TestFlight. Réglages → Mises à jour recherche les versions publiques. Les releases brouillon CI ne sont pas visibles par ce vérificateur anonyme ; dans ce cas, il indique explicitement qu’aucune mise à jour publique n’est proposée. La recherche ne remplace pas l’installation et la resignature de la nouvelle IPA.

Sources : [TestFlight Apple — mises à jour automatiques et durée des builds](https://testflight.apple.com/), [TestFlight pour développeurs](https://developer.apple.com/testflight/), [compte développeur Apple](https://developer.apple.com/help/account/basics/about-your-developer-account/), [mises à jour automatiques App Store](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/).

## Son et concentration

La version 0.5.0 retire les appels à Raccourcis : aucune ouverture de Raccourcis n’a lieu au début ou à la fin des séances. Une programmation native du mode Concentration par app peut être choisie dans les réglages iOS. Le lecteur universel reste celui du Centre de contrôle ; Cadenza présente les contrôles publics de volume et d’AirPlay. Voir [les possibilités et limites vérifiées](CAPACITES_NATIVES.md).
