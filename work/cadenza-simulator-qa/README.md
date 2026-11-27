# Vérification des interactions iOS

Le test utilise un iPhone simulateur neuf et sélectionne le profil de démonstration via `--cadenza-preview home`. Il réinstalle l’application uniquement dans ce simulateur entre les quatre scénarios. Les accessoires système et le réseau scolaire réels restent hors du test.

Le macOS hôte a besoin de Xcode, d’un runtime iOS arm64, de Java 17 ou supérieur et de la CLI GitHub. Le script télécharge Maestro 2.12.1 et vérifie le SHA-256 du ZIP publié. Il réutilise un brouillon CI qui contient `Cadenza-simulator.app.zip` et le rapport du même commit.

```bash
export GH_TOKEN=…  # jeton du dépôt ayant accès aux brouillons
bash work/cadenza-simulator-qa/run.sh JuJT/Cadence papillon-ci-N-1-simulator SHA_ENTIER 0.9.0 11
```

Le dossier `cadenza-tap-reports` reçoit les valeurs des tests JUnit, les images et les journaux. Un échec conserve les preuves et produit un code de sortie non nul. Les chronomètres passent uniquement si deux lectures affichées progressent puis si la réduction revient à l’onglet d’origine.

Pour un run GitHub secondaire, copier ce dossier sous `work/` sur une branche de QA et installer `workflow.yml.example` dans `.github/workflows/cadenza-ui-taps.yml`. Renseigner le brouillon, le SHA complet et pousser cette branche sous le nom `cadenza-qa/ui-taps`, hors du motif de compilation `papillon-cadenza/**`. Le workflow emploie `contents: write` pour que `GITHUB_TOKEN` lise le brouillon non publié et conserve les sorties comme artefact de run.

[Documentation Maestro pour iOS](https://docs.maestro.dev/get-started/supported-platform/ios/uikit)
