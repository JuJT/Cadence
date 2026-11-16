# Widgets de Cadenza

La version 0.3 corrige la découverte des groupes après resignature et sépare le groupe privé des jetons du résumé partagé. Voir [le correctif et le contrôle sur appareil](RENOUVELLEMENT_ET_SESSION.md#widgets-après-resignature). Le test de lecture sur l’iPhone reste nécessaire ; une écriture réussie seule ne le remplace pas.

Cadenza pour iPhone propose quatre widgets utilisant uniquement vos données locales :

- **Aujourd’hui** : cours mesurés ou confirmés, révisions et estimations séparées ; petit ou moyen format.
- **Ma semaine** : sept barres quotidiennes, mêmes catégories et matière la plus travaillée ; petit ou moyen format.
- **Prochain cours** : matière normalisée, date et horaire du prochain créneau synchronisé ; petit ou moyen format.
- **Temps d’étude** : résumé du jour sur l’écran verrouillé, en ligne ou rectangle.

Les valeurs sont un résumé daté publié par l’application. Les widgets se rafraîchissent selon le budget d’iOS ; leur compteur n’est pas un chronomètre continu. La Live Activity conserve le chronomètre de la séance. Ouvrir Cadenza actualise le résumé et demande le rechargement des widgets. Les cours futurs ne comptent pas dans les durées. Les estimations sont représentées séparément.

## Installation Windows et compte gratuit

Utiliser **Cadenza-iPhone-0.3.0.ipa** (variante technique `CadenceExtensions`), conserver les extensions dans Sideloadly, le même compte Apple et l’identifiant utilisé pour l’installation existante. Ne pas désinstaller l’application pour la mettre à jour.

Cette variante demande **Keychain Sharing**, que le tableau Apple indique disponible pour un compte Apple Developer gratuit. L’application et son extension demandent le groupe commun `com.cadence.study.widget-summary`, préfixé par le véritable identifiant de signature. Elles recherchent aussi les noms exacts inscrits dans leur propre signature après resignature ; le système contrôle leurs droits effectifs. Le transport du résumé vers les widgets reste local et ne demande aucun serveur ni compte supplémentaire. La connexion Supabase de l’app sert séparément à récupérer les données scolaires. Seul un petit résumé de statistiques et de prochains cours est partagé ; la base d’étude complète reste dans l’application.

**La capacité Apple et sa conservation par Sideloadly sont deux vérifications distinctes.** La documentation publique de Sideloadly ne garantit pas le traitement de ce groupe personnalisé. Après installation :

1. Ouvrir Cadenza et vérifier les durées dans Statistiques.
2. Ajouter un widget Cadenza depuis l’écran d’accueil et choisir Aujourd’hui, Ma semaine ou Prochain cours.
3. Revenir dans les réglages de Cadenza, rubrique diagnostic des intégrations. « Résumé publié » confirme l’écriture par l’app ; **« Dernière lecture réelle par un widget »** confirme que l’extension a lu les données. Ce reçu ne peut être créé que par l’extension.
4. Si le widget affiche « Relier mes données », vérifier le diagnostic. L’app et l’extension doivent conserver au moins un groupe commun réellement autorisé. Un renommage cohérent peut fonctionner ; la suppression de tout groupe commun empêche le partage. L’app continue de fonctionner et n’affiche aucun total inventé.

Si une IPA **après resignature** est disponible localement, exécuter :

```powershell
./Scripts/Diagnostic-IPA.ps1 -IPA 'chemin/vers/Cadence-resignee.ipa' -Rapport 'diagnostic-signature.json'
```

La section `keychainSharing` recherche le suffixe historique du groupe Cadenza dans les signatures de l’app et de l’extension et vérifie son autorisation dans leurs profils. `readyForPhysicalReadTest: true`, avec `templateMetadataOnly: false`, constitue une vérification positive utile avant le test de lecture. Un résultat négatif n’exclut pas un partage fonctionnel si le resigneur a renommé le groupe commun : l’app découvre davantage de noms que cet outil. Ce diagnostic ne valide ni cryptographiquement la signature ni le résultat sur l’iPhone. Les préfixes de signature et les données personnelles des profils sont masqués dans ce rapport. Ne pas envoyer de profil, certificat ou identifiant Apple.

## Ce que contient l’IPA distribuée

Le nom `unsigned` désigne une IPA sans certificat ni profil Apple, à resignature obligatoire. Pour préserver les capacités demandées, les variantes Extensions et Shared portent une **signature ad-hoc locale de métadonnées**, sans identité Apple. Son préfixe déclaré `UNSIGNED00` est un modèle temporaire, pas un identifiant d’équipe. Sideloadly doit le remplacer par des droits autorisés pour le compte et conserver un groupe commun aux deux bundles. Le fichier `CadenceSigningIntent.plist` fournit aussi l’intention de configuration ; sa présence seule ne donne aucun droit de partage.

Cette signature ad-hoc ne permet pas d’installer l’application. Le diagnostic de l’IPA fournie indique donc volontairement `templateMetadataOnly: true` et `readyForPhysicalReadTest: false`.

La variante **CadenceShared** conserve son autre transport, App Group, qui exige un groupe réellement provisionné. Les variantes autonome et Spike gardent leurs limites de partage. Aucun paiement ou changement de compte n’est effectué automatiquement.

Sources vérifiées : [capacités iOS Apple](https://developer.apple.com/help/account/reference/supported-capabilities-ios), [configuration Keychain Sharing](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing), [groupes d’accès au trousseau](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps), [Sideloadly et conservation des extensions](https://sideloadly.io/).
