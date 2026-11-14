# CONSIGNE PRINCIPALE CODEX — CADENCE ATELIER LIQUID GLASS V2

Tu es responsable de la **construction complète et testable** de Cadence, application **native SwiftUI** pour iPhone/iPad, avec intégration calendrier, cours, révisions, Live Activities, widgets, Raccourcis. L'utilisateur développe depuis **Windows exclusivement**, dispose d'un **Apple ID gratuit**, iPhone 15 Pro et Apple Watch Series 7, ainsi qu'un iPad scolaire potentiellement sous MDM. **0 € de coût obligatoire.**

## Ne pas improviser le brief ; lire d'abord

- `README_COMMENCER_ICI.md`
- `docs/SPEC_CALENDRIER_ET_DEDOUBLONNAGE.md`
- `docs/CHARTE_LIQUID_GLASS_NATIVE.md`
- `docs/UX_PARCOURS_ET_RECETTE_V2.md`
- `docs/CAHIER_DES_CHARGES.md`, `docs/ARCHITECTURE_TECHNIQUE.md`, `docs/FAISABILITE_ET_RISQUES.md`, `docs/PLAN_IMPLEMENTATION_ET_RECETTE.md`
- `designs/ATELIER_LIQUID_GLASS_3_ECRANS.png` (référence image), `designs/PROTOTYPE_INTERACTIF.html` (prototype navigable), `designs/TOKENS.json`, `designs/CHOIX_DESIGN.json`.

**V2 prévaut** sur l'ancien kit. Choix utilisateur définitifs : design Atelier + Liquid Glass Apple ; **deux types Cours / Révision** ; **cours calendriers Apple/Google déjà synchronisés ET cours manuels** ; révisions manuelles. Aucune question générale de style nécessaire.

## Cadre d'implémentation

- Code Swift/SwiftUI, EventKit, Charts, ActivityKit/WidgetKit, AppIntents. Pas de web wrapper, PWA ni React Native.
- Lire **les calendriers iOS déjà synchronisés**, y compris Google si présent, via `EKEventStore`; ne pas ajouter d'intégration Google OAuth obligatoire. Autorisation utilisateur de lecture (`requestFullAccessToEvents`) avant accès. Ne JAMAIS modifier le calendrier système depuis Cadence.
- Import des occurrences d'emploi du temps, classification matière configurable, dédoublonnage idempotent, traitement récurrences, mise à jour et suppression sans perdre sessions personnelles. Compter automatiquement un cours passé uniquement si l'utilisateur l'active ; alors afficher clairement « estimé » et remplacer l'estimation par le temps réel en cas de séance associée.
- Une session Cours manuelle et une session Révision manuelle peuvent être démarrées; une seule session chronométrée active à la fois. Agrégats : Cours mesurés/confirmés, Cours estimés, Révisions, total, sans double comptage.
- UI iOS26+ **réellement native** Liquid Glass : TabView/NavigationStack/toolbar/menu/sheet/nouveau style boutons ; glassEffect seulement quand nécessaire ; couleurs sémantiques et support des options d'accessibilité. Sur iOS17–25, fallback fonctionnel. Mettre les bonnes conditions `#available`, ne pas inventer des APIs ; valider sur Xcode présent sur GitHub runner.
- Données locales, exports JSON versionnés et CSV, aucun serveur, compte, abonnement ni secret.
- Extension widget + Live Activity toutes régions Dynamic Island ; App Shortcuts `Démarrer une révision`, `Ajouter un cours`, `Pause/Reprendre/Terminer`, `Temps cours/révisions/total`, `Ouvrir l'emploi du temps`. Pas de fausse intégration Raccourcis.

## Ordre obligatoire — réduire le travail de l'utilisateur

1. Générer projet XcodeGen ou `.xcodeproj`, tests et workflow `.github/workflows/build-unsigned-ipa.yml` pour runner macOS GitHub Actions. Aucun secret Apple ID/signature privé en CI.
2. **Spike minimal** : installer app simple depuis IPA non signé + Sideloadly compte gratuit ; widget/Live Activity/App Intent; fournir checklist de 4–6 tests matériels, et **ne jamais marquer comme validé** sans retour utilisateur.
3. Implémenter modèle et tests, moteur sessions et import calendrier EventKit, CRUD de matière / alias / sessions ; UI iOS26+ suivant les maquettes, responsive iPad.
4. Implémenter extension et intégrations Apple en isolant la dégradation si entitlement App Group non accessible. Offrir stockage indépendant en mode sans widget plutôt que planter.
5. Produire IPA unsigned et artifact CI ; fournir capture d'écran de la structure `.app/PlugIns`, scripts de diagnostic, guide de signature Windows/Sideloadly, sauvegarde et renouvellement 7 jours.
6. Si watchOS accessible, concevoir extension Watch P2 après preuve de signature / installation ; ne pas bloquer la V1.

## Critères d'arrêt

N'affirme pas « prêt à utiliser » sans compilation CI réussie, et jamais « Live Activity fonctionne » sans installation/test réel. Même en absence de CI ou d'accès physique, livrer des sources et un workflow complet, étapes restantes exactes et risques identifiés. Développer le maximum sans demander des confirmations secondaires. Ne jamais demander les identifiants Apple au chat, aux outils connectés ou aux logs. Si un dépôt GitHub est privé, s'assurer que le quota de runners macOS est disponible ; éviter toute facture.

## Livrables attendus de Codex

Sources SwiftUI/XcodeGen, workflow macOS, tests automatisés, doc installation, doc données, architecture, matrice de recette, fichier de changelog, captures simulées si possibles, statut de vérification différencié : « compilé », « testé en simulateur », « installé et testé sur iPhone ». Tous les termes et labels en français.
