# Vérification des interactions iOS

Le test utilise un iPhone simulateur neuf et sélectionne le profil de démonstration via `--cadenza-preview home`. Les quatre scénarios utilisent de vrais taps XCTest. Apple Vision reconnaît les textes visibles et localise les boutons dans les captures. Les accessoires système et le réseau scolaire réels restent hors du test.

Le macOS hôte a besoin de Xcode, d’un runtime iOS arm64 et de la CLI GitHub. Le script télécharge XcodeGen 2.49.0 et vérifie le SHA-256 du ZIP publié. Il compile le projet de test autonome et réutilise l’application compilée dans le brouillon CI du même commit.

```bash
export GH_TOKEN=…  # jeton du dépôt ayant accès aux brouillons
bash work/cadenza-simulator-qa/run.sh JuJT/Cadence papillon-ci-N-1-simulator SHA_ENTIER 0.9.0 11
```

Le dossier `cadenza-tap-reports` reçoit le résumé XCTest, les images, les résultats OCR et les journaux. Un échec conserve les preuves et produit un code de sortie non nul. Les chronomètres passent uniquement si deux lectures affichées progressent de deux secondes ou plus puis si la réduction revient à l’onglet d’origine.

Pour un run GitHub secondaire, copier ce dossier sous `work/` sur une branche de QA et installer `workflow.yml.example` dans `.github/workflows/cadenza-ui-taps.yml`. Renseigner le brouillon, le SHA complet et pousser cette branche sous le nom `cadenza-qa/ui-taps`, hors du motif de compilation `papillon-cadenza/**`. Le workflow emploie `contents: write` pour que `GITHUB_TOKEN` lise le brouillon non publié et conserve les sorties comme artefact de run.

[Documentation XCTest](https://developer.apple.com/documentation/xcuiautomation) · [Reconnaissance de texte Vision](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
