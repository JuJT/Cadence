# Cadenza 0.3.0 — composants et utilisation

Le design approuvé reste la base. Les halos se déplacent lentement par bruit interpolé non périodique, à 15 images/s maximum. Le rendu se suspend lorsque l’app est inactive, le fond masqué, l’économie d’énergie active ou les options d’accessibilité correspondantes activées. L’entrée d’une nouvelle séance et les changements d’onglet ont une transition courte sans réinitialiser la navigation.

## Fichiers et responsabilités

| Composant | Rôle |
|---|---|
| `Sources/CadenceCore/SchoolModels.swift` | Contrat réseau et cache des cours, devoirs et contenus |
| `SchoolReconciler.swift`, `Models.swift`, `CadenceEngine.swift`, `Statistics.swift`, `BackupCodec.swift` | Migration, rapprochement, crédit automatique, réalisation locale, segments par devoir et sauvegardes compatibles |
| `SchoolLoginLink.swift` | Validation stricte du code/lien reçu avant toute vérification d’authentification |
| `App/Services/SupabaseSchoolService.swift`, `SchoolAPIConfiguration.swift` | Requêtes authentifiées, session/refresh privés, URL fixe et refus de redirections |
| `App/AppStore.swift`, `LocalStateRepository.swift` | Persistance avant affichage, garde contre les réponses périmées, sauvegarde avant migration et actualisation |
| `App/Views/HomeworkView.swift`, `SchoolConnectionView.swift` | Nouvel onglet Devoirs, détails, filtres, travail et connexion initiale |
| `CoursesView.swift`, `HomeView.swift`, `RootView.swift`, `SettingsView.swift`, `RevisionView.swift` | Cours Supabase, exclusions sans confirmation imposée et intégrations aux écrans existants |
| `App/Services/SessionCompanionService.swift`, `App/Views/SessionCompanionView.swift` | Lecteur audio privé et appel du raccourci Concentration |
| `App/Design/CadenceTheme.swift` | Halos mobiles et transition d’onglet accessibles |
| `Shared/WidgetSnapshot.swift`, `App/Services/LiveActivityManager.swift` | Résumé depuis le cache, groupes réellement autorisés et reçu de lecture |
| `Shared/SignedKeychainGroups.swift` | Découverte bornée des groupes de la propre signature de l’exécutable, sans API privée ; Security contrôle toujours les droits |
| `Config/CadenceAppKeychain.entitlements`, `project.yml`, scripts de signature/diagnostic | Groupe privé d’authentification séparé du résumé du widget |
| `supabase/functions/cadenza-school`, `supabase/migrations` | Lecteur Edge déployé et autorisation privée reproductible |
| `Tests/CadenceCoreTests`, `Tests/CadenceUITests` | Régressions métier, sécurité des liens et parcours avec données fictives |

## À faire après installation

1. Installer `Cadenza-iPhone-0.3.0.ipa` par-dessus l’app actuelle, avec le même compte et les mêmes options Sideloadly. Conserver les extensions et l’auto-renouvellement ; ne pas désinstaller l’app.
2. Ouvrir Réglages → Connexion PRONOTE via Supabase. Utiliser l’adresse Gmail propriétaire déjà autorisée, demander le message et coller son code ou son lien dans l’app sans l’ouvrir d’abord. Une session privée est ensuite conservée sur cet iPhone.
3. Pour Concentration, créer une fois le raccourci décrit dans [RENOUVELLEMENT_ET_SESSION.md](RENOUVELLEMENT_ET_SESSION.md), puis activer son appel automatique. iOS peut demander une autorisation initiale.
4. Ajouter les widgets et vérifier leur lecture réelle dans Diagnostic. Le correctif de transport est intégré, mais la conservation des droits par Sideloadly nécessite le test sur l’appareil.

Le lecteur de fichiers propose les commandes réelles de sa propre lecture audio. Deezer et les fichiers déjà lus par une autre app gardent leurs commandes dans le Centre de contrôle ; Cadenza ne prétend pas piloter ces lecteurs avec une API Apple privée.

Le renouvellement automatique était actif lors de l’audit local du 16 novembre. Chaque signature gratuite reste valable sept jours et doit être renouvelée à temps par le PC joignable en USB ou en Wi-Fi. L’app ne peut pas rendre ce profil permanent.
