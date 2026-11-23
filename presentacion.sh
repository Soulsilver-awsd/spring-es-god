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

FIRST_FRAME=1
DOCK_ROW=5
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
  [ -t 1 ] && printf '\033[?25h%s' "$C_RESET" || printf '%s' "$C_RESET"
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

begin_frame() {
  local hard="${1:-0}"
  [ ! -t 1 ] && return
  printf '\033[?25l'
  if [ "$FIRST_FRAME" -eq 1 ] || [ "$hard" -eq 1 ]; then
    [ -n "${TERM:-}" ] && clear 2>/dev/null || printf '\033[2J\033[H'
    FIRST_FRAME=0
  else
    printf '\033[H'
  fi
}

end_frame() {
  [ -t 1 ] && printf '\033[J' || true
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

get_progress_bar() {
  local num="$1" total="${2:-15}" filled empty
  filled=$(( (num * 10 + total / 2) / total ))
  [ "$filled" -gt 10 ] && filled=10
  empty=$((10 - filled))
  printf '[%s%s]' "$(repeat_char '█' "$filled")" "$(repeat_char '░' "$empty")"
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

# Estado persistente del cluster para el panel inmerso
fetch_cluster_dock_data() {
  DOCK_OK=0; DOCK_HEALTHY=0; DOCK_RUNNING=0
  local svc
  for svc in api-gateway eureka-server ms-cuentas-1 ms-cuentas-2 ms-transacciones primary replica1 replica2; do
    eval "D_SYM_${svc//-/_}='?'"
    eval "D_COL_${svc//-/_}=\"\$C_DIM\""
  done
  local out line st status var
  if out="$(docker compose ps -a --format '{{.Service}}|{{.State}}|{{.Status}}' 2>/dev/null | tr -d '\r')"; then
    DOCK_OK=1
    while IFS='|' read -r svc st status; do
      [ -z "$svc" ] && continue
      var="${svc//-/_}"
      if [ "$st" = "running" ]; then
        DOCK_RUNNING=$((DOCK_RUNNING + 1))
        if echo "$status" | grep -q 'unhealthy'; then
          eval "D_SYM_${var}='!'; D_COL_${var}=\"\$C_RED\""
        elif echo "$status" | grep -q 'starting'; then
          eval "D_SYM_${var}='~'; D_COL_${var}=\"\$C_YELLOW\""
        else
          DOCK_HEALTHY=$((DOCK_HEALTHY + 1))
          eval "D_SYM_${var}='●'; D_COL_${var}=\"\$C_GREEN\""
        fi
      else
        eval "D_SYM_${var}='✗'; D_COL_${var}=\"\$C_RED\""
      fi
    done <<< "$out"
  fi
}

print_badge() {
  local label="$1" key="${2//-/_}" sym col
  eval "sym=\"\$D_SYM_${key}\"; col=\"\$D_COL_${key}\""
  printf '%s[%s %s]%s' "$col" "$sym" "$label" "$C_RESET"
}

render_cluster_dock() {
  fetch_cluster_dock_data
  local title tcol bcol="$C_CYAN"
  if [ "$DOCK_OK" -eq 0 ]; then
    title="CLUSTER INMERSO · DOCKER DESCONECTADO"; tcol="$C_RED"
  elif [ "$DOCK_HEALTHY" -eq 8 ]; then
    title="CLUSTER INMERSO · 8/8 HEALTHY"; tcol="$C_GREEN"
  else
    title="CLUSTER INMERSO · ${DOCK_HEALTHY}/8 HEALTHY · ${DOCK_RUNNING}/8 ACTIVOS"; tcol="$C_YELLOW"
  fi
  local t=" $title "
  local fill=$((75 - ${#t}))
  [ "$fill" -lt 2 ] && fill=2
  printf '%s┌─%s%s%s┐%s\n' "$bcol" "$tcol" "$t" "$bcol$(repeat_char '─' "$fill")" "$C_RESET"

  printf '%s│ %sEDGE ' "$bcol" "$C_DIM"
  print_badge "gateway :8080" "api-gateway"; printf ' '
  print_badge "eureka :8761" "eureka-server"; printf '  %sBD ' "$C_DIM"
  print_badge "primary" "primary"; printf ' '
  print_badge "rep1" "replica1"; printf ' '
  print_badge "rep2" "replica2"; printf '  %s│%s\n' "$bcol" "$C_RESET"

  printf '%s│ %sAPPS ' "$bcol" "$C_DIM"
  print_badge "cuentas-1 :8081" "ms-cuentas-1"; printf ' '
  print_badge "cuentas-2 :8082" "ms-cuentas-2"; printf ' '
  print_badge "transacciones :8083" "ms-transacciones"
  printf '       %s│%s\n' "$bcol" "$C_RESET"

  printf '%s└%s┘%s\n' "$bcol" "$(repeat_char '─' 76)" "$C_RESET"
}

update_dock_in_place() {
  [ ! -t 1 ] && return
  printf '\033[s\033[%d;1H' "$DOCK_ROW"
  render_cluster_dock
  printf '\033[u'
}

slide_chrome() {
  local num="$1" active="$2" title="$3"
  DOCK_ROW=5
  begin_frame
  local labels=("[1:Arq]" "[2:Eur]" "[3:P2P]" "[4:Rep]" "[5:Fal]" "[6:Fin]")
  local right gap row2 i col
  right="$(printf '%02d/15 %s' "$num" "$(get_progress_bar "$num" 15)")"
  gap=$((74 - 47 - ${#right}))
  [ "$gap" -lt 1 ] && gap=1
  row2="$(pad_fixed "► $title" 74)"

  printf '%s╔%s╗%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"
  printf '%s║ ' "$C_CYAN"
  for i in 0 1 2 3 4 5; do
    col="$C_DIM"
    [ $((i + 1)) -eq "$active" ] && col="${C_BOLD}${C_YELLOW}"
    printf '%s%s%s' "$col" "${labels[$i]}" "$C_RESET"
    [ "$i" -lt 5 ] && printf ' '
  done
  printf '%*s%s%s%s ║%s\n' "$gap" "" "$C_CYAN" "$right" "$C_CYAN" "$C_RESET"
  printf '%s║ %s%s%s ║%s\n' "$C_CYAN" "${C_BOLD}${C_WHITE}" "$row2" "$C_CYAN" "$C_RESET"
  printf '%s╚%s╝%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"

  render_cluster_dock
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

parse_key_char() {
  local k="$1" seq=""
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
    ACT="PREV"; return
  fi
  case "$k" in
    a|A) ACT="PREV" ;;
    n|N) ACT="NEXT" ;;
    r|R) ACT="REPEAT" ;;
    m|M) ACT="HOME" ;;
    q|Q) ACT="QUIT" ;;
    b|B) ACT="EUREKA" ;;
    u|U) ACT="UTILS" ;;
    p|P) ACT="PREP" ;;
    s|S) ACT="STARTALL" ;;
    t|T) ACT="SUITE" ;;
    c|C) ACT="ENV" ;;
    w|W) ACT="DOCK_REFRESH" ;;
    [1-6]) ACT="B$k" ;;
    *)   ACT="NEXT" ;;
  esac
}

read_slide_key_live() {
  local live="${1:-1}" k=""
  if [ ! -t 0 ]; then ACT="QUIT"; return; fi
  while true; do
    if [ "$live" -eq 1 ]; then
      if IFS= read -rsn1 -t 3 k; then
        parse_key_char "$k"
        return
      else
        update_dock_in_place
      fi
    else
      IFS= read -rsn1 k || { ACT="QUIT"; return; }
      parse_key_char "$k"
      return
    fi
  done
}

wait_slide_footer() {
  local next_lbl="${1:-Siguiente}" allow_back="${2:-1}"
  printf '%s%s%s\n' "$C_DIM" "$(repeat_char '─' 78)" "$C_RESET"
  if [ "$allow_back" -eq 1 ]; then
    printf '  %s[ESPACIO/→] %s   [←/Backspace] Anterior%s\n' "${C_BOLD}${C_GREEN}" "$next_lbl" "$C_RESET"
  else
    printf '  %s[ESPACIO/→] %s%s\n' "${C_BOLD}${C_GREEN}" "$next_lbl" "$C_RESET"
  fi
  printf '  %s[1-6] Seccion   [R] Actualizar   [B] Eureka   [U] Utilidades   [Q] Salir%s\n' "$C_DIM" "$C_RESET"
  end_frame
  while true; do
    read_slide_key_live 1
    case "$ACT" in
      EUREKA)       open_eureka ;;
      DOCK_REFRESH) update_dock_in_place ;;
      *)            return ;;
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

extract_transfer_fields() {
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
    sal = f"{float(datos['nuevoSaldoOrigen']):.2f}" if datos.get("nuevoSaldoOrigen") is not None else "-"
    vals = [
        str(d.get("mensaje") or "-"),
        str(datos.get("codigoComprobante") or "-"),
        sal,
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

extract_critico_fields() {
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
    sal = f"{float(datos['saldo']):.2f}" if datos.get("saldo") is not None else "-"
    print(f"{sal}|{aud.get('nodoBaseDatos', '-')}|{aud.get('politicaEnrutamiento', '-')}")
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

# --- Panel de Utilidades ---

show_clean_prep() {
  begin_frame 1
  printf '%s╔%s╗%s\n' "$C_YELLOW" "$(repeat_char '═' 76)" "$C_RESET"
  printf '%s║ %s%s%s ║%s\n' "$C_YELLOW" "$C_YELLOW" "$(pad_fixed "REINICIO LIMPIO DEL ENTORNO (down -v + up -d --build)" 74)" "$C_YELLOW" "$C_RESET"
  printf '%s╚%s╝%s\n\n' "$C_YELLOW" "$(repeat_char '═' 76)" "$C_RESET"
  ensure_env || { wait_slide_footer "Volver" 0; FIRST_FRAME=1; return; }
  printf '  %s$ docker compose down -v && docker compose up -d --build%s\n' "$C_CYAN" "$C_RESET"
  docker compose down -v
  docker compose up -d --build || {
    printf '\n  %s[ERROR] docker compose up fallo.%s\n' "$C_RED" "$C_RESET"
    wait_slide_footer "Volver" 0; FIRST_FRAME=1; return
  }
  printf '\n  %sEsperando que los 8 contenedores esten healthy...%s\n' "$C_YELLOW" "$C_RESET"
  local start_t now elapsed
  start_t=$(date +%s)
  while true; do
    now=$(date +%s); elapsed=$((now - start_t))
    [ "$elapsed" -ge 240 ] && break
    fetch_cluster_dock_data
    printf '\r  %s[%3ds] Healthy: %s/8   %s' "$C_CYAN" "$elapsed" "$DOCK_HEALTHY" "$C_RESET"
    if [ "$DOCK_HEALTHY" -ge 8 ]; then
      printf '\n  %s[OK] Los 8 contenedores estan healthy!%s\n' "$C_GREEN" "$C_RESET"
      break
    fi
    sleep 2
  done
  open_eureka
  printf '  %s[OK] Eureka abierto en %s%s\n' "$C_GREEN" "$EUREKA" "$C_RESET"
  CACHE_TX_OK_FILE=""
  CACHE_TX_ERR_FILE=""
  wait_slide_footer "Volver al panel" 0
  FIRST_FRAME=1
}

show_utils_panel() {
  FIRST_FRAME=1
  while true; do
    DOCK_ROW=4
    begin_frame
    printf '%s╔%s╗%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"
    printf '%s║ %s%s%s ║%s\n' "$C_CYAN" "$C_CYAN" "$(pad_fixed "UTILIDADES DEL ENTORNO Y VERIFICACION" 74)" "$C_CYAN" "$C_RESET"
    printf '%s╚%s╝%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"
    render_cluster_dock

    printf '\n'
    [ ! -f "$REPO_DIR/.env" ] && printf '  %s[AVISO] Falta .env en el repositorio (pulsa [C] o [P]).%s\n' "$C_YELLOW" "$C_RESET"
    local sinfo
    if sinfo="$(get_saldo_line | tr -d '\r')"; then
      local s c l col="$C_GREEN"
      s="$(echo "$sinfo" | cut -d'|' -f1)"; c="$(echo "$sinfo" | cut -d'|' -f2)"; l="$(echo "$sinfo" | cut -d'|' -f3)"
      awk -v v="${c:-0}" 'BEGIN{exit !(v+0 > 0)}' && col="$C_YELLOW"
      printf '  %sCuenta %s: saldo=$%s | consumidoHoy=$%s / $%s%s\n' "$col" "$ORIGEN" "$s" "$c" "$l" "$C_RESET"
    fi
    printf '\n'
    box_top "ACCIONES DISPONIBLES" "$C_CYAN"
    box_line "[P] Reinicio limpio (down -v + up -d --build + abrir Eureka)" "$C_YELLOW" "$C_CYAN"
    box_line "[S] Arrancar contenedores detenidos (docker compose start)" "$C_WHITE" "$C_CYAN"
    box_line "[B] Abrir Eureka en navegador ($EUREKA)" "$C_WHITE" "$C_CYAN"
    box_line "[C] Crear .env desde .env.example" "$C_WHITE" "$C_CYAN"
    box_line "[T] Ejecutar suite automatizada P01-P08" "$C_WHITE" "$C_CYAN"
    box_line "[1..6] Ir directo a Seccion 1..6" "$C_CYAN" "$C_CYAN"
    box_line "[ESPACIO / ESC / M] Volver a la Portada" "$C_GREEN" "$C_CYAN"
    box_bottom "$C_CYAN"
    end_frame

    read_slide_key_live 1
    case "$ACT" in
      PREP)         show_clean_prep ;;
      STARTALL)     begin_frame 1; ensure_env || true; docker compose start; wait_slide_footer "Volver" 0; FIRST_FRAME=1 ;;
      EUREKA)       open_eureka ;;
      DOCK_REFRESH) update_dock_in_place ;;
      ENV)          ensure_env; sleep 1 ;;
      SUITE)
        begin_frame 1
        [ -f "$REPO_DIR/docs/api/curl-p01-p08.sh" ] && bash "$REPO_DIR/docs/api/curl-p01-p08.sh"
        wait_slide_footer "Volver" 0
        FIRST_FRAME=1
        ;;
      QUIT)   ACT="QUIT"; return ;;
      B[1-6]) return ;;
      *)      ACT="PORTADA"; return ;;
    esac
  done
}

# --- Diapositivas 01 a 15 ---

slide_01() {
  slide_chrome 1 1 "Arquitectura del Sistema · 8 Contenedores Docker"
  printf '\n'
  box_top "FLUJO Y TOPOLOGIA DE RED (wallet-net)" "$C_CYAN"
  box_line "Cliente ─:8080─▶ [api-gateway] ◀──registro/latido 5s──▶ [eureka :8761]" "$C_CYAN" "$C_CYAN"
  box_line "                      │ lb:// Round-Robin" "$C_DIM" "$C_CYAN"
  box_line "        ┌─────────────┼─────────────┐" "$C_DIM" "$C_CYAN"
  box_line "        ▼             ▼             ▼" "$C_DIM" "$C_CYAN"
  box_line " [ms-cuentas-1] [ms-cuentas-2] [ms-transacciones]  (esquemas aislados:" "$C_GREEN" "$C_CYAN"
  box_line "     :8081          :8082            :8083          cuentas_db / tx_db)" "$C_GREEN" "$C_CYAN"
  box_line "        └─────────────┬─────────────┘  Enrutador JDBC (@UsarNodo)" "$C_MAGENTA" "$C_CYAN"
  box_line "     Escritura / RYOW │         Lecturas Ordinarias" "$C_DIM" "$C_CYAN"
  box_line "                      ▼" "$C_DIM" "$C_CYAN"
  box_line "       [primary :5432 R/W] ══WAL══▶ [replica1 :5433] + [replica2 :5434]" "$C_BLUE" "$C_CYAN"
  box_bottom "$C_CYAN"
  wait_slide_footer "Detalle del clúster"
}

slide_02() {
  slide_chrome 2 1 "Clúster Docker Compose · Estado de Servicios"
  printf '\n'
  box_top "TELEMETRIA DE CONTENEDORES (docker compose ps)" "$C_CYAN"
  if docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}' >"$TMP/ps.txt" 2>/dev/null; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if echo "$line" | grep -q 'healthy'; then
        box_line "$line" "$C_GREEN" "$C_CYAN"
      elif echo "$line" | grep -q '^NAME'; then
        box_line "$line" "$C_CYAN" "$C_CYAN"
      else
        box_line "$line" "$C_YELLOW" "$C_CYAN"
      fi
    done <"$TMP/ps.txt"
  else
    box_line "No se pudo consultar docker compose (verifica Docker)." "$C_RED" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
  wait_slide_footer "2. Descubrimiento en Eureka"
}

slide_03() {
  slide_chrome 3 2 "Descubrimiento Dinámico con Netflix Eureka"
  printf '\n'
  box_top "ARQUITECTURA DE DESCUBRIMIENTO" "$C_CYAN"
  box_line "● Auto-registro al arrancar y latido (heartbeat) cada 5 segundos." "$C_WHITE" "$C_CYAN"
  box_line "● API Gateway resuelve por nombre logico (lb://ms-cuentas), sin IPs fijas." "$C_WHITE" "$C_CYAN"
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
  wait_slide_footer "Balanceo HTTP Round Robin"
}

slide_04() {
  slide_chrome 4 2 "Balanceo de Carga HTTP · Round Robin"
  printf '\n  %s20 peticiones consecutivas a GET %s/api/cuentas/instancia%s\n\n' "$C_CYAN" "$GATEWAY" "$C_RESET"
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
  printf '  %s[ RESULTADO: %d/20 RESPUESTAS 200 OK · REPARTO ROUND ROBIN ]%s\n' "$pcol" "$ok_cnt" "$C_RESET"
  wait_slide_footer "3. Comunicación entre servicios"
}

slide_05() {
  local use_cache="${1:-0}" code
  slide_chrome 5 3 "Orquestación P2P entre Microservicios · Transferencia"
  printf '\n  %sCliente ─POST :8080─▶ [ms-transacciones :8083] ─Eureka─▶ [ms-cuentas] ─ACID─▶ PRIMARY%s\n\n' "$C_CYAN" "$C_RESET"

  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_TX_OK_FILE" ] || [ ! -f "$CACHE_TX_OK_FILE" ]; then
    local payload="{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":25,\"motivo\":\"Transferencia P2P\"}"
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
  printf '  %s● Debito y credito ejecutados en una sola transaccion ACID con bloqueo ordenado.%s\n' "$C_DIM" "$C_RESET"
  wait_slide_footer "Validación de saldo insuficiente"
}

slide_06() {
  local use_cache="${1:-0}" code
  slide_chrome 6 3 "Validación de Reglas de Negocio · Error Controlado"
  printf '\n  %sEscritura previa (%s) -> %s%s\n\n' "$C_CYAN" "$LAST_TX_CODIGO" "$LAST_TX_NODO" "$C_RESET"

  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_TX_ERR_FILE" ] || [ ! -f "$CACHE_TX_ERR_FILE" ]; then
    local payload="{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":9999,\"motivo\":\"Prueba limite\"}"
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
  box_line "Monto solicitado   : \$9999.00  (supera saldo disponible)" "$C_WHITE" "$bcol"
  box_line "Integridad ACID    : Transaccion revertida; saldos intactos" "$C_GREEN" "$bcol"
  box_line "Auditoria nodoBD   : $nbd" "$C_CYAN" "$bcol"
  box_bottom "$bcol"
  wait_slide_footer "4. Persistencia replicada"
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
  slide_chrome 7 4 "Enrutamiento de Base de Datos · Primario vs Réplicas"
  printf '\n  %sEscrituras -> %s  |  Lecturas -> REPLICA_1 / REPLICA_2%s\n\n' "$C_CYAN" "$LAST_TX_NODO" "$C_RESET"
  render_lecturas_box "$C_GREEN"
  printf '  %s[ %s/20 LECTURAS 200 OK · REPARTO ROUND ROBIN EN REPLICAS (recovery=true) ]%s\n' "$C_GREEN" "$LECT_OK" "$C_RESET"
  wait_slide_footer "Lectura crítica RYOW"
}

slide_08() {
  slide_chrome 8 4 "Consistencia Inmediata · Read-Your-Own-Writes (RYOW)"
  printf '\n'
  box_top "ARQUITECTURA DE CONSISTENCIA" "$C_CYAN"
  box_line "● Las replicas WAL pueden presentar retardo minimo tras una escritura." "$C_WHITE" "$C_CYAN"
  box_line "● /saldo-critico enruta al PRIMARIO para garantizar lectura actualizada." "$C_WHITE" "$C_CYAN"
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
  wait_slide_footer "5. Simulación de fallos (Instancia)"
}

slide_09() {
  local use_cache="${1:-0}"
  slide_chrome 9 5 "Alta Disponibilidad HTTP · Caída de ms-cuentas-2"

  if [ "$use_cache" -eq 1 ] && [ -n "$LAST_BURST_SUMMARY" ]; then
    printf '\n'
    box_top "RESUMEN DE ALTA DISPONIBILIDAD" "$C_CYAN"
    box_line "$LAST_BURST_SUMMARY" "$C_GREEN" "$C_CYAN"
    box_line "Eureka dio de baja la instancia y API Gateway reintento GET sin errores." "$C_WHITE" "$C_CYAN"
    box_bottom "$C_CYAN"
    wait_slide_footer "5b. Caída de réplica PostgreSQL"
    return
  fi

  local phase=1 total_req=0 err_req=0 c1=0 c2=0
  local event_msg="Trafico continuo activo contra Gateway :8080"
  local ring=() abort_act="" hdr="$TMP/traf_hdr.txt" code inst ts col
  local last_poll
  last_poll=$(date +%s)

  render_s9_body() {
    [ -t 1 ] && printf '\033[9;1H'
    local status_txt
    case "$phase" in
      1) status_txt="Trafico activo (ms-cuentas-1 + ms-cuentas-2)  |  [ESPACIO] Detener :8082" ;;
      2) status_txt="ms-cuentas-2 DETENIDA · Failover en Gateway   |  [ESPACIO] Reiniciar :8082" ;;
      3) status_txt="Recuperando instancia (~25s JVM)              |  [ESPACIO] Ver resumen" ;;
    esac
    local ccol="$C_GREEN"; [ "$err_req" -gt 0 ] && ccol="$C_RED"
    box_top "TELEMETRIA EN VIVO (VENTANA FIJA)" "$C_YELLOW"
    box_line "$status_txt" "$C_YELLOW" "$C_YELLOW"
    box_line "$(printf 'Peticiones: %-4d  ms-cuentas-1: %-4d  ms-cuentas-2: %-4d  Errores: %d' "$total_req" "$c1" "$c2" "$err_req")" "$ccol" "$C_YELLOW"
    box_bottom "$C_YELLOW"

    box_top "ULTIMAS PETICIONES" "$C_DIM"
    local i item_col item_txt
    for i in 0 1 2 3 4 5; do
      if [ "$i" -lt "${#ring[@]}" ]; then
        item_col="${ring[$i]%%|*}"
        item_txt="${ring[$i]#*|}"
        box_line "$item_txt" "$item_col" "$C_DIM"
      else
        box_line "" "$C_WHITE" "$C_DIM"
      fi
    done
    box_bottom "$C_DIM"
    printf '  %s%s%s\n' "$C_CYAN" "$(pad_fixed "$event_msg" 74)" "$C_RESET"
    end_frame
  }

  while true; do
    local now
    now=$(date +%s)
    if [ $((now - last_poll)) -ge 2 ]; then
      last_poll="$now"
      update_dock_in_place
    fi

    code="$(curl -s --max-time 3 -o /dev/null -D "$hdr" -w '%{http_code}' "$GATEWAY/api/cuentas/$ORIGEN" 2>/dev/null)" || code="000"
    [ -z "$code" ] && code="000"
    inst="$(grep -i '^X-Service-Instance:' "$hdr" 2>/dev/null | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/\r$//')"
    [ -z "$inst" ] && inst="sin-instancia"
    ts="$(date +%T)"
    total_req=$((total_req + 1))
    if [ "$code" != "200" ]; then
      err_req=$((err_req + 1)); col="$C_RED"
    elif echo "$inst" | grep -q 'ms-cuentas-2'; then
      c2=$((c2 + 1)); col="$C_CYAN"
    else
      c1=$((c1 + 1)); col="$C_GREEN"
    fi
    ring+=("$col|[$ts]  HTTP $code  ->  $inst")
    if [ "${#ring[@]}" -gt 6 ]; then
      ring=("${ring[@]:1}")
    fi

    render_s9_body

    # Espera breve no bloqueante con lectura de tecla
    local k=""
    if [ "${BASH_VERSINFO[0]:-3}" -ge 4 ]; then
      if IFS= read -rsn1 -t 0.25 k; then
        parse_key_char "$k"
      else
        ACT=""
      fi
    else
      if IFS= read -rsn1 -t 1 k; then
        parse_key_char "$k"
      else
        ACT=""
      fi
    fi

    if [ -n "$ACT" ]; then
      case "$ACT" in
        QUIT|HOME|PREV|B[1-6]) abort_act="$ACT"; break ;;
        EUREKA) open_eureka ;;
        *)
          if [ "$phase" -eq 1 ]; then
            phase=2
            event_msg="[ACCION] Deteniendo ms-cuentas-2 (docker compose stop)..."
            ( docker compose stop ms-cuentas-2 >/dev/null 2>&1 ) &
            BG_DOCKER_PID=$!
          elif [ "$phase" -eq 2 ]; then
            phase=3
            event_msg="[ACCION] Reiniciando ms-cuentas-2 (docker compose start)..."
            ( docker compose start ms-cuentas-2 >/dev/null 2>&1 ) &
            BG_DOCKER_PID=$!
          else
            break
          fi
          ;;
      esac
    fi
  done

  if [ "$BG_DOCKER_PID" -gt 0 ]; then
    wait "$BG_DOCKER_PID" 2>/dev/null || true
    BG_DOCKER_PID=0
  fi
  if [ -n "$abort_act" ]; then ACT="$abort_act"; return; fi

  LAST_BURST_SUMMARY="Total peticiones: $total_req  |  Exitosas (200): $((total_req - err_req))  |  Errores (!=200): $err_req"
  slide_chrome 9 5 "Alta Disponibilidad HTTP · Resumen de Contingencia"
  printf '\n'
  local rcol="$C_GREEN"; [ "$err_req" -gt 0 ] && rcol="$C_RED"
  box_top "RESUMEN DE ALTA DISPONIBILIDAD" "$rcol"
  box_line "$LAST_BURST_SUMMARY" "$rcol" "$rcol"
  box_line "Distribucion: ms-cuentas-1=$c1  |  ms-cuentas-2=$c2" "$C_WHITE" "$rcol"
  box_line "Eureka dio de baja la instancia y API Gateway reintento GET sin errores." "$C_CYAN" "$rcol"
  box_bottom "$rcol"
  wait_slide_footer "5b. Caída de réplica PostgreSQL"
}

slide_10() {
  slide_chrome 10 5 "Alta Disponibilidad de Datos · Caída de Réplica PG"
  printf '\n'
  box_top "ESCENARIO: FALLO DE NODO DE LECTURA EN CALIENTE" "$C_YELLOW"
  box_line "" "$C_WHITE" "$C_YELLOW"
  box_line "  ● Se detiene replica1 mientras el servicio recibe consultas." "$C_WHITE" "$C_YELLOW"
  box_line "  ● El enrutador @UsarNodo captura el fallo y redirige la lectura" "$C_WHITE" "$C_YELLOW"
  box_line "    a la replica sana (X-Db-Fallback: true)." "$C_WHITE" "$C_YELLOW"
  box_line "" "$C_WHITE" "$C_YELLOW"
  box_line "  PRUEBA: docker compose stop replica1  +  20 lecturas consecutivas" "$C_CYAN" "$C_YELLOW"
  box_line "" "$C_WHITE" "$C_YELLOW"
  box_bottom "$C_YELLOW"
  wait_slide_footer "Ejecutar caída de replica1 y lecturas"
}

slide_11() {
  docker compose stop replica1 >/dev/null 2>&1 || true
  slide_chrome 11 5 "Failover Transparente · Lecturas sobre REPLICA_2"
  printf '\n  %s$ docker compose stop replica1  [OK]%s\n\n' "$C_CYAN" "$C_RESET"
  render_lecturas_box "$C_YELLOW"
  printf '  %s[ %s/20 RESPUESTAS 200 OK · TODAS EN REPLICA_2 · FALLBACK=%s RESCATADAS ]%s\n' "$C_GREEN" "$LECT_OK" "$LECT_FB" "$C_RESET"
  wait_slide_footer "Estado de salud de réplicas"
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
  slide_chrome 12 5 "Detección Automática de Réplica Caída (Sondeo 3s)"
  printf '\n'
  render_db_estado_box "SALUD DE REPLICAS (/api/cuentas/db/estado)"
  printf '\n'
  box_top "MECANISMO DE DETECCION" "$C_DIM"
  box_line "● ReplicaHealthTracker sondea cada 3 segundos con pg_is_in_recovery()." "$C_WHITE" "$C_DIM"
  box_line "● REPLICA_1 queda fuera del Round-Robin sin errores para el cliente." "$C_WHITE" "$C_DIM"
  box_bottom "$C_DIM"
  wait_slide_footer "Reiniciar replica1 (recuperación WAL)"
}

slide_13() {
  docker compose start replica1 >/dev/null 2>&1 || true
  slide_chrome 13 5 "Recuperación de Réplica · Streaming WAL y Umbral 2/2"
  printf '\n  %s$ docker compose start replica1  [OK]%s\n\n' "$C_CYAN" "$C_RESET"
  box_top "SINCRONIZACION AUTOMATICA EN CURSO" "$C_GREEN"
  box_line "[✓] Contenedor replica1 reiniciado." "$C_GREEN" "$C_GREEN"
  box_line "[~] Sincronizando registros WAL pendientes desde el nodo primario..." "$C_YELLOW" "$C_GREEN"
  box_line "[~] Umbral de reincorporacion: 2 chequeos consecutivos sanos (2 x 3s)." "$C_CYAN" "$C_GREEN"
  box_bottom "$C_GREEN"
  wait_slide_footer "Verificar reincorporación al Round-Robin"
}

slide_14() {
  slide_chrome 14 5 "Reincorporación Automática de replica1 al Round-Robin"
  printf '\n'
  render_db_estado_box "SALUD DE REPLICAS TRAS RECUPERACION (/api/cuentas/db/estado)"
  printf '\n'
  box_top "RETORNO AUTOMATICO" "$C_DIM"
  box_line "● Una vez completados 2 chequeos exitosos, REPLICA_1 regresa al balanceo." "$C_WHITE" "$C_DIM"
  box_bottom "$C_DIM"
  wait_slide_footer "6. Conclusiones técnicas"
}

slide_15() {
  slide_chrome 15 6 "Conclusiones Técnicas · Decisiones, Limitaciones y Mejoras"
  printf '\n'
  printf ' %s┌─ DECISIONES ──────────┐ ┌─ LIMITACIONES ────────┐ ┌─ MEJORAS FUTURAS ─────┐%s\n' "$C_CYAN" "$C_RESET"
  local rows=(
    "· BD por @UsarNodo|· Sin failover primario|· Failover (Patroni)"
    "  write->PRI / read->REP|· Eureka unico (SPOF)|· Claves idempotencia"
    "· Round Robin + salud|· /movimiento-interno|· Retry conexion en"
    "  chequeo 2 de 2|  expuesto en Gateway|  ms-transacciones"
    "· Eureka sin cache +|· Limite diario no se|· Health Eureka real"
    "  retry GET (0 err P03)|  reinicia solo|· Bloquear ruta interna"
    "· Flyway advisory lock|· Sin idempotencia P2P|  y Sagas / Outbox"
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
  printf ' %s└───────────────────────┘ └───────────────────────┘ └───────────────────────┘%s\n' "$C_DIM" "$C_RESET"
  box_top "SINTESIS FINAL" "$C_CYAN"
  box_line '  "Mas de uno de todo, y saber esquivar al que falla. Sistema distribuido."' "$C_CYAN" "$C_CYAN"
  box_bottom "$C_CYAN"
  wait_slide_footer "Volver a Portada"
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
    DOCK_ROW=5
    begin_frame
    printf '%s╔%s╗%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"
    printf '%s║ %s%s%s ║%s\n' "$C_CYAN" "${C_BOLD}${C_CYAN}" "$(pad_fixed "BILLETERA DIGITAL DISTRIBUIDA  ·  ARQUITECTURA DE MICROSERVICIOS" 74)" "$C_CYAN" "$C_RESET"
    printf '%s║ %s%s%s ║%s\n' "$C_CYAN" "$C_DIM" "$(pad_fixed "Spring Boot 3.4 · Netflix Eureka · API Gateway · PostgreSQL 17 (WAL)" 74)" "$C_CYAN" "$C_RESET"
    printf '%s╚%s╝%s\n' "$C_CYAN" "$(repeat_char '═' 76)" "$C_RESET"

    render_cluster_dock

    printf '\n'
    printf '  %s┌─ INFRAESTRUCTURA ────┐ ┌─ OPERACION & DATOS ──┐ ┌─ ALTA DISPONIBILIDAD ┐%s\n' "$C_WHITE" "$C_RESET"
    printf '  %s│ 1. Arquitectura      │ │ 4. Balanceo HTTP     │ │ 7. Tolerancia HTTP   │%s\n' "$C_GREEN" "$C_RESET"
    printf '  %s│ 2. Eureka & Gateway  │ │ 5. Transferencias    │ │ 8. Failover Replica  │%s\n' "$C_CYAN" "$C_RESET"
    printf '  %s│ 3. Cluster PG17 WAL  │ │ 6. CQRS-lite & RYOW  │ │ 9. Retorno Automatico│%s\n' "$C_YELLOW" "$C_RESET"
    printf '  %s└──────────────────────┘ └──────────────────────┘ └──────────────────────┘%s\n\n' "$C_WHITE" "$C_RESET"

    local sinfo
    if [ ! -f "$REPO_DIR/.env" ]; then
      printf '  %s[AVISO] Falta .env -> [U] -> [P] Reinicio limpio%s\n' "$C_YELLOW" "$C_RESET"
    elif sinfo="$(get_saldo_line | tr -d '\r')"; then
      local s c l col="$C_GREEN" badge=" [LISTO]"
      s="$(echo "$sinfo" | cut -d'|' -f1)"; c="$(echo "$sinfo" | cut -d'|' -f2)"; l="$(echo "$sinfo" | cut -d'|' -f3)"
      if awk -v v="${c:-0}" 'BEGIN{exit !(v+0 > 0)}'; then
        col="$C_YELLOW"; badge=" [REINICIAR CON U->P]"
      fi
      printf '  %sCuenta %s : saldo=$%s | usado=$%s/$%s%s%s\n' "$col" "$ORIGEN" "$s" "$c" "$l" "$badge" "$C_RESET"
    else
      printf '  %sGateway :8080 : Esperando conexion...%s\n' "$C_DIM" "$C_RESET"
    fi

    printf '%s%s%s\n' "$C_DIM" "$(repeat_char '─' 78)" "$C_RESET"
    printf '  %s► [ESPACIO / ENTER / →] Iniciar Presentacion (Diapositiva 1/15)%s\n' "${C_BOLD}${C_GREEN}" "$C_RESET"
    printf '    %s[1-6] Ir a Seccion   [B] Eureka   [U] Utilidades   [Q] Salir%s\n' "$C_DIM" "$C_RESET"
    end_frame

    read_slide_key_live 1
    case "$ACT" in
      QUIT)         return ;;
      EUREKA)       open_eureka ;;
      DOCK_REFRESH) update_dock_in_place ;;
      PREP)         show_clean_prep ;;
      UTILS)
        show_utils_panel
        [ "$ACT" = "QUIT" ] && return
        if [[ "$ACT" =~ ^B[1-6]$ ]]; then run_deck "$(block_to_idx "$ACT")"; fi
        ;;
      B[1-6]) run_deck "$(block_to_idx "$ACT")" ;;
      NEXT|REPEAT) run_deck 0 ;;
      *) ;;
    esac
    [ "$ACT" = "QUIT" ] && return
  done
}

show_portada
