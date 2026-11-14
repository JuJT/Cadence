# Intégrations système et modes de repli

## ActivityKit

`SessionActivityAttributes` transporte uniquement identifiant de séance, nom de matière, type, état et références temporelles. Le stockage local des séances reste l’autorité. Chaque mutation persistée déclenche `SystemIntegrationService.refresh(state:)` ; les mises à jour ActivityKit sont sérialisées, sans minuterie réseau et sans publication chaque seconde.

Le chrono actif affiché par SwiftUI part d’une date virtuelle égale à `maintenant − secondes actives`. La pause affiche une durée fixe ; la reprise recrée la référence temporelle. L’extension fournit écran verrouillé, compact leading/trailing, minimal et les régions expanded. Les liens ouvrent les commandes dans l’app. Les commandes directes de pause/fin en extension ne sont pas promises sans partage/processus vérifiés.

`NSSupportsLiveActivities` est activé uniquement dans les variantes avec extension. Toute erreur ActivityKit reste un diagnostic local ; elle n’efface ni ne termine les séances. Une activité peut expirer après 8 heures, même si une séance dure davantage. Aucun push distant, compte ou serveur n’est utilisé.

## WidgetKit et App Groups

Dans `CadenceExtensions`, aucun entitlement App Group n’est demandé. Le widget propose d’ouvrir Cadence et annonce l’indisponibilité des données partagées. Il n’invente pas de totaux.

Dans `CadenceShared`, l’app et l’extension demandent `group.com.cadence.study`. Ce nom est une configuration à conserver cohérente avec les entitlements effectivement provisionnés lors de la signature. Si le conteneur n’est pas accessible, l’app garde son stockage privé et le widget revient à l’ouverture. Le mode partagé publie une snapshot atomique : cours mesurés/confirmés, cours estimés, révisions, prochaine occurrence et matière active, sans notes. L’heure d’actualisation est affichée ; une snapshot d’un jour précédent n’est jamais présentée comme le total d’aujourd’hui. La fréquence de rafraîchissement reste décidée par WidgetKit.

Une compilation avec entitlements unsigned ne prouve pas que le compte gratuit autorise ces entitlements. Contrôler **l’exécutable et le profil resignés** et effectuer le test matériel. La disponibilité de `containerURL` permet un repli, pas une certification de la signature.

## Raccourcis Apple

Les dix structures `AppIntent` sont compilées dans l’app principale, avec `openAppWhenRun=true` : démarrer une révision, ajouter un cours terminé, pause, reprise, fin, temps de cours, temps de révisions, total, emploi du temps et confirmation d’un cours du calendrier. Cette dernière action utilise une vraie `AppEntity` dont les suggestions proviennent des occurrences locales terminées. Elles appellent le même singleton `AppStore` et le même moteur/persistance que l’interface ; aucun faux appel web ou état séparé n’est utilisé.

La matière est indiquée par son nom/alias exact ou résolue depuis la matière par défaut. Une matière ambiguë déclenche une erreur explicite. L’ajout de cours qui chevauche une occurrence demande de poursuivre l’association dans l’app. Les actions pause/reprise/fin répétées ne dupliquent aucune séance. Les requêtes retournent des **secondes** et annoncent les estimations séparément dans leur dialogue.

Les actions ne sont pas exécutées comme un service silencieux dans le widget. Leur découverte et leur exécution après fermeture de l’app restent des tests physiques requis. Siri et l’indexation peuvent dépendre de la langue et de l’état du système.

## OS, Watch et accès

Minimum iOS/iPadOS 17. Les contrôles natifs Liquid Glass sont conditionnés à iOS 26 dans les vues ; les versions précédentes ont des contrôles standards. Les captures CI vérifient uniquement le simulateur installé sur le runner, pas tous les OS compatibles. Les App Groups, Live Activities et Raccourcis doivent être testés avec la signature finale. L’app Watch dédiée reste P2. L’iPad scolaire dépend de son MDM et de l’autorisation de l’établissement.

Références Apple vérifiées le 14 novembre 2026 : [Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider), [ouvrir l’app depuis un intent](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun), [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).
