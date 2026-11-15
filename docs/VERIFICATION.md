# Vérification de Cadence — livraison du 15 novembre 2026

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

Les fichiers `Verification/RESULTAT_CI.json`, `Verification/rapports-ci`, `Verification/rapports-ipad` et `Verification/captures` conservent les résultats, empreintes et preuves. Les PNG d’inventaire des bundles sont des visualisations de leur structure réelle ; ils sont distincts des captures d’interface. Les images dans `Reference/Design` restent les maquettes d’origine.

## Ce qui reste à vérifier sur votre appareil

- Installation Sideloadly et renouvellement par-dessus l’app avec le même compte et le même bundle ID.
- Conservation effective de l’extension après resignature, Live Activity, Dynamic Island, widget et découverte/exécution des Raccourcis.
- Autorisation EventKit, présence du calendrier Google déjà synchronisé et import de votre emploi du temps réel.
- Accessibilité avec vos réglages, versions antérieures à iOS 26 et autorisation de l’iPad administré.
- Relais système vers la Watch ; application watchOS dédiée maintenue en P2.

La variante App Group est compilée mais ses droits ne sont pas garantis avec un compte gratuit. Utilisez la variante autonome si les extensions empêchent la signature. Le guide [SPIKE_IPHONE.md](SPIKE_IPHONE.md) comporte les six essais physiques ; aucun n’a été marqué réussi sans observation réelle.

## Environnement local

L’essai Swift local sous WSL avait expiré avant compilation ; les tests validés ont donc été exécutés sur macOS GitHub. Aucun paquet système ni service Windows n’a été modifié. La toolchain temporaire d’Ubuntu a été supprimée après rétablissement de WSL le 15 novembre ; elle ne fait pas partie des livrables.
