# Architecture de la livraison

## Séparation des responsabilités

`CadenceCore` est un package Swift Foundation sans dépendance à EventKit, SwiftUI ni WidgetKit. Les modèles sont des valeurs Codable/Sendable. Le moteur reçoit une copie de l’état par `inout` et les tests contrôlent les horodatages. La source de vérité locale est `CadenceState`, version 3, compatible avec les anciennes sauvegardes.

`AppStore` est l’unique écrivain, isolé sur MainActor. Une commande prépare une copie, la valide puis écrit le fichier atomiquement avant de publier l’état à SwiftUI et aux intégrations. Une erreur de lecture initiale bloque les écritures et conserve le fichier existant. Les App Intents utilisent `openAppWhenRun = true` et le même store ; ils ne prétendent pas modifier une base isolée d’extension.

`LocalStateRepository` stocke `Application Support/Cadence/cadence-state.json` et conserve la génération précédente dans `cadence-previous.json`. Le partage widget ne déplace jamais cette base. Pas de synchronisation multiappareils.

## Synchronisation scolaire Supabase

SupabaseSchoolService lit le nouvel endpoint Edge authentifié. SchoolReconciler rapproche les créneaux, conserve les décisions locales et absorbe les anciens doublons sans effacer les séances. AppStore sérialise les rafraîchissements et invalide les réponses périmées. Les données restent en cache, tandis que les jetons sont dans le trousseau privé. Voir [SUPABASE_CADENZA.md](SUPABASE_CADENZA.md).

## Ancien connecteur Calendrier et compatibilité

Ce code reste présent pour la compatibilité et l’historique, mais n’alimente plus les cours scolaires au lancement, au premier plan ni sur notification EventKit. L’interface scolaire utilise Supabase. Les paragraphes suivants décrivent l’ancien import.

`CalendarIntegrationService` demande l’accès EventKit uniquement après action de l’utilisateur. L’accès système s’appelle « intégral » car iOS l’impose pour lire ; le code Cadence n’effectue aucune écriture EventKit. Google est disponible seulement si ses calendriers sont déjà synchronisés et exposés par iOS.

Le premier import requiert un aperçu puis une validation. La fenêtre est de 30 jours avant aujourd’hui à 31 jours après le début d’aujourd’hui. Les rafraîchissements suivants utilisent la même fenêtre, au retour au premier plan, après notification EventKit ou sur demande. Aucune périodicité d’arrière-plan n’est garantie.

Le rapprochement vérifie calendrier, identifiants et ancre de récurrence ; si les identifiants changent, il utilise un rapprochement conservateur par titre et horaires à cinq minutes. Une ambiguïté est mise à vérifier. Les événements « révision », sur journée entière et exclus par mot-clé ne sont pas automatiquement importés en cours. Les titres non classés demandent une matière.

Une lecture refusée ou échouée ne devient jamais un instantané vide destructeur. Un calendrier qui n’est plus disponible est exclu du rapprochement des suppressions. Désélectionner un calendrier conserve l’historique. Une modification de cours protégé garde l’ancienne décision comptable et propose d’accepter les nouveaux horaires ou de garder les horaires personnels.

## Temps et statistiques

Les segments `start/end` définissent le temps actif ; un segment ouvert désigne la phase en cours. Le timer UI rafraîchit seulement l’affichage. Les transitions sont persistées et la session reste restaurable après fermeture. Recul de l’horloge : la transition est refusée avec un message explicite.

Les statistiques coupent chaque segment aux bornes de la période locale, avec les intervalles du calendrier système ; un jour de changement d’heure peut durer 23 ou 25 heures. Une durée confirmée corrigée est répartie proportionnellement sur son créneau prévu. Une session mesurée liée remplace le crédit de l’occurrence entière. Une occurrence future, absente, annulée ou ignorée ne produit aucun crédit de planning.

## Intégrations et distribution

La Live Activity reçoit des mises à jour aux transitions. Son compteur système dépend des dates, sans mise à jour ActivityKit chaque seconde. Ses régions compactes, minimales, étendues et écran verrouillé sont définies dans l’extension. La session principale peut continuer au-delà de la limite système de l’activité.

Sans App Group disponible, le widget propose l’ouverture de Cadence et n’affiche aucun faux total. La variante partagée utilise uniquement une copie minimale horodatée, jamais les notes détaillées. La variante autonome ne contient pas d’extension. La signature gratuite et Sideloadly doivent être vérifiés sur appareil : aucun résultat de compilation ne constitue cette preuve.

Le projet XcodeGen et les workflows sont séparés du package. Les schémas d’essai et de production partagent les mêmes sources et l’identité d’installation. Xcode 26 ou ultérieur est requis pour compiler les boutons Liquid Glass ; les appels récents sont conditionnés à iOS 26 et les contrôles standards assurent le repli.
