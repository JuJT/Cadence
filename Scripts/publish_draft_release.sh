#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -n "${GH_TOKEN:-}"
test -n "${GITHUB_REPOSITORY:-}"
test -n "${GITHUB_SHA:-}"
test -n "${GITHUB_RUN_NUMBER:-}"
command -v gh >/dev/null
mkdir -p dist/reports

# Seulement les sorties réellement présentes dans ce run, y compris un échec partiel.
# Une release brouillon n'est jamais présentée comme une compilation réussie.
shopt -s nullglob
assets=(dist/*-unsigned.ipa)
report_paths=()
for path in dist/reports dist/screenshots dist/*.xcresult; do
  if [[ -d "$path" ]]; then report_paths+=("${path#dist/}"); fi
done
if (( ${#report_paths[@]} > 0 )); then
  report_zip="$PWD/dist/Cadence-rapports-et-captures.zip"
  (cd dist && /usr/bin/zip -qry "$report_zip" "${report_paths[@]}")
  assets+=("$report_zip")
fi
python3 - "${assets[@]}" <<'PY'
import os, sys
for path in sys.argv[1:]:
    if os.path.getsize(path) >= 2 * 1024 ** 3:
        raise SystemExit('Fichier trop volumineux pour GitHub Releases : ' + os.path.basename(path))
PY

tag="ci-${GITHUB_RUN_NUMBER}"
notes="dist/reports/release-notes.md"
cat > "$notes" <<EOF
Cadence — sorties du run CI n° ${GITHUB_RUN_NUMBER}.

Révision : ${GITHUB_SHA}
Résultat des étapes de vérification : ${BUILD_RESULT:-unknown}
Run : https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}

Ce brouillon peut contenir des rapports d’échec ou une compilation partielle.
Les IPA éventuellement présentes sont non signées. Aucune installation iPhone,
signature gratuite, Live Activity ou extension sur appareil physique n’est validée.
Les captures de simulateur, si présentes, sont réelles ; les images de bundle sont
des inventaires générés depuis le produit compilé. Aucun fichier absent n’est simulé.

Ce brouillon n’est pas une publication : il reste réservé aux personnes autorisées
à gérer les releases du dépôt. Il utilise le stockage GitHub Releases, sans cache
ni artefact Actions pour un lancement sur push.
EOF

if existing_draft="$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json isDraft --jq .isDraft 2>/dev/null)"; then
  if [[ "$existing_draft" != "true" ]]; then
    echo 'La release existe déjà et est publiée : refus de la modifier automatiquement.' >&2
    exit 1
  fi
  gh release edit "$tag" --repo "$GITHUB_REPOSITORY" --draft \
    --target "$GITHUB_SHA" --title "Cadence · CI #${GITHUB_RUN_NUMBER} (${BUILD_RESULT:-unknown})" --notes-file "$notes"
  if (( ${#assets[@]} > 0 )); then
    gh release upload "$tag" "${assets[@]}" --repo "$GITHUB_REPOSITORY" --clobber
  fi
else
  gh release create "$tag" "${assets[@]}" --repo "$GITHUB_REPOSITORY" \
    --target "$GITHUB_SHA" --draft \
    --title "Cadence · CI #${GITHUB_RUN_NUMBER} (${BUILD_RESULT:-unknown})" --notes-file "$notes"
fi
url="$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json url --jq .url)"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '\n[Brouillon de livraison CI #%s](%s) — résultat : %s\n' \
    "$GITHUB_RUN_NUMBER" "$url" "${BUILD_RESULT:-unknown}" >> "$GITHUB_STEP_SUMMARY"
fi
