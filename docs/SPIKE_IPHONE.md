# Premier jalon : six tests matériels

**Statut initial : compilation iOS, installation, widget, Live Activity et Raccourcis non vérifiés.** Le code complet est livré pour avancer depuis Windows ; cette livraison ne franchit pas le jalon matériel. Commencer par `CadenceSpike-unsigned.ipa` après un run CI réussi. Si la signature des extensions échoue, la variante autonome reste disponible.

| Test | Action sur iPhone 15 Pro | Résultat à relever | Statut initial |
|---|---|---|---|
| 1 · Installer | Signer/installer le spike via Sideloadly, ouvrir en mode avion | Cadence s’ouvre sans compte ni serveur | À faire |
| 2 · Chronométrer | Démarrer une révision, verrouiller 2 min, rouvrir, pause 30 s, reprendre | Temps actif proche de 2 min puis pause exclue ; une seule séance | À faire |
| 3 · Live Activity | Démarrer, verrouiller, observer écran verrouillé et Island puis toucher pour ouvrir | Nom/type/temps visibles, pause correcte ; noter explicitement tout échec | À faire |
| 4 · Widget | Ajouter le widget Cadence petit puis moyen | Sans App Group : « Ouvrir Cadence », aucun faux total ; avec groupe validé : vraie snapshot horodatée | À faire |
| 5 · Raccourcis | Rechercher Cadence, exécuter « Démarrer une révision » avec une matière, puis pause/reprendre/terminer/temps total | Actions natives présentes, ouvrent l’app, contrôle idempotent et historique cohérent | À faire |
| 6 · Préserver | Exporter JSON, fermer/rouvrir puis renouveler par-dessus avec le même bundle ID | Historique et sauvegarde conservés ; vérifier à nouveau à l’échéance de 7 jours | À faire |

La version sans App Group ne promet pas de total dans le widget. La Live Activity utilise ActivityKit pour son état et ne dépend pas d’une lecture du stockage de l’app par l’extension. Elle peut être terminée par iOS après 8 heures ; cela ne termine pas la séance persistée. Ne rien marquer « validé » sans observation réelle.

Après ces tests, installer `CadenceExtensions` ou `Cadence` et suivre la recette fonctionnelle complète. Ne commencer une app watchOS dédiée qu’après preuve de la chaîne de signature/installations iPhone. Aucun test Watch/MDM n’est implicitement réussi.
