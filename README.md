# Cadenza — Atelier Liquid Glass pour iPhone

Application native SwiftUI française, iPhone uniquement, iOS 17 minimum. Le design Atelier conserve ses surfaces translucides et ses halos bleutés. Les deux catégories de temps sont **Cours** et **Révisions**.

La version **0.5.0, build 6** se connecte directement à PRONOTE avec Pawnote LTS, la bibliothèque utilisée par Papillon. La recherche d’établissement utilise une position approximative uniquement au choix « Autour de moi », ou une ville/adresse, avec une URL HTTPS manuelle en alternative. Le mot de passe initial n’est pas enregistré ; le jeton de l’appareil reste dans le trousseau privé, séparé des widgets.

Cours, devoirs, notes et moyennes, compétences, vie scolaire, informations, messagerie, menus, contenus de cours, bulletin et compte sont présentés selon les droits de l’espace élève. Le cache persistant reste accessible hors connexion. Les messages ne sont envoyés et les informations accusées que sur confirmation dans l’interface. La validation d’un devoir dans Cadenza reste locale.

## Installer et utiliser

Installer **Cadenza-iPhone-0.5.0.ipa** par-dessus l’app actuelle avec le même compte et les mêmes options Sideloadly, sans désinstaller. Conserver les extensions et l’auto-renouvellement. Ouvrir ensuite Réglages → Connexion PRONOTE. Voir [la refonte 0.5.0](docs/REFONTE_0.5.0.md), [la connexion directe](docs/PRONOTE_DIRECT.md), [les composants et changements](docs/FONCTIONNALITES_0.4.0.md), [les capacités natives](docs/CAPACITES_NATIVES.md) et [les résultats vérifiés](docs/VERIFICATION.md).

[Aperçu des captures natives de la version 0.4.0](Verification/0.4.0/APERCU.html), avec données fictives et empreintes des fichiers originaux.

Les identifiants `com.cadence.study`, `cadence://` et le fichier `Cadence/cadence-state.json` restent stables. Les noms techniques Cadence préservent la compatibilité des mises à jour ; ils ne correspondent pas à une seconde app.

## Fonctions

- Chronomètre unique, pauses, reprise, matières, alias, historique, sauvegarde JSON et export CSV.
- Cours passés intégrés automatiquement dans Cours, corrections et exclusions locales, une seule durée pour un cours chronométré et planifié.
- Devoirs regroupés par date limite exacte, filtres, lancement d’une révision et association au chronomètre actif.
- Portail PRONOTE depuis l’accueil, ressources liées par leur véritable identifiant et pièces jointes HTTPS.
- Statistiques Charts Cours/Révisions ; provenance historique conservée en interne pour éviter les doubles comptes.
- Widgets locaux, Dynamic Island, Live Activities et App Intents.
- Volume système et sortie AirPlay natifs ; début et fin de séance sans lancement de Raccourcis. Le lecteur universel reste dans le Centre de contrôle iOS.
- Accès direct aux notes, informations et absences depuis Accueil ; ressources de cours classées par matière.
- Actions Valider / Démarrer sur les cartes de devoirs ; HTML PRONOTE nettoyé, y compris les anciens caches.
- Période actuelle propre à chaque écran ; moyennes publiées prioritaires et estimations distinctes si absentes.
- Parcours de première installation et nouveautés versionnés ; recherche des mises à jour publiées depuis Réglages.
- Fonds suspendus hors écran/en arrière-plan et en cas d’économie d’énergie ou de chauffe ; calculs de graphiques regroupés, navigation native conservée.

## Compiler

`Runtime` contient le code source du moteur Pawnote et le verrouillage des dépendances. `npm ci`, `npm test` puis `npm run build` reconstruisent le bundle local ; les tests ne contiennent ni compte scolaire ni données personnelles. `swift test` exécute le domaine métier. GitHub Actions génère le projet avec XcodeGen, teste le pont JavaScriptCore réel puis compile les variantes iPhone. Les sorties sont placées dans une release **brouillon**, sans stockage Actions payant par défaut sur ce dépôt public.

Les variantes CadenceSpike, Cadence, CadenceExtensions et CadenceShared partagent le même bundle ID et se remplacent. Le fichier principal utilise **CadenceExtensions**, avec widgets et Live Activity. La présence de capacités dans une IPA non signée ne garantit pas leur conservation après Sideloadly : voir [les widgets](docs/WIDGETS_WINDOWS.md).

Le client scolaire n’appelle plus Supabase. Les anciens services, fonctions et tâches PRONOTE du projet Supabase n’ont pas été supprimés ou modifiés par cette version. Les structures historiques restent lisibles.

Sources et licences : [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Le code correspondant de la distribution comprenant Pawnote GPL-3.0-or-later est fourni ; le raccourci préfait et sa licence MIT sont inclus. Aucun visuel ni logo Papillon n’est repris.
