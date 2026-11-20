# Vérification de la refonte 0.5.0

La refonte est suivie dans la [proposition de version 0.5.0](https://github.com/JuJT/Cadence/pull/1). Les [exécutions de compilation sur sa branche](https://github.com/JuJT/Cadence/actions/workflows/build-unsigned-ipa.yml?query=branch%3Afeat%2Fpronote-integrated-0.5.0) vérifient le moteur Pawnote, le noyau Swift, les IPA et les parcours natifs en simulateur. Seul un run entièrement réussi constitue une validation ; ses rapports et captures sont livrés avec l’IPA correspondante. Les résultats historiques ci-dessous ne valident pas la nouvelle version.

Les fixtures sont fictives. Le compte personnel, l’installation iPhone, le son matériel et le prochain renouvellement Sideloadly ne sont pas testés par le simulateur. L’audit local du 19 novembre confirme seulement que l’auto-renouvellement existant est configuré et sans échec enregistré.

# Vérification de Cadenza 0.4.0 — 18 novembre 2026

Compilation et contrôles finaux : [GitHub Actions](https://github.com/JuJT/Cadence/actions/runs/44347981845), commit `ffe0013fa0589791dae70e31bb7f38ca16969339`, version 0.4.0 build 5. Les quatre variantes ciblent uniquement l’iPhone et conservent l’identifiant `com.cadence.study`.

| Contrôle | Résultat réel |
|---|---|
| Domaine Swift | 78 tests réussis, dont archives Religion, annulations/exclusions, migration des identités de devoirs, sessions et sauvegardes |
| Scripts Python | 22 tests réussis |
| Moteur Pawnote | 40 tests Node réussis ; dépendances épinglées, audit sans vulnérabilité |
| Pont JavaScriptCore | Vrai bundle chargé ; CSPRNG, réseau privé, cookies, bornes, annulation, watchdog, 200 appels consécutifs et nettoyage vérifiés sur macOS |
| Interface | 15 parcours réussis : 14 en clair, 1 en sombre ; connexion sans requête, portail, catégories, dates, séances, brouillon annulé, widgets et grandes polices |
| Captures | 27 captures natives, sans retouche, empreintes conservées |
| Raccourci préfait | Empreinte, chaîne Apple, audience publique, signature AEA et dix actions Focus vérifiées ; fichier signé inclus dans chaque app |
| IPA | Quatre IPA arm64 iPhone, nom/version/bundle ID/CRC/SHA-256 conformes ; bundle Pawnote et raccourci comparés aux empreintes |
| Stockage privé | Groupe de jetons distinct du résumé widgets dans les métadonnées de signature ; validation après Sideloadly reste matérielle |

## Essais sur le service public de démonstration

Le [rapport agrégé](../Verification/0.4.0/PRONOTE_DEMO.json) décrit quatre connexions autorisées à la démo officielle Index Éducation et 46 réponses HTTP 200. Aucun compte personnel, aucun jeton ni aucune ligne scolaire n’est publié. Les lectures ont validé le profil, les cours, les devoirs, les notes, les contenus et une leçon liée. Le créneau réel de 61 jours a donné 198 cours et 57 devoirs, avec identifiants uniques et durées positives.

Les ressources ont été vérifiées sur des intervalles de 7, 14 et 61 jours. Une requête annuelle unique renvoyait zéro ; l’interface charge donc les contenus et les menus par semaine, à la demande, et permet de changer de date.

La démo PRONOTE 2026 n’avait aucune information publiée. Son nouveau schéma de liste a été observé en lecture réelle. Les articles non vides, sondages et détails différés sont testés avec des données synthétiques correspondant au contrat du client officiel public ; ils restent à vérifier avec le compte réel. La liste ne déclenche aucun appel de détail et aucun article n’est marqué comme lu ou accusé automatiquement.

La démo ne valide pas le renouvellement persistant des jetons : son serveur ne les conserve pas comme un établissement réel. La rotation, l’ordre de sauvegarde et l’interruption d’une requête consommante sont couverts séparément par les tests du moteur. Aucun message, accusé de réception ou changement de réalisation de devoir n’a été envoyé pendant les essais réels. Le test UI du compositeur a rempli puis annulé un brouillon sans action Envoyer.

## Limites et essais sur appareil

L’iPhone n’était pas disponible pour une validation matérielle. La première connexion avec les vrais identifiants, les vérifications de sécurité propres à l’établissement, l’import/autorisation du raccourci, le partage réel des widgets après Sideloadly, la Dynamic Island et la température restent à contrôler sur l’appareil. Une IPA compilée et ses signatures ad-hoc ne garantissent pas les droits conservés par le resigneur.

Les optimisations réduisent les mises à jour du fond, les calculs de graphiques, les minuteurs hors écran et les rechargements d’extensions. Ce sont des contrôles structurels et fonctionnels, pas une mesure de chauffe ou de consommation sur iPhone. Le chronomètre reste fondé sur les dates persistées.

Le lecteur universel des pistes et positions d’autres applications n’est pas fourni par les API publiques iOS. Le volume et le sélecteur de sortie audio intégrés sont des contrôles système réels ; Cadenza ne propose plus d’import MP3 ni de lien Deezer.

Un premier contrôle a révélé une course entre la fin d’une commande JavaScript et l’admission de la suivante. Le gate est désormais libéré avant le retour au demandeur ; les 200 appels consécutifs et la passe finale vérifient cette correction. Les sources des tests et les rapports bruts sont livrés.

Guides : [connexion PRONOTE](PRONOTE_DIRECT.md), [composants](FONCTIONNALITES_0.4.0.md), [son/Concentration et renouvellement](RENOUVELLEMENT_ET_SESSION.md), [galerie native](../Verification/0.4.0/APERCU.html).

---

## Historique — Vérification de Cadenza 0.3.0 — 17 novembre 2026

Compilation finale : [GitHub Actions](https://github.com/JuJT/Cadence/actions/runs/43974418769), commit `5f3e66c9c178ca482674d16d4ca9dec388eb7767`, version 0.3.0 build 4. Les quatre IPA appareil portent le nom Cadenza et ciblent uniquement l’iPhone.

| Contrôle | Résultat réel |
|---|---|
| Noyau Swift | 65 tests réussis, dont migration, doublons, Paris été/hiver, devoirs/pauses/attributions et validation des liens de connexion |
| Scripts Python | 13 tests réussis, dont séparation du groupe privé et des droits du widget |
| Résumé widgets | Sérialisation, ancien format, bornes, séparation des estimations et parseur des groupes signés : réussis |
| Parcours natifs | 11 réussis, dont trois parcours de devoirs et la feuille Musique et concentration ; 10 en clair, 1 en sombre |
| Captures | 21 captures natives sans retouche, empreintes conservées dans `Verification/0.3.0` |
| Métadonnées et intégrité | Version, nom, famille iPhone, extensions, CRC et SHA-256 des quatre IPA conformes |
| Isolation d’authentification | Groupe privé présent dans l’app et absent des droits du widget, aucun wildcard donnant cet accès ; modèles de signature ad-hoc, sans profil Apple |
| API déployée | Connexion par e-mail vérifié puis lecture 200 de 460 créneaux, 17 devoirs et 250 contenus ; refus 401/403 et schéma privé inaccessible au client public |
| Infrastructure PRONOTE | Fonctions existantes inchangées, 14 tâches PRONOTE actives ; aucun nouveau client PRONOTE sur iPhone |

Les tests réseau ont été exécutés depuis le poste de travail. Le lien de connexion a été vérifié en POST, la session de test révoquée et les fichiers temporaires de jetons supprimés. Le rapport `SUPABASE_AUDIT.json` ne conserve que des résultats agrégés. Aucun contenu scolaire réel, adresse, identifiant utilisateur, jeton ou secret administratif n’est publié dans le dépôt, les captures ou les logs de CI.

Un lancement précédent du simulateur n’a pas ouvert la feuille « Nouvelle séance » malgré un tap correctement ciblé. Le même code a ensuite réussi les onze parcours complets ; aucun défaut reproductible de présentation n’a été établi. Les rapports distinguent cette exécution de validation des tentatives précédentes.

Les données des captures scolaires et de présentation sont fictives et compilées uniquement dans le simulateur. Les images de widgets montrent les composants réels dans une galerie de test, sans constituer une installation WidgetKit sur l’écran d’accueil. Le fond animé est actif avec ses garde-fous d’accessibilité ; la CI ne mesure pas la consommation énergétique réelle de l’iPhone.

L’iPhone n’étant pas disponible en USB/Wi-Fi pendant cette livraison, le Keychain privé après Sideloadly, la lecture réelle des widgets, l’audio écran verrouillé, la Dynamic Island et le raccourci Concentration restent à contrôler sur appareil. Les capacités de l’IPA non signée ne garantissent pas leur conservation par le resigneur. Le reçu « Dernière lecture réelle par un widget » reste la preuve de lecture effective.

Composants et utilisation : [FONCTIONNALITES_0.3.0.md](FONCTIONNALITES_0.3.0.md), [SUPABASE_CADENZA.md](SUPABASE_CADENZA.md), [RENOUVELLEMENT_ET_SESSION.md](RENOUVELLEMENT_ET_SESSION.md).

---

## Historique — Cadenza 0.2.0

Les quatre variantes finales 0.2.0 (build 3) sont compilées par [GitHub Actions](https://github.com/JuJT/Cadence/actions/runs/43766146783), commit `5e7b98e89a7b887c20914fd2d98d7f4a3e9b0144`.

| Contrôle | Résultat |
|---|---|
| Noyau métier inchangé | 36 tests Swift réussis |
| Scripts de diagnostic et captures | 8 tests Python réussis |
| Résumé widgets | Ancien format décodé, sérialisation complète, taille bornée, estimations séparées et valeurs invalides : réussis |
| IPA appareil | Quatre variantes arm64 pour iPhone uniquement, nom Cadenza, même identifiant d’app, nouvelle icône 1024 × 1024 opaque |
| Intégrité locale | CRC et SHA-256 des quatre IPA comparés aux empreintes du runner : conformes |
| Parcours XCTest complets | 7 réussis sur iPhone : navigation, calendrier, séance, vitrine, grandes polices, composants widgets et sombre ; [run complet](https://github.com/JuJT/Cadence/actions/runs/43762368393) |
| Recontrôle après ciblage iPhone | Quatre IPA reconstruites, noms et familles de chaque app/extension contrôlés ; parcours Nouvelle séance, formulaire et fin relancé avec succès |
| Captures natives | 20 images et provenance conservées dans `Verification/Cadenza-0.2.0` |
| Partage des données widgets | Groupe commun présent dans les métadonnées des exécutables Extensions ; droits Apple réels après Sideloadly non validés par la CI |

Les captures `vitrine-*` utilisent des données fictives isolées uniquement dans le simulateur. Les captures `widgets-apercu-*` montrent les composants SwiftUI réellement utilisés par les widgets, pas des widgets installés sur SpringBoard. Elles permettent de contrôler la mise en page sans représenter une preuve de signature ou de lecture du trousseau sur iPhone. La Dynamic Island et la lecture réelle des widgets restent à essayer sur l’appareil.

Les sept parcours complets et les captures de présentation proviennent du commit `9d8194a1b95f7169bbb3d25d2a3f3c0a0a398f57`. Les sources `App`, `Shared`, `Widgets`, `Sources` et `Tests` sont identiques dans le commit final. Le dernier ajustement impose la famille iPhone dans chaque cible XcodeGen et vérifie les Info.plist réellement compilés. Les captures préfixées `final-` et `rapports-build-final` proviennent de cette reconstruction ; la provenance exacte figure dans chaque entrée du rapport JSON.

La variante Extensions contient une signature ad-hoc de métadonnées, sans certificat ni profil Apple, pour conserver les capacités demandées à la resignature. Elle ne s’installe pas directement et le diagnostic indique volontairement `templateMetadataOnly: true`, `readyForPhysicalReadTest: false`. La disponibilité de Keychain Sharing et la conservation du groupe par Sideloadly sont des conditions distinctes ; voir [WIDGETS_WINDOWS.md](WIDGETS_WINDOWS.md). Un reçu de lecture n’est écrit que par l’extension après une lecture effective.

Le détail de la refonte, des composants et des fichiers est dans [REFONTE_DESIGN_0.2.0.md](REFONTE_DESIGN_0.2.0.md). Les données, alias et calculs de CadenceCore sont conservés.

---

## Historique — Cadence 0.1.1

Les quatre IPA finales 0.1.1 (build 2) sont compilées par le [run GitHub Actions 43719744499](https://github.com/JuJT/Cadence/actions/runs/43719744499), commit `34649464e895545be455644e69f593b4aa7fd638`. Ce dernier passage raccourcit uniquement le titre du formulaire pour supprimer sa troncature, puis réexécute les tests métier/scripts et le parcours de séance. La [régression complète précédente](https://github.com/JuJT/Cadence/actions/runs/43717867275), commit `aab667e7bda356940d5ed7a88c2e893cdbe9d4aa`, avait déjà validé l’ensemble des modifications fonctionnelles et les cinq parcours iPhone/iPad.

| Vérification du correctif | Résultat |
|---|---|
| Noyau métier | 36 tests Swift réussis, dont titres courts et alias Français conservés |
| Scripts | 6 tests Python réussis |
| IPA appareil | Quatre variantes arm64 compilées, version 0.1.1 build 2, même identifiant d’app |
| Intégrité | CRC des quatre IPA et SHA-256 comparés aux rapports du runner : conformes |
| iPhone simulateur | Régression complète réussie : dates dans les deux sens, matières courtes, feuille, annulation/confirmation, pause/reprise. Parcours de séance réexécuté après le raccourcissement du titre : réussi |
| Sombre et iPad paysage | Parcours existants réussis |
| Captures natives | 13 captures de régression et 3 nouvelles captures du contrôle final : feuille, formulaire au titre entier et alerte de fin |
| Installation physique du correctif | Non réalisée par la CI ; recette iPhone à effectuer après mise à jour |

Le nouvel ensemble de preuves est dans `Verification/0.1.1/RESULTAT_CI.json`. La régression complète conserve ses rapports et captures dans `rapports` et `captures` ; le contrôle final utilise `rapports-en-tete` et `captures-en-tete`. Les empreintes relient chaque image à son propre run. Ces captures proviennent de simulateurs ; elles ne constituent pas une preuve du rendu de la Dynamic Island sur l’iPhone personnel.

L’utilisateur a signalé la réussite des essais du Spike antérieur sur son iPhone, puis fourni les captures de l’application complète qui motivent ce correctif. La nouvelle disposition de la Dynamic Island et des widgets reste à examiner sur cet appareil. Dans CadenceExtensions, le widget fonctionne comme raccourci sans totaux ; les données partagées nécessitent un App Group autorisé dans la signature. Les essais d’une version antérieure ne valident pas ces modifications.

Voir [CORRECTIF_0.1.1.md](CORRECTIF_0.1.1.md) pour la portée et la recette de mise à jour. La refonte esthétique globale est différée à l’étape suivante.

---

## Historique de la première livraison

La compilation complète du 14 novembre 2026 a réussi : [run GitHub Actions 43613409295](https://github.com/JuJT/Cadence/actions/runs/43613409295), commit `6728b57416f0ac74296f70278c35d6e7bbca1551`.

| Vérification | Résultat |
|---|---|
| Xcode | 26.6, build 17F113 ; Swift 6.3.3 en mode langage Swift 5 |
| Noyau métier | 34 tests exécutés, zéro échec |
| Scripts Python | 6 tests exécutés, zéro échec |
| Application pour appareil | Quatre IPA arm64 compilées : essai, autonome, extensions et App Group expérimental |
| Intégrité locale | CRC des ZIP/IPA et SHA-256 comparés aux empreintes du runner : conformes |
| Extensions | `CadenceWidgets.appex` présent pour les trois variantes avec extension, absent pour l’autonome |
| Simulateur iPhone | Navigation, démarrage, pause, reprise, terminaison et statistiques : réussis |
| Mode sombre | Parcours Statistiques et capture réelle : réussis |
| Simulateur iPad | Navigation à colonnes en paysage : réussie |
| Captures livrées | Neuf images natives, provenant des pièces jointes XCTest ; revue visuelle effectuée |
| Installation et signature gratuite | **Non effectuées sur appareil physique** |

Les captures iPad ont fait l’objet d’un [contrôle ciblé supplémentaire](https://github.com/JuJT/Cadence/actions/runs/43703459552) : l’ancienne capture de fenêtre de XCTest était recadrée après rotation. La capture plein écran et l’attente des dimensions paysage corrigent cet artefact. Seuls les tests et leur workflow ont changé ; le code applicatif est identique à celui des quatre IPA compilées. Les six images iPhone proviennent du run complet ; les trois images iPad livrées proviennent de ce contrôle ciblé.

Les fichiers `Verification/RESULTAT_CI_0.1.0.json`, `Verification/rapports-ci`, `Verification/rapports-ipad` et `Verification/captures` conservent les résultats, empreintes et preuves. Les PNG d’inventaire des bundles sont des visualisations de leur structure réelle ; ils sont distincts des captures d’interface. Les images dans `Reference/Design` restent les maquettes d’origine.

## Ce qui reste à vérifier sur votre appareil

- Installation Sideloadly et renouvellement par-dessus l’app avec le même compte et le même bundle ID.
- Conservation effective de l’extension après resignature, Live Activity, Dynamic Island, widget et découverte/exécution des Raccourcis.
- Autorisation EventKit, présence du calendrier Google déjà synchronisé et import de votre emploi du temps réel.
- Accessibilité avec vos réglages, versions antérieures à iOS 26 et autorisation de l’iPad administré.
- Relais système vers la Watch ; application watchOS dédiée maintenue en P2.

La variante App Group est compilée mais ses droits ne sont pas garantis avec un compte gratuit. Utilisez la variante autonome si les extensions empêchent la signature. Le guide [SPIKE_IPHONE.md](SPIKE_IPHONE.md) comporte les six essais physiques ; aucun n’a été marqué réussi sans observation réelle.

## Environnement local

L’essai Swift local sous WSL avait expiré avant compilation ; les tests validés ont donc été exécutés sur macOS GitHub. Aucun paquet système ni service Windows n’a été modifié. La toolchain temporaire d’Ubuntu a été supprimée après rétablissement de WSL le 15 novembre ; elle ne fait pas partie des livrables.
