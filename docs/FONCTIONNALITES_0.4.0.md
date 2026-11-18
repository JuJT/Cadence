# Cadenza 0.4.0 — composants et changements

| Composant | Responsabilité |
|---|---|
| `Runtime/src`, `Runtime/patches`, `package-lock.json` | Pawnote LTS 1.6.4, compatibilité Papillon épinglée, normalisation du protocole, tests Node sans données réelles |
| `App/Services/PawnoteRuntime.swift` | JavaScriptCore hors MainActor, réseau privé, limites, CSPRNG, annulation et retour borné |
| `PronoteSchoolService.swift` | Connexion directe, jetons rotatifs privés, ordre des requêtes et gardes de déconnexion |
| `PronotePortalRepository.swift` | Cache scolaire séparé du suivi d’étude, atomique et protégé |
| `SchoolLocatorService.swift`, `SchoolConnectionView.swift` | Annuaire, localisation facultative, ville, URL et connexion élève |
| `PronotePortalView.swift` | Notes, moyennes, compétences, vie scolaire, informations, messages, menus, contenus, bulletin, compte et liens selon autorisations |
| `CorePronoteModels.swift` | Profil, périodes, capacités et cache de portail |
| `SchoolReconciler.swift`, `Models.swift`, `CadenceEngine.swift` | Réparation Religion, archives, exclusions explicites et migration des identités de devoirs sans perte de travail |
| `CadenceTheme.swift`, vues Accueil/Statistiques/Cours/Devoirs/Révision | Cadence du fond, suspension hors écran, calculs regroupés, dates limites et deux catégories |
| `LiveActivityManager.swift`, `Shared/CadenceWidgetViews.swift` | Traitement regroupé des intégrations, publication utile des widgets et Cours/Révisions |
| `SessionCompanionService.swift`, `SessionCompanionView.swift` | Raccourci préfait, volume système et sortie audio, sans lecteur MP3 ou lien Deezer |
| `Scripts/verify_prebuilt_focus_shortcut.py` | Vérification reproductible du préfait signé, de son audience et de ses seules actions Focus |

Les champs historiques distinguant les modes d’enregistrement restent dans les sauvegardes pour préserver leur lecture et éviter les doubles comptes. Ils ne créent plus une troisième catégorie dans les écrans, widgets et dialogues Raccourcis.

Les cours annulés remplacés ne restent plus des cartes concurrentes. Les vrais choix locaux et les séances déjà mesurées ne sont pas effacés. La réparation fonctionne d’abord avec le cache, avant la réponse du réseau.

Le fond garde son aspect mais passe de 15 à 2 mises à jour maximales par seconde, avec suspension lorsque l’écran est masqué, l’app inactive ou l’appareil en état thermique non nominal. Les calculs statistiques sont réalisés une fois par journée/période, et non dans chaque barre du graphique. Seul l’affichage du chronomètre visible garde une cadence d’une seconde ; l’enregistrement reste fondé sur les dates persistées.

Ces réductions structurelles ne sont pas une mesure de température sur iPhone. Le comportement thermique, le partage réel des widgets après resignature et les permissions Concentration doivent encore être vérifiés sur l’appareil.
