# Widgets de Cadenza

Cadenza pour iPhone propose quatre widgets utilisant uniquement vos données locales :

- **Aujourd’hui** : cours mesurés ou confirmés, révisions et estimations séparées ; petit ou moyen format.
- **Ma semaine** : sept barres quotidiennes, mêmes catégories et matière la plus travaillée ; petit ou moyen format.
- **Prochain cours** : matière normalisée, date et horaire du prochain créneau synchronisé ; petit ou moyen format.
- **Temps d’étude** : résumé du jour sur l’écran verrouillé, en ligne ou rectangle.

Les valeurs sont un résumé daté publié par l’application. Les widgets se rafraîchissent selon le budget d’iOS ; leur compteur n’est pas un chronomètre continu. La Live Activity conserve le chronomètre de la séance. Ouvrir Cadenza actualise le résumé et demande le rechargement des widgets. Les cours futurs ne comptent pas dans les durées. Les estimations sont représentées séparément.

## Installation Windows et compte gratuit

Utiliser **Cadenza-iPhone-0.2.0.ipa** (variante technique `CadenceExtensions`), conserver les extensions dans Sideloadly, le même compte Apple et l’identifiant utilisé pour l’installation existante. Ne pas désinstaller l’application pour la mettre à jour.

Cette variante demande **Keychain Sharing**, que le tableau Apple indique disponible pour un compte Apple Developer gratuit. L’application et son extension utilisent le groupe commun `com.cadence.study.widget-summary`, préfixé par le véritable identifiant de signature. Le système vérifie l’autorisation de ce groupe. Aucun serveur, compte Cadenza, accès hors du bac à sable ou identifiant Apple enregistré dans le code n’est utilisé. Seul un petit résumé de statistiques et de prochains cours est partagé ; la base d’étude complète reste dans l’application.

**La capacité Apple et sa conservation par Sideloadly sont deux vérifications distinctes.** La documentation publique de Sideloadly ne garantit pas le traitement de ce groupe personnalisé. Après installation :

1. Ouvrir Cadenza et vérifier les durées dans Statistiques.
2. Ajouter un widget Cadenza depuis l’écran d’accueil et choisir Aujourd’hui, Ma semaine ou Prochain cours.
3. Revenir dans les réglages de Cadenza, rubrique diagnostic des intégrations. « Résumé publié » confirme l’écriture par l’app ; **« Dernière lecture réelle par un widget »** confirme que l’extension a lu les données. Ce reçu ne peut être créé que par l’extension.
4. Si le widget affiche « Relier mes données », vérifier le diagnostic. Une signature qui retire ou change le groupe commun empêche le partage ; l’app continue de fonctionner et n’affiche aucun total inventé.

Si une IPA **après resignature** est disponible localement, exécuter :

```powershell
./Scripts/Diagnostic-IPA.ps1 -IPA 'chemin/vers/Cadence-resignee.ipa' -Rapport 'diagnostic-signature.json'
```

La section `keychainSharing` doit indiquer un groupe commun de Cadenza dans les signatures de l’app et de l’extension, autorisé par leurs profils, avec `templateMetadataOnly: false`. `readyForPhysicalReadTest: true` autorise le test de lecture ; ce diagnostic ne valide ni cryptographiquement la signature ni le résultat sur l’iPhone. Les préfixes de signature et les données personnelles des profils sont masqués dans ce rapport. Ne pas envoyer de profil, certificat ou identifiant Apple.

## Ce que contient l’IPA distribuée

Le nom `unsigned` désigne une IPA sans certificat ni profil Apple, à resignature obligatoire. Pour préserver les capacités demandées, les variantes Extensions et Shared portent une **signature ad-hoc locale de métadonnées**, sans identité Apple. Son préfixe déclaré `UNSIGNED00` est un modèle temporaire, pas un identifiant d’équipe. Sideloadly doit le remplacer par le préfixe autorisé du compte et conserver le même suffixe de groupe dans les deux bundles. Le fichier `CadenceSigningIntent.plist` fournit aussi l’intention de configuration ; sa présence seule ne donne aucun droit de partage.

Cette signature ad-hoc ne permet pas d’installer l’application. Le diagnostic de l’IPA fournie indique donc volontairement `templateMetadataOnly: true` et `readyForPhysicalReadTest: false`.

La variante **CadenceShared** conserve son autre transport, App Group, qui exige un groupe réellement provisionné. Les variantes autonome et Spike gardent leurs limites de partage. Aucun paiement ou changement de compte n’est effectué automatiquement.

Sources vérifiées : [capacités iOS Apple](https://developer.apple.com/help/account/reference/supported-capabilities-ios), [configuration Keychain Sharing](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing), [groupes d’accès au trousseau](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps), [Sideloadly et conservation des extensions](https://sideloadly.io/).
