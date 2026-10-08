#!/usr/bin/env bash
# Lance à la main le test de charge k6 (le même que celui de l'analyse automatique)
# contre un service, et affiche le résumé de k6.
# Usage : ./scripts/charge.sh [cible]     ex. ./scripts/charge.sh http://taskflow
set -uo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
CIBLE="${1:-http://taskflow}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCENARIO="${SCRIPT_DIR}/../exemples/robustesse/configmap-k6.yaml"

echo "Test de charge k6 sur ${CIBLE} (60 s, 5 utilisateurs virtuels)..."
awk '/robustesse.js: \|/{f=1; next} f{sub(/^    /, ""); print}' "${SCENARIO}" \
  | kubectl -n taskflow run "k6-$(date +%s)" --rm -i --restart=Never --quiet \
      --image=grafana/k6:latest --image-pull-policy=IfNotPresent \
      --env="TARGET=${CIBLE}" -- run -
code=$?
if [ "${code}" -eq 0 ]; then
  echo "Résultat : seuils respectés."
else
  echo "Résultat : au moins un seuil n'est pas respecté (code ${code})."
fi
exit "${code}"
