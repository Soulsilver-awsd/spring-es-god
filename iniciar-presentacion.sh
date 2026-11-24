#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$REPO_DIR"

if ! command -v node >/dev/null 2>&1; then
  echo "[ERROR] No se encontró Node.js en el PATH."
  exit 1
fi

PORT="${PORT:-3333}"
URL="http://localhost:${PORT}"

echo "=============================================================="
echo "  Billetera Digital Distribuida - Presentación Web Interactiva"
echo "  Abriendo ${URL} ..."
echo "=============================================================="

(
  sleep 1.5
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then
    open "$URL" >/dev/null 2>&1 || true
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$URL" >/dev/null 2>&1 || true
  fi
) &

exec node "$REPO_DIR/presentacion-web/server.mjs"
