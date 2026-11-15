# Vérification de Cadenza 0.2.0 — 15 novembre 2026

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
