#!/usr/bin/env bash
# Presentacion interactiva modo PowerPoint (1 tecla) basada en guion.md
# Uso: ./presentacion.sh   (Linux / macOS / WSL / Git Bash)
set -uo pipefail
unset LC_ALL 2>/dev/null || true
_utf_chk="á"
if [ "${#_utf_chk}" -ne 1 ]; then
  export LC_CTYPE=C.UTF-8 2>/dev/null || true
  _utf_chk="á"
  [ "${#_utf_chk}" -ne 1 ] && export LC_CTYPE=en_US.UTF-8 2>/dev/null || true
fi
export LC_NUMERIC=C

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR" || exit 1

GATEWAY="${GATEWAY:-http://localhost:8080}"
EUREKA="${EUREKA:-http://localhost:8761}"
ORIGEN="0991112233"
DESTINO="0984445566"

SHOW_NOTES=1
DECK_START=0
LAST_TX_NODO="PRIMARY (recovery=false)"
LAST_TX_CODIGO="TX-2026-0001"
LAST_BURST_SUMMARY=""
CACHE_TX_OK_FILE=""
CACHE_TX_ERR_FILE=""

TMP="$(mktemp -d)"
HEADERS_FILE="$TMP/headers.txt"
BODY_FILE="$TMP/body.json"
TRAFICO_PID=0
BG_DOCKER_PID=0

# Colores ANSI
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_CYAN=$'\033[36m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_BLUE=$'\033[34m'
C_MAGENTA=$'\033[35m'
C_WHITE=$'\033[97m'

cleanup() {
  [ "$TRAFICO_PID" -gt 0 ] && kill "$TRAFICO_PID" 2>/dev/null || true
  [ "$BG_DOCKER_PID" -gt 0 ] && wait "$BG_DOCKER_PID" 2>/dev/null || true
  rm -rf "$TMP"
  printf '\033[?25h%s' "$C_RESET"
}
trap cleanup EXIT INT TERM

# Parser JSON con fallback si no hay jq
JSON_TOOL="raw"
if command -v jq >/dev/null 2>&1; then
  JSON_TOOL="jq"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import json" >/dev/null 2>&1; then
  JSON_TOOL="python3"
elif command -v python >/dev/null 2>&1 && python -c "import json" >/dev/null 2>&1; then
  JSON_TOOL="python"
fi

clear_safe() {
  [ -t 1 ] && [ -n "${TERM:-}" ] && clear 2>/dev/null || true
}

repeat_char() {
  local ch="$1" n="$2" out=""
  [ "$n" -le 0 ] && return
  printf -v out '%*s' "$n" ''
  printf '%s' "${out// /$ch}"
}

pad_fixed() {
  local txt="${1//$'\r'/}" w="$2"
  local len=${#txt}
  if [ "$len" -gt "$w" ]; then
    printf '%s...' "${txt:0:$((w - 3))}"
  else
    printf '%s%*s' "$txt" "$((w - len))" ''
  fi
}

get_elapsed_timer() {
  if [ "$DECK_START" -le 0 ]; then
    printf '00:00 / 05:00'
    return
  fi
  local now diff m s
  now=$(date +%s)
  diff=$((now - DECK_START))
  [ "$diff" -lt 0 ] && diff=0
  m=$((diff / 60))
  s=$((diff % 60))
  printf '%02d:%02d / 05:00' "$m" "$s"
}

get_progress_bar() {
  local num="$1" total="${2:-15}" filled empty
  filled=$(( (num * 10 + total / 2) / total ))
  [ "$filled" -gt 10 ] && filled=10
  empty=$((10 - filled))
  printf '[%s%s]' "$(repeat_char '█' "$filled")" "$(repeat_char '░' "$empty")"
}

slide_chrome() {
  local num="$1" block="$2" title="$3" speaker="$4" budget="$5"
  clear_safe
  local prog timer short_blk left right gap row2
  prog="$(get_progress_bar "$num" 15)"
  timer="$(get_elapsed_timer)"
  short_blk="${block/BLOQUE /B}"
  left="$(printf 'SLIDE %02d/15  %s  %s' "$num" "$prog" "$short_blk")"
  if [ -n "$speaker" ]; then
    right="$speaker ($budget)  $timer"
  else
    right="$timer"
  fi
  gap=$((74 - ${#left} - ${#right}))
  if [ "$gap" -lt 1 ]; then
    local maxl=$((74 - ${#right} - 1))
    [ "$maxl" -lt 1 ] && maxl=1
    left="${left:0:$maxl}"
    gap=$((74 - ${#left} - ${#right}))
    [ "$gap" -lt 1 ] && gap=1
  fi
  row2="$(pad_fixed "► $title" 74)"

  printf '%s╔%s╗%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"
  printf '%s║ %s%s%s%*s%s%s%s ║%s\n' \
    "$C_CYAN" "$C_CYAN" "$left" "$C_RESET" "$gap" "" "$C_YELLOW" "$right" "$C_CYAN" "$C_RESET"
  printf '%s║ %s%s%s ║%s\n' "$C_CYAN" "${C_BOLD}${C_WHITE}" "$row2" "$C_CYAN" "$C_RESET"
  printf '%s╚%s╝%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"
}

box_top() {
  local title=" $1 " col="${2:-$C_DIM}"
  local fill=$((75 - ${#title}))
  [ "$fill" -lt 2 ] && fill=2
  printf '%s┌─%s%s┐%s\n' "$col" "$title" "$(repeat_char '─' "$fill")" "$C_RESET"
}

box_line() {
  local txt="$1" tcol="${2:-$C_WHITE}" bcol="${3:-$C_DIM}"
  printf '%s│ %s%s%s │%s\n' "$bcol" "$tcol" "$(pad_fixed "$txt" 74)" "$bcol" "$C_RESET"
}

box_bottom() {
  local col="${1:-$C_DIM}"
  printf '%s└%s┘%s\n' "$col" "$(repeat_char '─' 76)" "$C_RESET"
}

write_notes() {
  [ "$SHOW_NOTES" -eq 0 ] && return
  printf '\n  %sNOTAS DEL ORADOR:%s\n' "$C_YELLOW" "$C_RESET"
  for l in "$@"; do
    printf '    %s· %s%s\n' "$C_DIM" "$l" "$C_RESET"
  done
}

open_eureka() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$EUREKA" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then
    open "$EUREKA" >/dev/null 2>&1 &
  elif command -v wslview >/dev/null 2>&1; then
    wslview "$EUREKA" >/dev/null 2>&1 &
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$EUREKA" >/dev/null 2>&1 &
  fi
}

read_slide_key() {
  local k="" seq=""
  IFS= read -rsn1 k || { ACT="QUIT"; return; }
  if [ "$k" = $'\x1b' ]; then
    if [ "${BASH_VERSINFO[0]:-3}" -ge 4 ]; then
      IFS= read -rsn3 -t 0.05 seq || true
    fi
    case "$seq" in
      "[D"|"OD"|"[5~") ACT="PREV" ;;
      "[C"|"OC"|"[6~") ACT="NEXT" ;;
      "")              ACT="HOME" ;;
      *)               ACT="NEXT" ;;
    esac
    return
  fi
  if [ "$k" = $'\x7f' ] || [ "$k" = $'\b' ]; then
    ACT="PREV"
    return
  fi
  case "$k" in
    a|A) ACT="PREV" ;;
    n|N) ACT="NEXT" ;;
    r|R) ACT="REPEAT" ;;
    m|M) ACT="HOME" ;;
    q|Q) ACT="QUIT" ;;
    b|B) ACT="EUREKA" ;;
    v|V) ACT="NOTES" ;;
    u|U) ACT="UTILS" ;;
    p|P) ACT="PREP" ;;
    s|S) ACT="STARTALL" ;;
    t|T) ACT="SUITE" ;;
    c|C) ACT="ENV" ;;
    0)   ACT="RESET_TIMER" ;;
    [1-6]) ACT="B$k" ;;
    *)   ACT="NEXT" ;;
  esac
}

wait_slide_footer() {
  local next_lbl="${1:-Siguiente diapositiva}" allow_back="${2:-1}"
  printf '\n%s%s%s\n' "$C_DIM" "$(repeat_char '─' 78)" "$C_RESET"
  if [ "$allow_back" -eq 1 ]; then
    printf '  %s[ESPACIO/→] %s   [←/Backspace] Anterior%s\n' "${C_BOLD}${C_GREEN}" "$next_lbl" "$C_RESET"
  else
    printf '  %s[ESPACIO/→] %s%s\n' "${C_BOLD}${C_GREEN}" "$next_lbl" "$C_RESET"
  fi
  local nlbl="OFF"; [ "$SHOW_NOTES" -eq 1 ] && nlbl="ON"
  printf '  %s[R] Re-ejecutar  [B] Eureka  [V] Notas:%-3s  [U] Utils  [M] Portada  [Q] Salir%s\n' "$C_DIM" "$nlbl" "$C_RESET"
  while true; do
    read_slide_key
    case "$ACT" in
      EUREKA)
        open_eureka
        printf '  %s[OK] Eureka abierto en el navegador (%s).%s\n' "$C_CYAN" "$EUREKA" "$C_RESET"
        ;;
      NOTES)
        SHOW_NOTES=$((1 - SHOW_NOTES))
        nlbl="OFF"; [ "$SHOW_NOTES" -eq 1 ] && nlbl="ON"
        printf '  %s[OK] Notas del orador: %s (desde la siguiente pantalla).%s\n' "$C_CYAN" "$nlbl" "$C_RESET"
        ;;
      *) return ;;
    esac
  done
}

api_req() {
  local method="$1" url="$2" json="${3:-}" tout="${4:-10}" code
  local args=(-s --max-time "$tout" -o "$BODY_FILE" -D "$HEADERS_FILE" -w '%{http_code}' -X "$method" "$url")
  if [ -n "$json" ]; then
    args+=(-H 'Content-Type: application/json' -d "$json")
  else
    args+=(-H 'Accept: application/json')
  fi
  code="$(curl "${args[@]}" 2>/dev/null)" || code="000"
  [ -z "$code" ] && code="000"
  echo "$code"
}

get_header() {
  grep -i "^$1:" "$HEADERS_FILE" 2>/dev/null | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/\r$//'
}

ensure_env() {
  if [ ! -f "$REPO_DIR/.env" ]; then
    if [ -f "$REPO_DIR/.env.example" ]; then
      cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
      printf '  %s[OK] Archivo .env creado desde .env.example.%s\n' "$C_GREEN" "$C_RESET"
      return 0
    fi
    printf '  %s[ERROR] No existe .env ni .env.example.%s\n' "$C_RED" "$C_RESET"
    return 1
  fi
  return 0
}

extract_transfer_fields() { # file -> msg|cod|sal|ic|nbd|pol
  local f="$1"
  case "$JSON_TOOL" in
    jq)
      jq -r '[.mensaje // "-", .datos.codigoComprobante // "-", (.datos.nuevoSaldoOrigen // "-" | tostring), .auditoriaTecnica.instanciaCuentasConsultada // "-", .auditoriaTecnica.nodoBaseDatos // "-", .auditoriaTecnica.politicaEnrutamiento // "-"] | join("|")' "$f" 2>/dev/null
      ;;
    python3|python)
      "$JSON_TOOL" - "$f" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    datos = d.get("datos") or {}
    aud = d.get("auditoriaTecnica") or {}
    vals = [
        str(d.get("mensaje") or "-"),
        str(datos.get("codigoComprobante") or "-"),
        str(datos.get("nuevoSaldoOrigen") if datos.get("nuevoSaldoOrigen") is not None else "-"),
        str(aud.get("instanciaCuentasConsultada") or "-"),
        str(aud.get("nodoBaseDatos") or "-"),
        str(aud.get("politicaEnrutamiento") or "-"),
    ]
    print("|".join(vals))
except Exception:
    print("-|-|-|-|-|-")
PY
      ;;
    *) echo "-|-|-|-|-|-" ;;
  esac
}

extract_critico_fields() { # file -> saldo|nbd|pol
  local f="$1"
  case "$JSON_TOOL" in
    jq)
      jq -r '[(.datos.saldo // "-" | tostring), .auditoriaTecnica.nodoBaseDatos // "-", .auditoriaTecnica.politicaEnrutamiento // "-"] | join("|")' "$f" 2>/dev/null
      ;;
    python3|python)
      "$JSON_TOOL" - "$f" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    datos = d.get("datos") or {}
    aud = d.get("auditoriaTecnica") or {}
    print(f"{datos.get('saldo', '-')}|{aud.get('nodoBaseDatos', '-')}|{aud.get('politicaEnrutamiento', '-')}")
except Exception:
    print("-|-|-")
PY
      ;;
    *) echo "-|-|-" ;;
  esac
}

get_saldo_line() {
  local code
  code="$(api_req GET "$GATEWAY/api/cuentas/$ORIGEN/saldo-critico" "" 2)"
  [ "$code" != "200" ] && return 1
  case "$JSON_TOOL" in
    jq) jq -r '.datos | "\(.saldo)|\(.consumidoHoy)|\(.limiteDiario)"' "$BODY_FILE" 2>/dev/null ;;
    python3|python)
      "$JSON_TOOL" - "$BODY_FILE" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8")).get("datos") or {}
    print(f"{float(d.get('saldo') or 0):.2f}|{float(d.get('consumidoHoy') or 0):.2f}|{float(d.get('limiteDiario') or 0):.2f}")
except Exception:
    sys.exit(1)
PY
      ;;
    *) return 1 ;;
  esac
}

# --- Utilidades Pre-grabacion / Panel ---

show_clean_prep() {
  clear_safe
  printf '%s╔%s╗%s\n' "$C_YELLOW" "$(repeat_char '═' 76)" "$C_RESET"
  printf '%s║ %s%s%s ║%s\n' "$C_YELLOW" "$C_YELLOW" "$(pad_fixed "PREPARACION LIMPIA PRE-GRABACION (down -v + up -d --build)" 74)" "$C_YELLOW" "$C_RESET"
  printf '%s╚%s╝%s\n\n' "$C_YELLOW" "$(repeat_char '═' 76)" "$C_RESET"
  ensure_env || { wait_slide_footer "Volver" 0; return; }
  printf '  %s$ docker compose down -v && docker compose up -d --build%s\n' "$C_CYAN" "$C_RESET"
  docker compose down -v
  docker compose up -d --build || {
    printf '\n  %s[ERROR] docker compose up fallo.%s\n' "$C_RED" "$C_RESET"
    wait_slide_footer "Volver" 0
    return
  }
  printf '\n  %sEsperando que los 8 contenedores esten healthy...%s\n' "$C_YELLOW" "$C_RESET"
  local start_t now elapsed h
  start_t=$(date +%s)
  while true; do
    now=$(date +%s); elapsed=$((now - start_t))
    [ "$elapsed" -ge 240 ] && break
    h=$(docker compose ps -a --format '{{.Status}}' 2>/dev/null | grep -c 'healthy' || true)
    printf '\r  %s[%3ds] Healthy: %s/8   %s' "$C_CYAN" "$elapsed" "$h" "$C_RESET"
    if [ "$h" -ge 8 ]; then
      printf '\n  %s[OK] Los 8 contenedores estan healthy!%s\n' "$C_GREEN" "$C_RESET"
      break
    fi
    sleep 2
  done
  open_eureka
  printf '  %s[OK] Eureka abierto en %s%s\n' "$C_GREEN" "$EUREKA" "$C_RESET"
  CACHE_TX_OK_FILE=""
  CACHE_TX_ERR_FILE=""
  DECK_START=0
  wait_slide_footer "Volver al panel" 0
}

show_utils_panel() {
  while true; do
    clear_safe
    printf '%s╔%s╗%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"
    printf '%s║ %s%s%s ║%s\n' "$C_CYAN" "$C_CYAN" "$(pad_fixed "PANEL DE CONTROL Y UTILIDADES (PRE-GRABACION / PLAN B)" 74)" "$C_CYAN" "$C_RESET"
    printf '%s╚%s╝%s\n\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"

    [ ! -f "$REPO_DIR/.env" ] && printf '  %s[AVISO] Falta .env en el repositorio (pulsa [C] o [P]).%s\n' "$C_YELLOW" "$C_RESET"
    local ps_out total=0 healthy=0 stopped=""
    if ps_out="$(docker compose ps -a --format '{{.Name}}|{{.State}}|{{.Status}}' 2>/dev/null)"; then
      total="$(echo "$ps_out" | grep -c '|' || true)"
      healthy="$(echo "$ps_out" | grep -c 'healthy' || true)"
      stopped="$(echo "$ps_out" | awk -F'|' '$2 != "running" && $1 != "" {print $1}' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
      local col="$C_YELLOW"; [ "$healthy" -ge 8 ] && col="$C_GREEN"
      printf '  %sClúster: %s/8 healthy (visibles: %s)%s\n' "$col" "$healthy" "$total" "$C_RESET"
      [ -n "$stopped" ] && printf '  %sDetenidos: %s -> pulsa [S] para arrancar%s\n' "$C_RED" "$stopped" "$C_RESET"
    else
      printf '  %sDocker: Daemon no responde.%s\n' "$C_RED" "$C_RESET"
    fi
    local sinfo
    if sinfo="$(get_saldo_line | tr -d '\r')"; then
      local s c l col="$C_GREEN"
      s="$(echo "$sinfo" | cut -d'|' -f1)"; c="$(echo "$sinfo" | cut -d'|' -f2)"; l="$(echo "$sinfo" | cut -d'|' -f3)"
      awk -v v="${c:-0}" 'BEGIN{exit !(v+0 > 0)}' && col="$C_YELLOW"
      printf '  %sCuenta %s: saldo=%s | consumidoHoy=%s / %s%s\n' "$col" "$ORIGEN" "$s" "$c" "$l" "$C_RESET"
    fi
    printf '\n'
    box_top "ACCIONES RAPIDAS" "$C_CYAN"
    box_line "[P] Preparacion limpia (down -v + up -d --build + abrir Eureka)" "$C_YELLOW" "$C_CYAN"
    box_line "[S] Arrancar contenedores detenidos (docker compose start)" "$C_WHITE" "$C_CYAN"
    box_line "[B] Abrir Eureka en navegador ($EUREKA)" "$C_WHITE" "$C_CYAN"
    box_line "[C] Crear .env desde .env.example" "$C_WHITE" "$C_CYAN"
    box_line "[T] Plan B: ejecutar suite automatizada P01-P08" "$C_WHITE" "$C_CYAN"
    box_line "[0] Reiniciar cronometro de presentacion (00:00)" "$C_WHITE" "$C_CYAN"
    box_line "[1..6] Saltar directo a Bloque 1..6" "$C_CYAN" "$C_CYAN"
    box_line "[ESPACIO / ESC / M] Volver a la Portada" "$C_GREEN" "$C_CYAN"
    box_bottom "$C_CYAN"

    read_slide_key
    case "$ACT" in
      PREP)        show_clean_prep ;;
      STARTALL)    clear_safe; ensure_env || true; docker compose start; wait_slide_footer "Volver" 0 ;;
      EUREKA)      open_eureka ;;
      ENV)         ensure_env; sleep 1 ;;
      RESET_TIMER) DECK_START=0; CACHE_TX_OK_FILE=""; CACHE_TX_ERR_FILE="" ;;
      SUITE)
        clear_safe
        [ -f "$REPO_DIR/docs/api/curl-p01-p08.sh" ] && bash "$REPO_DIR/docs/api/curl-p01-p08.sh"
        wait_slide_footer "Volver" 0
        ;;
      QUIT)        ACT="QUIT"; return ;;
      B[1-6])      return ;;
      *)           ACT="PORTADA"; return ;;
    esac
  done
}

# --- Diapositivas 01 a 15 ---

slide_01() {
  slide_chrome 1 "BLOQUE 1/6" "Arquitectura distribuida (8 contenedores)" "Persona A" "0:00-0:50"
  cat <<'ART'

  +----------------+   HTTP :8080   +-----------------------+
  | Cliente / Demo | -------------> |  api-gateway (:8080)  |
  +----------------+                +-----------+-----------+
                                                | lb:// Round Robin
  +-----------------------+                     v
  | eureka-server (:8761) | <==== registro + latido 5s =====
  +-----------------------+     |              |            |
                                v              v            v
                         +------------+ +------------+ +----------------+
                         |ms-cuentas-1| |ms-cuentas-2| |ms-transacciones|
                         |   :8081    | |   :8082    | |     :8083      |
                         +-----+------+ +-----+------+ +-------+--------+
                               \              |                /
                                +----> [Enrutador JDBC] <-----+
                        Escritura/RYOW /              \ Lecturas
                                      v                v
                   +----------------------+     +---------------------+
                   | primary :5432 (R/W)  |====>| replica1 :5433 (RO) |
                   | cuentas_db  | tx_db  | WAL | replica2 :5434 (RO) |
                   +----------------------+     +---------------------+
ART
  write_notes \
    "Billetera P2P: 8 contenedores, todo distribuido y con respaldo." \
    "Esquemas y usuarios disjuntos en BD: garantizado por PostgreSQL."
  wait_slide_footer "Ver contenedores vivos (docker compose ps)"
}

slide_02() {
  slide_chrome 2 "BLOQUE 1/6" "Clúster Docker activo (8 contenedores)" "Persona A" "0:00-0:50"
  printf '\n'
  box_top "DOCKER COMPOSE PS" "$C_CYAN"
  local healthy=0 total=0
  if docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}' >"$TMP/ps.txt" 2>/dev/null; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if echo "$line" | grep -q 'healthy'; then
        healthy=$((healthy + 1)); total=$((total + 1))
        box_line "$line" "$C_GREEN" "$C_CYAN"
      elif echo "$line" | grep -q '^NAME'; then
        box_line "$line" "$C_CYAN" "$C_CYAN"
      else
        total=$((total + 1))
        box_line "$line" "$C_YELLOW" "$C_CYAN"
      fi
    done <"$TMP/ps.txt"
  else
    box_line "No se pudo consultar docker compose (verifica Docker)." "$C_RED" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
  local pcol="$C_YELLOW"; [ "$healthy" -ge 8 ] && pcol="$C_GREEN"
  [ "$total" -lt 8 ] && total=8
  printf '  %s[ ESTADO DEL CLUSTER: %s/%s CONTENEDORES HEALTHY ]%s\n' "$pcol" "$healthy" "$total" "$C_RESET"
  write_notes "Senalar los 8 contenedores en estado (healthy) y pasar a Persona B."
  wait_slide_footer "Bloque 2: Descubrimiento en Eureka"
}

slide_03() {
  slide_chrome 3 "BLOQUE 2/6" "Descubrimiento dinámico en Eureka" "Persona B" "0:50-1:40"
  printf '\n'
  box_top "CONCEPTO CLAVE" "$C_CYAN"
  box_line "● Registro automatico al arrancar + heartbeat cada 5 segundos." "$C_WHITE" "$C_CYAN"
  box_line "● El Gateway no usa IPs fijas: resuelve 'ms-cuentas' via Eureka (lb://)." "$C_WHITE" "$C_CYAN"
  box_bottom "$C_CYAN"
  printf '\n'
  box_top "REGISTRO EUREKA EN VIVO (:8761/eureka/apps)" "$C_GREEN"
  local code
  code="$(api_req GET "$EUREKA/eureka/apps" "" 5)"
  if [ "$code" = "200" ]; then
    case "$JSON_TOOL" in
      jq)
        jq -r '.applications.application[] | "\(.name)|\([.instance[] | "\(.instanceId) [\(.status)]"] | join("  ,  "))"' "$BODY_FILE" 2>/dev/null | \
          while IFS='|' read -r name insts; do
            local col="$C_CYAN"; [ "$name" = "MS-CUENTAS" ] && col="$C_GREEN"
            box_line "$(printf '%-17s -> %s' "$name" "$insts")" "$col" "$C_GREEN"
          done
        ;;
      python3|python)
        "$JSON_TOOL" - "$BODY_FILE" <<'PY' | tr -d '\r' | while IFS='|' read -r name insts; do
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    for app in d.get("applications", {}).get("application", []):
        insts = app.get("instance", [])
        if isinstance(insts, dict): insts = [insts]
        s = "  ,  ".join(f"{i.get('instanceId')} [{i.get('status')}]" for i in insts)
        print(f"{app.get('name', '')}|{s}")
except Exception:
    pass
PY
          local col="$C_CYAN"; [ "$name" = "MS-CUENTAS" ] && col="$C_GREEN"
          box_line "$(printf '%-17s -> %s' "$name" "$insts")" "$col" "$C_GREEN"
        done
        ;;
      *) box_line "Respuesta Eureka OK (HTTP 200)." "$C_GREEN" "$C_GREEN" ;;
    esac
  else
    box_line "No responde Eureka en $EUREKA (HTTP $code)." "$C_RED" "$C_GREEN"
  fi
  box_bottom "$C_GREEN"
  write_notes \
    "Mostrar Eureka en el navegador (pulsa [B] si quieres abrirlo)." \
    "MS-CUENTAS con 2 instancias UP (8081, 8082) y MS-TRANSACCIONES con 1."
  wait_slide_footer "Probar balanceo Round Robin (20 peticiones)"
}

slide_04() {
  slide_chrome 4 "BLOQUE 2/6" "Balanceo HTTP Round Robin (20 peticiones)" "Persona B" "0:50-1:40"
  printf '\n  %sEndpoint: GET %s/api/cuentas/instancia  (x20)%s\n\n' "$C_CYAN" "$GATEWAY" "$C_RESET"
  : > "$TMP/balanceo.txt"
  local i code inst ok_cnt=0
  for i in $(seq 1 20); do
    code="$(api_req GET "$GATEWAY/api/cuentas/instancia" "" 5)"
    [ "$code" = "200" ] && ok_cnt=$((ok_cnt + 1))
    inst="$(get_header "X-Service-Instance")"; [ -z "$inst" ] && inst="sin-cabecera"
    printf '%s %s\n' "$code" "$inst" >> "$TMP/balanceo.txt"
  done
  box_top "DISTRIBUCION POR INSTANCIA" "$C_GREEN"
  sort "$TMP/balanceo.txt" | uniq -c | while read -r cnt code inst; do
    local pct=$(( (cnt * 100) / 20 ))
    local filled=$((cnt > 20 ? 20 : cnt))
    local bar_str col="$C_GREEN"
    bar_str="$(repeat_char '█' "$filled")$(repeat_char '░' "$((20 - filled))")"
    [ "$code" != "200" ] && col="$C_RED"
    echo "$inst" | grep -q 'ms-cuentas-2' && [ "$code" = "200" ] && col="$C_CYAN"
    box_line "$(printf '%-20s [%s]  %s  %2d/20 (%3d%%)' "$inst" "$code" "$bar_str" "$cnt" "$pct")" "$col" "$C_GREEN"
  done
  box_bottom "$C_GREEN"
  local pcol="$C_GREEN"; [ "$ok_cnt" -ne 20 ] && pcol="$C_RED"
  printf '\n  %s[ RESULTADO: %d/20 RESPUESTAS 200 OK · REPARTO EQUILIBRADO ]%s\n' "$pcol" "$ok_cnt" "$C_RESET"
  write_notes "Veinte peticiones, diez y diez, cero errores. Parejo, como debe ser."
  wait_slide_footer "Bloque 3: Transferencia P2P (transferir 25)"
}

slide_05() {
  local use_cache="${1:-0}" code
  slide_chrome 5 "BLOQUE 3/6" "Comunicación entre servicios: Transferencia \$25" "Persona B" "1:40-2:25"
  printf '\n  %sCliente ─POST :8080─▶ [ms-transacciones :8083] ─Eureka─▶ [ms-cuentas] ─ACID─▶ PRIMARY%s\n\n' "$C_CYAN" "$C_RESET"

  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_TX_OK_FILE" ] || [ ! -f "$CACHE_TX_OK_FILE" ]; then
    local payload="{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":25,\"motivo\":\"Demo video\"}"
    code="$(api_req POST "$GATEWAY/api/transacciones/transferir" "$payload" 10)"
    cp "$BODY_FILE" "$TMP/cache_tx_ok.json"
    printf '%s' "$code" > "$TMP/cache_tx_ok.code"
    CACHE_TX_OK_FILE="$TMP/cache_tx_ok.json"
  else
    code="$(cat "$TMP/cache_tx_ok.code")"
  fi

  local bcol="$C_YELLOW"; [ "$code" = "201" ] || [ "$code" = "200" ] && bcol="$C_GREEN"
  local fields msg cod sal ic nbd pol
  fields="$(extract_transfer_fields "$CACHE_TX_OK_FILE" | tr -d '\r')"
  IFS='|' read -r msg cod sal ic nbd pol <<< "$fields"
  [ "$nbd" != "-" ] && LAST_TX_NODO="$nbd"
  [ "$cod" != "-" ] && LAST_TX_CODIGO="$cod"

  box_top "COMPROBANTE DE TRANSFERENCIA  [ HTTP $code ]" "$bcol"
  box_line "Estado / Mensaje   : $msg" "$bcol" "$bcol"
  box_line "Comprobante        : $cod       Monto: \$25.00 ($ORIGEN -> $DESTINO)" "$C_WHITE" "$bcol"
  box_line "Nuevo Saldo Origen : \$$sal" "$C_WHITE" "$bcol"
  box_line "Instancia Cuentas  : $ic  (resuelta via Eureka)" "$C_CYAN" "$bcol"
  box_line "Nodo Base de Datos : $nbd" "$C_YELLOW" "$bcol"
  box_line "Politica Enrutado  : $pol" "$C_WHITE" "$bcol"
  box_bottom "$bcol"
  write_notes \
    "201 Created, comprobante emitido, instanciaCuentas demuestra la llamada por Eureka." \
    "En ms-cuentas, debito y credito van en una transaccion ACID con bloqueo ordenado."
  wait_slide_footer "Error controlado: transferir 9999"
}

slide_06() {
  local use_cache="${1:-0}" code
  slide_chrome 6 "BLOQUE 3/6" "Validación de negocio y rechazo controlado (\$9999)" "Persona B" "1:40-2:25"
  printf '\n  %sReferencia escritura previa (%s): nodoBD = %s%s\n\n' "$C_CYAN" "$LAST_TX_CODIGO" "$LAST_TX_NODO" "$C_RESET"

  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_TX_ERR_FILE" ] || [ ! -f "$CACHE_TX_ERR_FILE" ]; then
    local payload="{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":9999,\"motivo\":\"Demo video\"}"
    code="$(api_req POST "$GATEWAY/api/transacciones/transferir" "$payload" 10)"
    cp "$BODY_FILE" "$TMP/cache_tx_err.json"
    printf '%s' "$code" > "$TMP/cache_tx_err.code"
    CACHE_TX_ERR_FILE="$TMP/cache_tx_err.json"
  else
    code="$(cat "$TMP/cache_tx_err.code")"
  fi

  local bcol="$C_RED"; [ "$code" = "409" ] && bcol="$C_YELLOW"
  local fields msg cod sal ic nbd pol
  fields="$(extract_transfer_fields "$CACHE_TX_ERR_FILE" | tr -d '\r')"
  IFS='|' read -r msg cod sal ic nbd pol <<< "$fields"

  box_top "RECHAZO CONTROLADO  [ HTTP $code ]" "$bcol"
  box_line "Mensaje devuelto   : $msg" "$bcol" "$bcol"
  box_line "Monto solicitado   : \$9999.00  (excede saldo disponible)" "$C_WHITE" "$bcol"
  box_line "Integridad ACID    : Saldo intacto, sin comprobante emitido" "$C_GREEN" "$bcol"
  box_line "Auditoria nodoBD   : $nbd" "$C_CYAN" "$bcol"
  box_bottom "$bcol"
  write_notes \
    "'409, saldo insuficiente. Error controlado y el saldo no se toca.'" \
    "Pasar la palabra a C: 'C, y la base de datos?'"
  wait_slide_footer "Bloque 4: Persistencia replicada (20 lecturas)"
}

render_lecturas_box() {
  local bcol="${1:-$C_GREEN}"
  : > "$TMP/lecturas.txt"
  local i u code node fb ok_cnt=0 fb_cnt=0
  for i in $(seq 1 10); do
    for u in "cuentas/$ORIGEN/contactos" "transacciones/historial/$ORIGEN"; do
      code="$(api_req GET "$GATEWAY/api/$u" "" 5)"
      [ "$code" = "200" ] && ok_cnt=$((ok_cnt + 1))
      node="$(get_header "X-Db-Node")"; [ -z "$node" ] && node="desconocido"
      fb="$(get_header "X-Db-Fallback")"; [ -z "$fb" ] && fb="false"
      [ "$fb" = "true" ] && fb_cnt=$((fb_cnt + 1))
      printf '%s|%s|%s\n' "$code" "$node" "$fb" >> "$TMP/lecturas.txt"
    done
  done
  box_top "20 LECTURAS ORDINARIAS (contactos + historial)" "$bcol"
  sort "$TMP/lecturas.txt" | uniq -c | while read -r line; do
    local cnt rest code node fb filled bar_str col
    cnt="$(echo "$line" | awk '{print $1}')"
    rest="$(echo "$line" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')"
    code="$(echo "$rest" | cut -d'|' -f1)"
    node="$(echo "$rest" | cut -d'|' -f2)"
    fb="$(echo "$rest" | cut -d'|' -f3)"
    filled=$((cnt > 12 ? 12 : cnt))
    bar_str="$(repeat_char '█' "$filled")$(repeat_char '░' "$((12 - filled))")"
    col="$C_GREEN"; [ "$fb" = "true" ] && col="$C_YELLOW"; [ "$code" != "200" ] && col="$C_RED"
    box_line "$(printf '%2d/20 [%s] %s  %s  fb=%s' "$cnt" "$code" "$bar_str" "$node" "$fb")" "$col" "$bcol"
  done
  box_bottom "$bcol"
  LECT_OK="$ok_cnt"
  LECT_FB="$fb_cnt"
}

slide_07() {
  slide_chrome 7 "BLOQUE 4/6" "Persistencia replicada: Enrutamiento Primary vs Réplicas" "Persona C" "2:25-3:10"
  printf '\n  %sEscritura previa -> %s  |  Lecturas -> REPLICA_1 / REPLICA_2%s\n\n' "$C_CYAN" "$LAST_TX_NODO" "$C_RESET"
  render_lecturas_box "$C_GREEN"
  printf '\n  %s[ %s/20 LECTURAS 200 OK · REPARTO ENTRE REPLICAS (recovery=true) ]%s\n' "$C_GREEN" "$LECT_OK" "$C_RESET"
  write_notes \
    "La transferencia previa fue a PRIMARY (recovery=false)." \
    "Estas 20 lecturas: mitad REPLICA_1 y mitad REPLICA_2, recovery=true, con su propia IP."
  wait_slide_footer "Lectura critica RYOW (saldo-critico)"
}

slide_08() {
  slide_chrome 8 "BLOQUE 4/6" "Consistencia inmediata: Lectura crítica (RYOW)" "Persona C" "2:25-3:10"
  printf '\n'
  box_top "PROBLEMA Y SOLUCION (Read-Your-Own-Writes)" "$C_CYAN"
  box_line "● Las replicas WAL pueden ir un instante atrasadas tras una escritura." "$C_WHITE" "$C_CYAN"
  box_line "● /saldo-critico fuerza lectura al PRIMARIO para ver el saldo al instante." "$C_WHITE" "$C_CYAN"
  box_bottom "$C_CYAN"
  printf '\n'
  local code
  code="$(api_req GET "$GATEWAY/api/cuentas/$ORIGEN/saldo-critico" "" 5)"
  box_top "LECTURA CRITICA  [ GET /api/cuentas/$ORIGEN/saldo-critico ]" "$C_GREEN"
  if [ "$code" = "200" ]; then
    local fields sal nbd pol
    fields="$(extract_critico_fields "$BODY_FILE" | tr -d '\r')"
    IFS='|' read -r sal nbd pol <<< "$fields"
    box_line "Saldo inmediato    : \$$sal" "$C_GREEN" "$C_GREEN"
    box_line "Nodo Base de Datos : $nbd" "$C_CYAN" "$C_GREEN"
    box_line "Politica Enrutado  : $pol" "$C_YELLOW" "$C_GREEN"
  else
    box_line "HTTP $code al consultar saldo-critico" "$C_RED" "$C_GREEN"
  fi
  box_bottom "$C_GREEN"
  write_notes "Directo al primario, con el saldo ya descontado (475.00). Read-your-own-writes."
  wait_slide_footer "Bloque 5a: Simulacion de caida de instancia en vivo"
}

slide_09() {
  local use_cache="${1:-0}"
  slide_chrome 9 "BLOQUE 5a/6" "Simulación de fallo: Caída de ms-cuentas-2 en vivo" "Persona C" "3:10-3:45"

  if [ "$use_cache" -eq 1 ] && [ -n "$LAST_BURST_SUMMARY" ]; then
    printf '\n'
    box_top "RESUMEN ULTIMA RAFAGA EN VIVO" "$C_CYAN"
    box_line "$LAST_BURST_SUMMARY" "$C_GREEN" "$C_CYAN"
    box_line "Pulsa [R] si quieres volver a iniciar el trafico en vivo." "$C_YELLOW" "$C_CYAN"
    box_bottom "$C_CYAN"
    wait_slide_footer "Bloque 5b: Caida de replica PostgreSQL"
    return
  fi

  printf '\n'
  box_top "CONTROL EN VIVO (SOLO PULSA [ESPACIO / →] EN CADA FASE)" "$C_YELLOW"
  box_line "1) Trafico activo -> pulsa tecla para TUMBAR ms-cuentas-2" "$C_WHITE" "$C_YELLOW"
  box_line "2) Solo responde :8081 (0 errores) -> pulsa tecla para ARRANCAR :8082" "$C_WHITE" "$C_YELLOW"
  box_line "3) No esperar arranque (~25s) -> pulsa tecla para CORTAR trafico" "$C_WHITE" "$C_YELLOW"
  box_bottom "$C_YELLOW"
  printf '\n'

  : > "$TMP/trafico.log"
  (
    local hdr="$TMP/traf_hdr.txt" code inst ts col
    while :; do
      code="$(curl -s --max-time 3 -o /dev/null -D "$hdr" -w '%{http_code}' "$GATEWAY/api/cuentas/$ORIGEN" 2>/dev/null)" || code="000"
      [ -z "$code" ] && code="000"
      inst="$(grep -i '^X-Service-Instance:' "$hdr" 2>/dev/null | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/\r$//')"
      [ -z "$inst" ] && inst="sin-instancia"
      ts="$(date +%T)"
      printf '%s\n' "$code" >> "$TMP/trafico.log"
      col="$C_GREEN"
      if [ "$code" != "200" ]; then col="$C_RED"
      elif echo "$inst" | grep -q 'ms-cuentas-2'; then col="$C_CYAN"
      fi
      printf '  %s[%s]  %s  %s%s\n' "$col" "$ts" "$code" "$inst" "$C_RESET"
      sleep 0.3
    done
  ) &
  TRAFICO_PID=$!

  local phase=1 abort_act=""
  while :; do
    read_slide_key
    if [ "$ACT" = "QUIT" ] || [ "$ACT" = "HOME" ] || [ "$ACT" = "PREV" ]; then
      abort_act="$ACT"; break
    fi
    if [ "$ACT" = "EUREKA" ]; then open_eureka; continue; fi
    if [ "$phase" -eq 1 ]; then
      phase=2
      printf '\n  %s>>> [ACCION] Ejecutando: docker compose stop ms-cuentas-2 ...%s\n' "$C_MAGENTA" "$C_RESET"
      (
        docker compose stop ms-cuentas-2 >/dev/null 2>&1
        printf '  %s>>> [OK] ms-cuentas-2 detenida. 100%% absorbido por ms-cuentas-1!%s\n' "$C_GREEN" "$C_RESET"
      ) &
      BG_DOCKER_PID=$!
      printf '  %s>>> [FASE 2/3] Pulsa [ESPACIO/→] para ARRANCAR ms-cuentas-2%s\n' "$C_YELLOW" "$C_RESET"
    elif [ "$phase" -eq 2 ]; then
      phase=3
      printf '\n  %s>>> [ACCION] Ejecutando: docker compose start ms-cuentas-2 ...%s\n' "$C_MAGENTA" "$C_RESET"
      (
        docker compose start ms-cuentas-2 >/dev/null 2>&1
        printf '  %s>>> [OK] docker compose start ms-cuentas-2 lanzado (~25s JVM).%s\n' "$C_CYAN" "$C_RESET"
      ) &
      BG_DOCKER_PID=$!
      printf '  %s>>> [FASE 3/3] Pulsa [ESPACIO/→] para cortar trafico y pasar a Persona A%s\n' "$C_YELLOW" "$C_RESET"
    else
      break
    fi
  done

  if [ "$TRAFICO_PID" -gt 0 ]; then
    kill "$TRAFICO_PID" 2>/dev/null || true
    wait "$TRAFICO_PID" 2>/dev/null || true
    TRAFICO_PID=0
  fi
  if [ "$BG_DOCKER_PID" -gt 0 ]; then
    wait "$BG_DOCKER_PID" 2>/dev/null || true
    BG_DOCKER_PID=0
  fi
  if [ -n "$abort_act" ]; then ACT="$abort_act"; return; fi

  local total errs col
  total="$(wc -l < "$TMP/trafico.log" | tr -d ' ')"
  errs="$(grep -vc '^200$' "$TMP/trafico.log" || true)"
  LAST_BURST_SUMMARY="Total peticiones: $total  |  Exitosas (200): $((total - errs))  |  Errores (!=200): $errs"
  col="$C_GREEN"; [ "$errs" -gt 0 ] && col="$C_RED"
  printf '\n'
  box_top "RESUMEN DE ALTA DISPONIBILIDAD" "$col"
  box_line "$LAST_BURST_SUMMARY" "$col" "$col"
  box_line "Eureka dio de baja la instancia y Gateway reintento GET sin errores." "$C_WHITE" "$col"
  box_bottom "$col"
  write_notes "Cero errores para el usuario. La prendemos y regresa sola. Pasar palabra a A."
  wait_slide_footer "Bloque 5b: Persona A (Caida replica PostgreSQL)"
}

slide_10() {
  slide_chrome 10 "BLOQUE 5b/6" "Simulación de fallo: Réplica PostgreSQL" "Persona A" "3:45-4:20"
  printf '\n\n'
  box_top "ESCENARIO EN CALIENTE: CAIDA DE REPLICA DE BASE DE DATOS" "$C_YELLOW"
  box_line "" "$C_WHITE" "$C_YELLOW"
  box_line "  ● Que pasa si muere una replica PostgreSQL mientras llegan lecturas?" "$C_WHITE" "$C_YELLOW"
  box_line "  ● El aspecto @UsarNodo captura el fallo y rescata la lectura" "$C_WHITE" "$C_YELLOW"
  box_line "    en la otra replica sana (X-Db-Fallback: true)." "$C_WHITE" "$C_YELLOW"
  box_line "" "$C_WHITE" "$C_YELLOW"
  box_line "  ACCION SIGUIENTE: docker compose stop replica1  +  20 lecturas" "$C_CYAN" "$C_YELLOW"
  box_line "" "$C_WHITE" "$C_YELLOW"
  box_bottom "$C_YELLOW"
  write_notes "'Ahora lo pesado: apagamos una replica de la base de datos.'"
  wait_slide_footer "Detener replica1 y lanzar 20 lecturas"
}

slide_11() {
  slide_chrome 11 "BLOQUE 5b/6" "replica1 detenida -> Failover transparente en lecturas" "Persona A" "3:45-4:20"
  printf '\n  %s$ docker compose stop replica1%s\n' "$C_CYAN" "$C_RESET"
  docker compose stop replica1 2>&1 | sed 's/^/  /'
  printf '\n'
  render_lecturas_box "$C_YELLOW"
  printf '\n  %s[ %s/20 RESPUESTAS 200 OK · TODAS EN REPLICA_2 · FALLBACK=%s RESCATADAS ]%s\n' "$C_GREEN" "$LECT_OK" "$LECT_FB" "$C_RESET"
  write_notes \
    "Todas las lecturas dan 200, todas en REPLICA_2." \
    "Las fallback=true se intentaron en la caida y se rescataron solas."
  wait_slide_footer "Consultar salud de replicas (estado)"
}

render_db_estado_box() {
  local title="$1" code
  code="$(api_req GET "$GATEWAY/api/cuentas/db/estado" "" 5)"
  box_top "$title" "$C_CYAN"
  if [ "$code" = "200" ]; then
    case "$JSON_TOOL" in
      jq)
        local srv
        srv="$(jq -r '.servicio // empty' "$BODY_FILE" 2>/dev/null)"
        [ -n "$srv" ] && box_line "Consultado en instancia: $srv" "$C_DIM" "$C_CYAN"
        jq -r '.replicas[] | "\(.nodo)|\(.available)|\(.consecutiveSuccesses)|\(.lastReplayLsn // "-")"' "$BODY_FILE" 2>/dev/null | \
          while IFS='|' read -r nodo avail succ lsn; do
            local badge col="$C_RED"
            badge="[✗ CAIDA  · available=false]"
            if [ "$avail" = "true" ]; then badge="[● ACTIVA · available=true ]"; col="$C_GREEN"; fi
            box_line "$(printf '%-10s %s  exitos=%-3s LSN=%s' "$nodo" "$badge" "$succ" "$lsn")" "$col" "$C_CYAN"
          done
        ;;
      python3|python)
        "$JSON_TOOL" - "$BODY_FILE" <<'PY' | tr -d '\r' | while IFS='|' read -r kind f1 f2 f3 f4; do
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    if d.get("servicio"):
        print(f"SRV|{d['servicio']}|||")
    for rep in d.get("replicas", []):
        print(f"REP|{rep.get('nodo')}|{str(rep.get('available')).lower()}|{rep.get('consecutiveSuccesses')}|{rep.get('lastReplayLsn')}")
except Exception:
    pass
PY
          if [ "$kind" = "SRV" ]; then
            box_line "Consultado en instancia: $f1" "$C_DIM" "$C_CYAN"
          else
            local badge col="$C_RED"
            badge="[✗ CAIDA  · available=false]"
            if [ "$f2" = "true" ]; then badge="[● ACTIVA · available=true ]"; col="$C_GREEN"; fi
            box_line "$(printf '%-10s %s  exitos=%-3s LSN=%s' "$f1" "$badge" "$f3" "$f4")" "$col" "$C_CYAN"
          fi
        done
        ;;
      *) box_line "$(cat "$BODY_FILE")" "$C_WHITE" "$C_CYAN" ;;
    esac
  else
    box_line "HTTP $code al consultar db/estado" "$C_RED" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
}

slide_12() {
  slide_chrome 12 "BLOQUE 5b/6" "Detección automática de réplica caída (sondeo 3s)" "Persona A" "3:45-4:20"
  printf '\n'
  render_db_estado_box "SALUD DE REPLICAS (/api/cuentas/db/estado)"
  printf '\n'
  box_top "MECANISMO DE DETECCION" "$C_DIM"
  box_line "● ReplicaHealthTracker sondea cada 3 segundos con pg_is_in_recovery()." "$C_WHITE" "$C_DIM"
  box_line "● Al fallar, REPLICA_1 sale de la ronda sin afectar al cliente." "$C_WHITE" "$C_DIM"
  box_bottom "$C_DIM"
  write_notes "Cada 3s se revisa salud: REPLICA_1 fuera de ronda. 'Y cuando vuelve?'"
  wait_slide_footer "Arrancar replica1 (docker compose start replica1)"
}

slide_13() {
  slide_chrome 13 "BLOQUE 5b/6" "Recuperación de replica1 (streaming WAL + 2/2 chequeos)" "Persona A" "3:45-4:20"
  printf '\n  %s$ docker compose start replica1%s\n' "$C_CYAN" "$C_RESET"
  docker compose start replica1 2>&1 | sed 's/^/  /'
  printf '\n'
  box_top "SINCRONIZACION AUTOMATICA EN CURSO" "$C_GREEN"
  box_line "[✓] Contenedor replica1 arrancado." "$C_GREEN" "$C_GREEN"
  box_line "[~] Alcanzando al primario por streaming WAL..." "$C_YELLOW" "$C_GREEN"
  box_line "[~] Debe superar 2 chequeos seguidos (2 x 3s) para volver a la ronda." "$C_CYAN" "$C_GREEN"
  box_bottom "$C_GREEN"
  printf '\n  %s[TIP] Habla ~8 segundos y luego pulsa [ESPACIO / →] para ver estado!%s\n' "$C_YELLOW" "$C_RESET"
  write_notes "Se pone al dia con el primario, pasa 2 chequeos seguidos y vuelve sin tocar nada."
  wait_slide_footer "Comprobar retorno automatico (estado)"
}

slide_14() {
  slide_chrome 14 "BLOQUE 5b/6" "Retorno automático de replica1 al Round-Robin" "Persona A" "3:45-4:20"
  printf '\n'
  render_db_estado_box "SALUD DE REPLICAS TRAS RECUPERACION (/api/cuentas/db/estado)"
  printf '\n  %s[TIP] Si REPLICA_1 aun muestra chequeo 1/2, pulsa [R] para refrescar en 1s.%s\n' "$C_DIM" "$C_RESET"
  write_notes "REPLICA_1 available=true! Vuelve al Round-Robin sin tocar nada a mano."
  wait_slide_footer "Bloque 6: Conclusiones (A, B y C)"
}

slide_15() {
  slide_chrome 15 "BLOQUE 6/6" "Conclusiones técnicas del equipo" "A, B y C" "4:20-5:00"
  printf '\n'
  printf ' %s┌─ A · DECISIONES ──────┐ ┌─ B · LIMITACIONES ────┐ ┌─ C · MEJORAS ─────────┐%s\n' "$C_CYAN" "$C_RESET"
  local rows=(
    "· BD por @UsarNodo:|· Sin failover del|· Failover automatico"
    "  escritura -> PRIMARY|  primario si se cae|  (Patroni / repmgr)"
    "  lectura -> REPLICAS|· Eureka unico (SPOF)|· Claves idempotencia"
    "· Round Robin + sondeo|· /movimiento-interno|  en transferencias"
    "  de salud 2 de 2|  expuesto en Gateway|· Retry de conexion en"
    "· Eureka sin cache +|· Limite diario no se|  ms-transacciones"
    "  retry GET (0 err P03)|  reinicia solo|· Health Eureka real"
    "· Flyway advisory lock|· Sin idempotencia en|· Bloquear ruta interna"
    "  en arranque paralelo|  timeout de ms-cuentas|  + Sagas / Outbox"
  )
  local r c1 c2 c3
  for r in "${rows[@]}"; do
    c1="$(echo "$r" | cut -d'|' -f1)"
    c2="$(echo "$r" | cut -d'|' -f2)"
    c3="$(echo "$r" | cut -d'|' -f3)"
    printf ' %s│%s%s%s│ │%s%s%s│ │%s%s%s│%s\n' \
      "$C_GREEN" "$C_WHITE" "$(pad_fixed "$c1" 23)" "$C_YELLOW" \
      "$C_WHITE" "$(pad_fixed "$c2" 23)" "$C_CYAN" \
      "$C_WHITE" "$(pad_fixed "$c3" 23)" "$C_CYAN" "$C_RESET"
  done
  printf ' %s└───────────────────────┘ └───────────────────────┘ └───────────────────────┘%s\n\n' "$C_DIM" "$C_RESET"
  box_top "MENSAJE DE CIERRE (LOS TRES)" "$C_CYAN"
  box_line '  "Mas de uno de todo, y saber esquivar al que falla.' "$C_CYAN" "$C_CYAN"
  box_line '   Eso es un sistema distribuido. Gracias!"' "$C_CYAN" "$C_CYAN"
  box_bottom "$C_CYAN"
  wait_slide_footer "Volver a Portada (Q=salir)"
}

# --- Motor PowerPoint ---

SLIDES=(
  slide_01 slide_02 slide_03 slide_04 slide_05
  slide_06 slide_07 slide_08 slide_09 slide_10
  slide_11 slide_12 slide_13 slide_14 slide_15
)

block_to_idx() {
  case "$1" in
    B1) echo 0 ;; B2) echo 2 ;; B3) echo 4 ;;
    B4) echo 6 ;; B5) echo 8 ;; B6) echo 14 ;;
    *)  echo 0 ;;
  esac
}

run_deck() {
  local idx="$1" use_cache=0
  [ "$DECK_START" -le 0 ] && DECK_START=$(date +%s)
  while [ "$idx" -ge 0 ] && [ "$idx" -lt "${#SLIDES[@]}" ]; do
    "${SLIDES[$idx]}" "$use_cache"
    use_cache=0
    case "$ACT" in
      PREV)
        [ "$idx" -eq 0 ] && { ACT="PORTADA"; return; }
        idx=$((idx - 1))
        use_cache=1
        ;;
      REPEAT) continue ;;
      HOME)   ACT="PORTADA"; return ;;
      QUIT)   ACT="QUIT"; return ;;
      UTILS)
        show_utils_panel
        [ "$ACT" = "QUIT" ] && return
        if [[ "$ACT" =~ ^B[1-6]$ ]]; then idx="$(block_to_idx "$ACT")"; fi
        ;;
      B[1-6]) idx="$(block_to_idx "$ACT")" ;;
      *)      idx=$((idx + 1)) ;;
    esac
  done
  ACT="PORTADA"
}

show_portada() {
  while true; do
    clear_safe
    printf '%s╔%s╗%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"
    printf '%s║ %s%s%s ║%s\n' "$C_CYAN" "${C_BOLD}${C_CYAN}" "$(pad_fixed "BILLETERA DIGITAL DISTRIBUIDA  ·  PRESENTACION INTERACTIVA" 74)" "$C_CYAN" "$C_RESET"
    printf '%s║ %s%s%s ║%s\n' "$C_CYAN" "$C_DIM" "$(pad_fixed "Spring Boot 3.4 · Eureka · API Gateway · PostgreSQL 17 (WAL)" 74)" "$C_CYAN" "$C_RESET"
    printf '%s╚%s╝%s\n\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"

    printf '  %s┌─ PERSONA A ──────────┐ ┌─ PERSONA B ──────────┐ ┌─ PERSONA C ──────────┐%s\n' "$C_WHITE" "$C_RESET"
    printf '  %s│ 1. Arquitectura      │ │ 2. Descubrimiento    │ │ 4. Persistencia WAL  │%s\n' "$C_GREEN" "$C_RESET"
    printf '  %s│ 5b. Fallo Replica PG │ │ 3. Transferencias    │ │ 5a. Fallo Instancia  │%s\n' "$C_CYAN" "$C_RESET"
    printf '  %s│ 6. Decisiones        │ │ 6. Limitaciones      │ │ 6. Mejoras           │%s\n' "$C_YELLOW" "$C_RESET"
    printf '  %s└──────────────────────┘ └──────────────────────┘ └──────────────────────┘%s\n\n' "$C_WHITE" "$C_RESET"

    box_top "ESTADO DEL ENTORNO ANTES DE GRABAR" "$C_DIM"
    [ ! -f "$REPO_DIR/.env" ] && box_line "● Falta .env en el proyecto -> pulsa [U] -> [P] Preparacion limpia" "$C_YELLOW" "$C_DIM"
    local ps_out total=0 healthy=0
    if ps_out="$(docker compose ps -a --format '{{.Name}}|{{.State}}|{{.Status}}' 2>/dev/null)"; then
      total="$(echo "$ps_out" | grep -c '|' || true)"
      healthy="$(echo "$ps_out" | grep -c 'healthy' || true)"
      local col="$C_YELLOW"; [ "$healthy" -ge 8 ] && col="$C_GREEN"
      box_line "● Contenedores : $healthy/8 healthy (visibles: $total)" "$col" "$C_DIM"
    else
      box_line "● Docker       : Daemon apagado (abre Docker antes de grabar)" "$C_RED" "$C_DIM"
    fi
    local sinfo
    if sinfo="$(get_saldo_line | tr -d '\r')"; then
      local s c l col="$C_GREEN" tip=" [LISTO]"
      s="$(echo "$sinfo" | cut -d'|' -f1)"; c="$(echo "$sinfo" | cut -d'|' -f2)"; l="$(echo "$sinfo" | cut -d'|' -f3)"
      if awk -v v="${c:-0}" 'BEGIN{exit !(v+0 > 0)}'; then
        col="$C_YELLOW"; tip=" [REINICIAR CON U->P]"
      fi
      box_line "● Cuenta $ORIGEN : saldo=\$$s | usado=\$$c/\$$l$tip" "$col" "$C_DIM"
    else
      box_line "● Gateway :8080: Sin respuesta aun" "$C_DIM" "$C_DIM"
    fi
    box_bottom "$C_DIM"

    printf '\n%s%s%s\n' "$C_DIM" "$(repeat_char '─' 78)" "$C_RESET"
    printf '  %s► Pulsa [ESPACIO / ENTER / →] para COMENZAR (Diapositiva 1/15)%s\n' "${C_BOLD}${C_GREEN}" "$C_RESET"
    local nlbl="OFF"; [ "$SHOW_NOTES" -eq 1 ] && nlbl="ON"
    printf '    %s[1-6] Ir a Bloque   [U] Utilidades/Prep   [V] Notas:%-3s   [B] Eureka   [Q] Salir%s\n' "$C_DIM" "$nlbl" "$C_RESET"

    read_slide_key
    case "$ACT" in
      QUIT)   return ;;
      EUREKA) open_eureka ;;
      NOTES)  SHOW_NOTES=$((1 - SHOW_NOTES)) ;;
      PREP)   show_clean_prep ;;
      UTILS)
        show_utils_panel
        [ "$ACT" = "QUIT" ] && return
        if [[ "$ACT" =~ ^B[1-6]$ ]]; then run_deck "$(block_to_idx "$ACT")"; fi
        ;;
      B[1-6]) run_deck "$(block_to_idx "$ACT")" ;;
      NEXT|REPEAT)
        DECK_START=$(date +%s)
        run_deck 0
        ;;
      *) ;;
    esac
    [ "$ACT" = "QUIT" ] && return
  done
}

show_portada
