# Compiler puis installer depuis Windows

Le dossier livré contient des sources, pas une IPA déjà compilée. Tant qu’un run GitHub Actions n’a pas réussi, la compilation iOS reste **non vérifiée**. Une IPA unsigned ne s’installe pas directement sur l’iPhone.

## 1. Compiler gratuitement avec GitHub Actions

1. Le dépôt fourni est [JuJT/Cadence](https://github.com/JuJT/Cadence). Le contenu du dossier Cadence se place à sa racine ; le workflow est dans `.github/workflows/`. Aucune note réelle, sauvegarde personnelle ni information Apple ne doit y être ajoutée.
2. Sur ce dépôt **public**, les changements de code sur `main` déclenchent un runner standard `macos-26`, gratuit. Aucun cache ni artefact Actions n’est téléversé sur un push : les sorties sont attachées à une **release brouillon `ci-numéro-du-run`**, accessible aux personnes autorisées à gérer le dépôt. GitHub Releases n’utilise pas le stockage des artefacts Actions ; les fichiers sont limités à moins de 2 GiB chacun, sans quota de taille totale de release ni de bande passante annoncé par GitHub.
3. Onglet **Actions → Cadence · compiler et vérifier sans signature** pour suivre le run. Un lancement manuel est aussi possible ; laisser « quota vérifié » décoché conserve le chemin public via release brouillon, sans artefact Actions. Cocher cette option active en plus un artefact Actions conservé 3 jours : le faire uniquement après vérification du quota de stockage et blocage de tout usage payant dans Billing. Pour un dépôt privé, un lancement manuel avec cette vérification, le quota de calcul suffisant et la variable `CADENCE_PRIVATE_FREE_CI=true` est obligatoire. Le workflow n’interroge pas la facturation du propriétaire.
4. Sur push, le job teste le noyau puis compile les **quatre** variantes : `CadenceSpike`, `Cadence`, `CadenceExtensions` et `CadenceShared`. En lancement manuel, la case App Group permet de choisir la quatrième. Il teste la version complète en simulateur iPhone, exporte les pièces jointes XCTest réelles et capture ses écrans. Si un simulateur iPad est disponible, il teste le même binaire en paysage puis capture Accueil et Statistiques ; sinon `ipad-status.txt` annonce cette limite, sans fabriquer d’image. Les pièces jointes des deux `.xcresult` sont exportées séparément dans `test-attachments/iphone` et `test-attachments/ipad`. Le résumé du job contient le lien vers la release brouillon et ses fichiers. Un échec peut aussi laisser un brouillon contenant des rapports ou des IPA partielles ; son titre et ses notes annoncent le résultat du run. Leur présence ne signifie pas réussite. Les mises à jour de documentation seules ne relancent pas la compilation. Un seul run à la fois, durée maximum 35 minutes ; aucune release n’est publiée automatiquement.

Le runner vérifie Xcode ≥ 26, sans figer un chemin Xcode qui deviendrait obsolète. Il ne reçoit aucun certificat, profil, mot de passe Apple ou secret de signature.

| IPA dans le brouillon / artefact facultatif | Usage |
|---|---|
| `CadenceSpike-unsigned.ipa` | Premier test minimal : minuteur, Live Activity, widget d’ouverture et Raccourcis |
| `Cadence-unsigned.ipa` | Application complète autonome, sans extension ni App Group |
| `CadenceExtensions-unsigned.ipa` | Application complète + Live Activity + widget d’ouverture, sans App Group |
| `CadenceShared-unsigned.ipa` | Option expérimentale : snapshot widget partagée, uniquement si le profil final autorise l’App Group |

Les quatre variantes utilisent **le même bundle ID `com.cadence.study`**, pour remplacer la même installation. Elles ne sont pas destinées à être installées côte à côte. Conserver la même identité lors de la resignature ; sauvegarder avant chaque remplacement.

## 2. Premier essai Sideloadly

1. Installer Sideloadly Windows depuis [le site officiel](https://sideloadly.io/), puis ses prérequis Apple indiqués sur ce site. Ne pas modifier des pilotes déjà fonctionnels sans diagnostic. Le site demande actuellement les versions web d’iTunes et d’iCloud pour Windows.
2. Connecter l’iPhone en USB, le déverrouiller et accepter « Faire confiance ». Activer le mode développeur si iOS le demande.
3. Charger `CadenceSpike-unsigned.ipa` dans Sideloadly. Saisir **vous-même**, dans Sideloadly local uniquement, votre compte Apple et les confirmations requises. Ne transmettre ces informations ni à Codex ni à GitHub.
4. Garder le bundle ID stable. Conserver l’extension pour tester la faisabilité. Si la signature de l’extension bloque, essayer `Cadence-unsigned.ipa` comme solution autonome, puis noter le message d’erreur nettoyé de toute information personnelle.
5. Sur l’iPhone, autoriser le profil développeur si demandé par Réglages. Exécuter les six tests de [SPIKE_IPHONE.md](SPIKE_IPHONE.md). Ne conclure à un succès que sur le résultat observé.

Sideloadly peut supprimer des extensions : si cette option est activée, widgets et Live Activities de Cadence ne peuvent pas être validés. La présence d’un dossier `.appex` dans l’IPA unsigned ne prouve pas sa conservation après resignature.

## 3. Application complète et renouvellement

Après le test minimal, installer la variante adaptée **par-dessus**, avec le même compte et le même bundle ID. Exporter d’abord le JSON depuis Cadence et conserver une copie dans Fichiers/PC. Ne pas supprimer l’app pour renouveler sa signature : cela peut supprimer ses données locales.

Avec le compte gratuit, Sideloadly annonce une validité de 7 jours et propose un daemon d’auto-renouvellement. Son fonctionnement dépend du PC, de l’appareil et de leur connexion. Vérifier l’état avant échéance ; l’automatisation ne garantit pas une disponibilité permanente.

Pour un iPad administré par l’établissement, obtenir l’autorisation de l’établissement et respecter le MDM. La variante autonome ne contourne aucune restriction. L’application Watch dédiée est reportée en P2 ; un éventuel relais système de Live Activity reste à tester sur la Watch.

## Diagnostic local d’un IPA

Après export local de l’IPA resigné, si disponible :

```powershell
.\Scripts\Diagnostic-IPA.ps1 -IPA 'C:\chemin\Cadence-resigne.ipa' -Rapport '.\diagnostic-local.json'
```

Le diagnostic affiche les bundles, les App Groups de l’exécutable et du profil, et l’expiration du profil si lisible. Il ne vérifie pas cryptographiquement la signature et ne remplace pas l’installation. Il ne révèle ni compte Apple, ni UDID, ni certificat, ni profil complet. Ne publier aucun IPA personnel resigné dans le dépôt.

Les rapports CI `*-bundle.json/txt/png` proviennent du bundle réellement compilé dans ce run. Ces PNG sont des **visualisations de l’inventaire**, distinctes des captures natives sous `screenshots/`. Les captures d’écrans proviennent des pièces jointes XCTest après navigation par les vrais boutons de l’app, sans ouverture d’URL système. `screenshot-index.json` relie chaque image au nom donné par le test, au manifeste brut et à son SHA-256 ; si aucun nom exploitable n’est trouvé, seules les pièces jointes brutes sont conservées, sans inventer le nom d’un écran. Aucun de ces fichiers n’est créé comme preuve avant exécution.

Sources vérifiées le 14 novembre 2026 : [runners GitHub macOS](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), [usage et facturation Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [stockage des releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#storage-and-bandwidth-quotas), [Sideloadly officiel](https://sideloadly.io/), [compte développeur Apple](https://developer.apple.com/help/account/basics/about-your-developer-account).
