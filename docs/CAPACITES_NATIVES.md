# Musique dans Cadenza

Depuis Réglages → Musique ou pendant une séance, choisissez Apple Music ou Spotify. Le dernier service sélectionné est mémorisé sur l’iPhone.

## Apple Music

Autorisez l’accès à la bibliothèque lors du premier appui sur **Autoriser Apple Music**. Cadenza affiche le morceau communiqué par Musique et pilote sa file de lecture. Vous pouvez passer à la piste suivante ou précédente, mettre en pause, reprendre et sélectionner des morceaux dans le sélecteur de bibliothèque d’iOS. Ils continuent à jouer dans l’app Musique quand Cadenza passe en arrière-plan.

Cette intégration utilise le lecteur système de l’app Musique et l’autorisation de bibliothèque iOS. Les éléments disponibles et les métadonnées dépendent de la bibliothèque et de l’abonnement de l’utilisateur. [Lecteur de Musique](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller/systemmusicplayer) · [Sélecteur de bibliothèque](https://developer.apple.com/documentation/mediaplayer/mpmediapickercontroller)

## Spotify

**Avec un lien partagé**, collez un lien open.spotify.com vers un morceau, une playlist, un album ou un épisode dans « Lire un lien Spotify ». Le lecteur officiel s’affiche dans Cadenza. Le dernier lien est mémorisé. Spotify détermine si le lecteur propose le titre complet ou un extrait. [Lecteur intégré Spotify](https://developer.spotify.com/documentation/embeds/tutorials/creating-an-embed) · [Disponibilité des extraits](https://developer.spotify.com/documentation/embeds/tutorials/troubleshooting)

**Avec Spotify Connect**, le lecteur contrôle la lecture du compte Spotify Premium, y compris sur un autre appareil Connect actif. Cette distribution personnelle demande d’enregistrer une application dans le tableau de bord développeur Spotify.

1. Créez l’application avec le produit **Web API**. Dans la liste des URI de redirection, ajoutez exactement `http://127.0.0.1/spotify/callback`. Spotify autorise un port dynamique pour une adresse de bouclage enregistrée sans port.
2. En mode développement, utilisez un compte autorisé dans les réglages de cette application. Le propriétaire de l’application doit remplir les conditions du mode développement Spotify.
3. Ouvrez **Musique → Spotify → Configurer Spotify Connect**. Collez le **Client ID** public, puis touchez **Connecter mon compte**. L’autorisation se déroule dans le navigateur système. Le secret client n’est demandé à aucun moment.
4. Lancez la lecture sur un appareil Spotify Connect. Cadenza affiche le titre et la destination et permet la pause, la reprise et le changement de piste. Le bouton **Actualiser le lecteur** relit l’état. **Déconnecter Spotify** supprime la connexion locale.

L’autorisation utilise PKCE avec un état aléatoire et l’écoute temporaire de la seule adresse de bouclage. Le jeton de renouvellement est conservé dans le groupe privé du trousseau de l’app sur cet iPhone. Le jeton d’accès reste en mémoire. [Configuration Spotify](https://developer.spotify.com/dashboard) · [PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow) · [URI de retour](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri) · [Conditions du mode développement](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide) · [Commandes de lecture](https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback)

Les essais avec une bibliothèque Apple Music et un compte Spotify Premium nécessitent l’iPhone et l’accord du titulaire du compte.
