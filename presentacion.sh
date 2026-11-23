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

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
REPO_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd || pwd)"
[ -f "$REPO_DIR/docker-compose.yml" ] || REPO_DIR="$PWD"
cd "$REPO_DIR" || exit 1

GATEWAY="${GATEWAY:-http://localhost:8080}"
EUREKA="${EUREKA:-http://localhost:8761}"
ORIGEN="0991112233"
DESTINO="0984445566"

FIRST_FRAME=1
FORCE_CLEAR=0
WIN_W=80
WIN_H=25
UI_W=78
INNER_W=74
PAD_L=1
PAD_T=0
MARGIN=" "
DOCK_ROW=5
RESIZED=0

LAST_DOCK_SIG=""
LAST_DOCK_POLL=0
DOCK_BG_PID=0

LAST_TX_NODO="PRIMARY (recovery=false)"
LAST_TX_CODIGO="TX-2026-0001"
LAST_BURST_LINES=()
STOP_REP_MS=0
START_REP_MS=0
CACHE_PS_READY=0
CACHE_EUREKA_CODE=""
CACHE_BAL_READY=0
CACHE_TX_OK_FILE=""
CACHE_TX_ERR_FILE=""
CACHE_LECT07_READY=0
CACHE_LECT11_READY=0
CACHE_CRIT_CODE=""
CACHE_EST12_CODE=""
CACHE_EST14_CODE=""

TMP="$(mktemp -d)"
HEADERS_FILE="$TMP/headers.txt"
BODY_FILE="$TMP/body.json"
DOCK_RAW="$TMP/dock.raw"
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
CLR_EOL=""
[ -t 1 ] && CLR_EOL=$'\033[K'
LAST_SCREEN_ID=""

cleanup() {
  [ "$BG_DOCKER_PID" -gt 0 ] && kill "$BG_DOCKER_PID" 2>/dev/null || true
  [ "$DOCK_BG_PID" -gt 0 ] && kill "$DOCK_BG_PID" 2>/dev/null || true
  rm -rf "$TMP"
  [ -t 1 ] && printf '\033[?25h%s' "$C_RESET" || printf '%s' "$C_RESET"
}
trap cleanup EXIT INT TERM
trap 'RESIZED=1' WINCH 2>/dev/null || true

# Parser JSON con fallback si no hay jq
JSON_TOOL="raw"
if command -v jq >/dev/null 2>&1; then
  JSON_TOOL="jq"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import json" >/dev/null 2>&1; then
  JSON_TOOL="python3"
elif command -v python >/dev/null 2>&1 && python -c "import json" >/dev/null 2>&1; then
  JSON_TOOL="python"
fi

now_ms() {
  local m
  m="$(date +%s%3N 2>/dev/null || true)"
  if [[ "$m" =~ ^[0-9]+$ ]]; then
    echo "$m"
  else
    echo "$(date +%s)000"
  fi
}

fmt_ms_sec() {
  awk -v m="${1:-0}" 'BEGIN { printf "%.2f", m / 1000.0 }'
}

repeat_char() {
  local ch="$1" n="$2" out=""
  [ "$n" -le 0 ] && return
  printf -v out '%*s' "$n" ''
  printf '%s' "${out// /$ch}"
}

pad_fixed() {
  local txt="${1//$'\r'/}" w="$2"
  [ "$w" -le 0 ] && return
  local len=${#txt}
  if [ "$len" -gt "$w" ]; then
    [ "$w" -le 3 ] && printf '%s' "${txt:0:$w}" || printf '%s...' "${txt:0:$((w - 3))}"
  else
    printf '%s%*s' "$txt" "$((w - len))" ''
  fi
}

pad_center() {
  local txt="${1//$'\r'/}" w="$2"
  local len=${#txt}
  if [ "$len" -ge "$w" ]; then
    pad_fixed "$txt" "$w"
  else
    local l=$(( (w - len) / 2 ))
    local r=$((w - len - l))
    printf '%*s%s%*s' "$l" '' "$txt" "$r" ''
  fi
}

shopt -s checkwinsize 2>/dev/null || true

update_ui_metrics() {
  local w="${DEMO_COLS:-80}" h="${DEMO_LINES:-25}"
  if [ -t 1 ]; then
    if command -v tput >/dev/null 2>&1; then
      w="$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")"
      h="$(tput lines 2>/dev/null || echo "${LINES:-25}")"
    else
      w="${COLUMNS:-80}"; h="${LINES:-25}"
    fi
  fi
  [[ "$w" =~ ^[0-9]+$ ]] || w=80
  [[ "$h" =~ ^[0-9]+$ ]] || h=25

  local new_ui_w=$((w - 2))
  [ "$new_ui_w" -gt 100 ] && new_ui_w=100
  [ "$new_ui_w" -lt 64 ] && new_ui_w=64
  local new_pad_l=$(( (w - new_ui_w) / 2 ))
  [ "$new_pad_l" -lt 0 ] && new_pad_l=0
  local new_pad_t=0
  if [ -t 1 ] && [ "$h" -ge 28 ]; then
    new_pad_t=$(( (h - 24) / 3 ))
    [ "$new_pad_t" -gt 3 ] && new_pad_t=3
  fi
  if [ "$new_ui_w" -ne "$UI_W" ] || [ "$new_pad_l" -ne "$PAD_L" ] || [ "$new_pad_t" -ne "$PAD_T" ]; then
    FORCE_CLEAR=1
  fi
  WIN_W="$w"; WIN_H="$h"; UI_W="$new_ui_w"; INNER_W=$((new_ui_w - 4))
  PAD_L="$new_pad_l"; PAD_T="$new_pad_t"
  MARGIN="$(repeat_char ' ' "$new_pad_l")"
  RESIZED=0
}

ui_blank() { printf '%s\n' "$CLR_EOL"; }
ui_line() { printf '%s%s%s%s%s\n' "$MARGIN" "${1:-}" "${2:-}" "$C_RESET" "$CLR_EOL"; }

begin_frame() {
  local hard="${1:-0}"
  update_ui_metrics
  [ ! -t 1 ] && return
  printf '\033[?25l'
  if [ "$FIRST_FRAME" -eq 1 ] || [ "$hard" -eq 1 ] || [ "$FORCE_CLEAR" -eq 1 ]; then
    [ -n "${TERM:-}" ] && clear 2>/dev/null || printf '\033[2J\033[H'
    FIRST_FRAME=0
    FORCE_CLEAR=0
  else
    printf '\033[H'
  fi
  local i=0
  while [ "$i" -lt "$PAD_T" ]; do
    ui_blank
    i=$((i + 1))
  done
}

end_frame() {
  [ -t 1 ] && printf '\033[J' || true
}

get_progress_bar() {
  local num="$1" total="${2:-15}" w="${3:-10}" filled empty
  filled=$(( (num * w + total / 2) / total ))
  [ "$filled" -gt "$w" ] && filled="$w"
  empty=$((w - filled))
  printf '[%s%s]' "$(repeat_char '█' "$filled")" "$(repeat_char '░' "$empty")"
}

box_top() {
  local title=" $1 " col="${2:-$C_DIM}"
  local max_t=$((UI_W - 6))
  [ "${#title}" -gt "$max_t" ] && title="${title:0:$max_t}"
  local fill=$(( (UI_W - 3) - ${#title} ))
  [ "$fill" -lt 2 ] && fill=2
  printf '%s%s┌─%s%s┐%s%s\n' "$MARGIN" "$col" "$title" "$(repeat_char '─' "$fill")" "$C_RESET" "$CLR_EOL"
}

box_line() {
  local txt="$1" tcol="${2:-$C_WHITE}" bcol="${3:-$C_DIM}"
  printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$bcol" "$tcol" "$(pad_fixed "$txt" "$INNER_W")" "$bcol" "$C_RESET" "$CLR_EOL"
}

box_bottom() {
  local col="${1:-$C_DIM}"
  printf '%s%s└%s┘%s%s\n' "$MARGIN" "$col" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
}

write_divider() {
  printf '%s%s%s%s%s\n' "$MARGIN" "$C_DIM" "$(repeat_char '─' "$UI_W")" "$C_RESET" "$CLR_EOL"
}

# Estado persistente del cluster (cacheado + refresco asincrono)
parse_dock_raw() {
  DOCK_OK=0; DOCK_HEALTHY=0; DOCK_RUNNING=0
  local svc
  for svc in api-gateway eureka-server ms-cuentas-1 ms-cuentas-2 ms-transacciones primary replica1 replica2; do
    eval "D_SYM_${svc//-/_}='?'"
    eval "D_COL_${svc//-/_}=\"\$C_DIM\""
  done
  local sig_parts="" line st status var
  if [ -f "$DOCK_RAW" ]; then
    local status_flag
    status_flag="$(head -n 1 "$DOCK_RAW" 2>/dev/null || echo "ERR")"
    if [ "$status_flag" = "OK" ]; then
      DOCK_OK=1
      while IFS='|' read -r svc st status; do
        [ -z "$svc" ] && continue
        var="${svc//-/_}"
        sig_parts="${sig_parts};${svc}=${st}=${status}"
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
      done < <(tail -n +2 "$DOCK_RAW")
    fi
  fi
  DOCK_SIG="${DOCK_OK}|${DOCK_HEALTHY}|${DOCK_RUNNING}|${sig_parts}"
}

fetch_dock_sync() {
  local out
  if out="$(docker compose ps -a --format '{{.Service}}|{{.State}}|{{.Status}}' 2>/dev/null | tr -d '\r')"; then
    printf 'OK\n%s\n' "$out" > "$DOCK_RAW"
  else
    printf 'ERR\n' > "$DOCK_RAW"
  fi
  LAST_DOCK_POLL=$(date +%s)
  parse_dock_raw
}

start_dock_probe_bg() {
  if [ "$DOCK_BG_PID" -gt 0 ]; then
    if kill -0 "$DOCK_BG_PID" 2>/dev/null; then
      return
    fi
    wait "$DOCK_BG_PID" 2>/dev/null || true
    DOCK_BG_PID=0
    LAST_DOCK_POLL=$(date +%s)
    local prev_sig="$LAST_DOCK_SIG"
    parse_dock_raw
    [ "$DOCK_SIG" != "$prev_sig" ] && update_dock_in_place
    return
  fi
  local now
  now=$(date +%s)
  if [ $((now - LAST_DOCK_POLL)) -ge 2 ]; then
    (
      local out
      if out="$(docker compose ps -a --format '{{.Service}}|{{.State}}|{{.Status}}' 2>/dev/null | tr -d '\r')"; then
        printf 'OK\n%s\n' "$out" > "$TMP/dock.tmp" && mv "$TMP/dock.tmp" "$DOCK_RAW"
      else
        printf 'ERR\n' > "$TMP/dock.tmp" && mv "$TMP/dock.tmp" "$DOCK_RAW"
      fi
    ) &
    DOCK_BG_PID=$!
    LAST_DOCK_POLL="$now"
  fi
}

print_badge() {
  local label="$1" key="${2//-/_}" sym col
  eval "sym=\"\$D_SYM_${key}\"; col=\"\$D_COL_${key}\""
  printf '%s[%s %s]%s' "$col" "$sym" "$label" "$C_RESET"
}

render_cluster_dock() {
  [ ! -f "$DOCK_RAW" ] && fetch_dock_sync || parse_dock_raw
  LAST_DOCK_SIG="$DOCK_SIG"
  local title tcol bcol="$C_CYAN"
  if [ "$DOCK_OK" -eq 0 ]; then
    title="MONITOR EN VIVO · DOCKER DESCONECTADO"; tcol="$C_RED"
  elif [ "$DOCK_HEALTHY" -eq 8 ]; then
    title="MONITOR EN VIVO · 8/8 EN LINEA"; tcol="$C_GREEN"
  else
    title="MONITOR EN VIVO · ${DOCK_HEALTHY}/8 HEALTHY · ${DOCK_RUNNING}/8 ACTIVOS"; tcol="$C_YELLOW"
  fi
  local t=" $title "
  local fill=$(( (UI_W - 3) - ${#t} ))
  [ "$fill" -lt 2 ] && fill=2
  printf '%s%s┌─%s%s%s┐%s%s\n' "$MARGIN" "$bcol" "$tcol" "$t" "$bcol$(repeat_char '─' "$fill")" "$C_RESET" "$CLR_EOL"

  if [ "$INNER_W" -ge 74 ]; then
    local mid=$(( (INNER_W - 71) / 2 ))
    [ "$mid" -lt 2 ] && mid=2
    local rem1=$((INNER_W - (71 + mid)))
    [ "$rem1" -lt 0 ] && rem1=0
    printf '%s%s│ %sRED  ' "$MARGIN" "$bcol" "$C_DIM"
    print_badge "gateway :8080" "api-gateway"; printf ' '
    print_badge "eureka :8761" "eureka-server"; printf '%*s%sBD ' "$mid" "" "$C_DIM"
    print_badge "primary" "primary"; printf ' '
    print_badge "rep1" "replica1"; printf ' '
    print_badge "rep2" "replica2"; printf '%*s %s│%s%s\n' "$rem1" "" "$bcol" "$C_RESET" "$CLR_EOL"

    local rem2=$((INNER_W - 68))
    [ "$rem2" -lt 0 ] && rem2=0
    printf '%s%s│ %sAPPS ' "$MARGIN" "$bcol" "$C_DIM"
    print_badge "cuentas-1 :8081" "ms-cuentas-1"; printf ' '
    print_badge "cuentas-2 :8082" "ms-cuentas-2"; printf ' '
    print_badge "transacciones :8083" "ms-transacciones"
    printf '%*s %s│%s%s\n' "$rem2" "" "$bcol" "$C_RESET" "$CLR_EOL"
  else
    local rem1=$((INNER_W - 57)); [ "$rem1" -lt 0 ] && rem1=0
    printf '%s%s│ %sRED  ' "$MARGIN" "$bcol" "$C_DIM"
    print_badge "gw" "api-gateway"; printf ' '
    print_badge "eureka" "eureka-server"; printf '   %sBD ' "$C_DIM"
    print_badge "primary" "primary"; printf ' '
    print_badge "rep1" "replica1"; printf ' '
    print_badge "rep2" "replica2"; printf '%*s %s│%s%s\n' "$rem1" "" "$bcol" "$C_RESET" "$CLR_EOL"

    local rem2=$((INNER_W - 50)); [ "$rem2" -lt 0 ] && rem2=0
    printf '%s%s│ %sAPPS ' "$MARGIN" "$bcol" "$C_DIM"
    print_badge "cuentas-1" "ms-cuentas-1"; printf ' '
    print_badge "cuentas-2" "ms-cuentas-2"; printf ' '
    print_badge "transacciones" "ms-transacciones"
    printf '%*s %s│%s%s\n' "$rem2" "" "$bcol" "$C_RESET" "$CLR_EOL"
  fi

  printf '%s%s└%s┘%s%s\n' "$MARGIN" "$bcol" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
}

update_dock_in_place() {
  [ ! -t 1 ] && return
  printf '\033[s\033[%d;1H' "$DOCK_ROW"
  render_cluster_dock
  printf '\033[u'
}

slide_chrome() {
  local num="$1" active="$2" title="$3"
  begin_frame
  DOCK_ROW=$((PAD_T + 5))
  local labels tab_len bar_len=10
  if [ "$INNER_W" -lt 70 ]; then
    labels=("[1]" "[2]" "[3]" "[4]" "[5]" "[6]")
    tab_len=23
  else
    labels=("[1:Arq]" "[2:Eur]" "[3:P2P]" "[4:Rep]" "[5:Fal]" "[6:Fin]")
    tab_len=47
  fi
  [ "$INNER_W" -ge 88 ] && bar_len=14
  local right gap row2 i col
  right="$(printf '%02d/15 %s' "$num" "$(get_progress_bar "$num" 15 "$bar_len")")"
  gap=$((INNER_W - tab_len - ${#right}))
  [ "$gap" -lt 1 ] && gap=1
  row2="$(pad_fixed "► $title" "$INNER_W")"

  printf '%s%s╔%s╗%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '═' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
  printf '%s%s║ ' "$MARGIN" "$C_CYAN"
  for i in 0 1 2 3 4 5; do
    col="$C_DIM"
    [ $((i + 1)) -eq "$active" ] && col="${C_BOLD}${C_YELLOW}"
    printf '%s%s%s' "$col" "${labels[$i]}" "$C_RESET"
    [ "$i" -lt 5 ] && printf ' '
  done
  printf '%*s%s%s%s ║%s%s\n' "$gap" "" "$C_CYAN" "$right" "$C_CYAN" "$C_RESET" "$CLR_EOL"
  printf '%s%s║ %s%s%s ║%s%s\n' "$MARGIN" "$C_CYAN" "${C_BOLD}${C_WHITE}" "$row2" "$C_CYAN" "$C_RESET" "$CLR_EOL"
  printf '%s%s╚%s╝%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '═' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"

  render_cluster_dock
  if [ -t 1 ] && [ "$LAST_SCREEN_ID" != "S${num}" ]; then
    printf '\033[J'
  fi
  LAST_SCREEN_ID="S${num}"
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
  local live="${1:-1}" k="" tout=1
  [ "${BASH_VERSINFO[0]:-3}" -ge 4 ] && tout="0.2"
  if [ ! -t 0 ]; then ACT="QUIT"; return; fi
  while true; do
    if [ "$RESIZED" -eq 1 ]; then
      ACT="RESIZE"; return
    fi
    if [ "$live" -eq 1 ]; then
      if IFS= read -rsn1 -t "$tout" k; then
        parse_key_char "$k"
        return
      else
        if [ "$RESIZED" -eq 1 ]; then ACT="RESIZE"; return; fi
        start_dock_probe_bg
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
  write_divider
  if [ "$allow_back" -eq 1 ]; then
    local nav_line="  [ESPACIO/→] ${next_lbl}   [←/Backspace] Anterior"
    if [ "${#nav_line}" -gt "$UI_W" ]; then
      nav_line="  [ESPACIO/→] ${next_lbl}   [←] Anterior"
    fi
    ui_line "${C_BOLD}${C_GREEN}" "$nav_line"
  else
    ui_line "${C_BOLD}${C_GREEN}" "  [ESPACIO/→] $next_lbl"
  fi
  local help_line="  [1-6] Seccion   [R] Actualizar   [B] Eureka   [U] Utilidades   [Q] Salir"
  [ "$UI_W" -lt 76 ] && help_line="  [1-6] Sec   [R] Re-ejec   [B] Eureka   [U] Utils   [Q] Salir"
  ui_line "$C_DIM" "$help_line"
  end_frame
  while true; do
    read_slide_key_live 1
    case "$ACT" in
      EUREKA)       open_eureka ;;
      DOCK_REFRESH) fetch_dock_sync; update_dock_in_place ;;
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
      printf '%s  %s[OK] Archivo .env creado desde .env.example.%s\n' "$MARGIN" "$C_GREEN" "$C_RESET"
      return 0
    fi
    printf '%s  %s[ERROR] No existe .env ni .env.example.%s\n' "$MARGIN" "$C_RED" "$C_RESET"
    return 1
  fi
  return 0
}

write_three_col_cards() {
  local t1="$1" t2="$2" t3="$3" c1="$4" c2="$5" c3="$6"
  shift 6
  local cw_base=$(( (UI_W - 2) / 3 ))
  local rem=$(( (UI_W - 2) - cw_base * 3 ))
  local cw0=$cw_base cw1=$cw_base cw2=$cw_base
  [ "$rem" -ge 1 ] && cw0=$((cw0 + 1))
  [ "$rem" -ge 2 ] && cw1=$((cw1 + 1))
  local cws=($cw0 $cw1 $cw2)
  local titles=("$t1" "$t2" "$t3")
  local i t cw ci fill maxt

  printf '%s' "$MARGIN"
  for i in 0 1 2; do
    cw="${cws[$i]}"; maxt=$((cw - 3))
    t=" ${titles[$i]} "
    [ "${#t}" -gt "$maxt" ] && t="${t:0:$maxt}"
    fill=$(( (cw - 3) - ${#t} )); [ "$fill" -lt 1 ] && fill=1
    printf '%s┌─%s%s┐%s' "$C_CYAN" "$t" "$(repeat_char '─' "$fill")" "$C_RESET"
    [ "$i" -lt 2 ] && printf ' '
  done
  printf '%s\n' "$CLR_EOL"

  local row f1 f2 f3
  for row in "$@"; do
    f1="$(echo "$row" | cut -d'|' -f1)"
    f2="$(echo "$row" | cut -d'|' -f2)"
    f3="$(echo "$row" | cut -d'|' -f3)"
    printf '%s%s│%s%s%s│ %s│%s%s%s│ %s│%s%s%s│%s%s\n' \
      "$MARGIN" "$c1" "$C_WHITE" "$(pad_fixed "$f1" "$((cw0 - 2))")" "$c1" \
      "$c2" "$C_WHITE" "$(pad_fixed "$f2" "$((cw1 - 2))")" "$c2" \
      "$c3" "$C_WHITE" "$(pad_fixed "$f3" "$((cw2 - 2))")" "$c3" "$C_RESET" "$CLR_EOL"
  done

  printf '%s%s' "$MARGIN" "$C_DIM"
  for i in 0 1 2; do
    ci=$((cws[i] - 2))
    printf '└%s┘' "$(repeat_char '─' "$ci")"
    [ "$i" -lt 2 ] && printf ' '
  done
  printf '%s%s\n' "$C_RESET" "$CLR_EOL"
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
  LAST_SCREEN_ID="PREP"
  begin_frame 1
  printf '%s%s╔%s╗%s%s\n' "$MARGIN" "$C_YELLOW" "$(repeat_char '═' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
  printf '%s%s║ %s%s%s ║%s%s\n' "$MARGIN" "$C_YELLOW" "$C_YELLOW" "$(pad_fixed "REINICIO LIMPIO DEL ENTORNO (down -v + up -d --build)" "$INNER_W")" "$C_YELLOW" "$C_RESET" "$CLR_EOL"
  printf '%s%s╚%s╝%s%s\n' "$MARGIN" "$C_YELLOW" "$(repeat_char '═' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
  ui_blank
  ensure_env || { wait_slide_footer "Volver" 0; FIRST_FRAME=1; return; }
  ui_line "$C_CYAN" "  \$ docker compose down -v && docker compose up -d --build"
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
    fetch_dock_sync
    printf '\r  %s[%3ds] Healthy: %s/8   %s' "$C_CYAN" "$elapsed" "$DOCK_HEALTHY" "$C_RESET"
    if [ "$DOCK_HEALTHY" -ge 8 ]; then
      printf '\n  %s[OK] Los 8 contenedores estan healthy!%s\n' "$C_GREEN" "$C_RESET"
      break
    fi
    sleep 2
  done
  open_eureka
  printf '  %s[OK] Eureka abierto en %s%s\n' "$C_GREEN" "$EUREKA" "$C_RESET"
  CACHE_TX_OK_FILE=""; CACHE_TX_ERR_FILE=""
  wait_slide_footer "Volver al panel" 0
  FIRST_FRAME=1
}

show_utils_panel() {
  FIRST_FRAME=1
  LAST_SCREEN_ID="UTILS"
  while true; do
    begin_frame
    DOCK_ROW=$((PAD_T + 4))
    printf '%s%s╔%s╗%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '═' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    printf '%s%s║ %s%s%s ║%s%s\n' "$MARGIN" "$C_CYAN" "$C_CYAN" "$(pad_fixed "UTILIDADES DEL ENTORNO Y VERIFICACION" "$INNER_W")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    printf '%s%s╚%s╝%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '═' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    render_cluster_dock

    ui_blank
    if [ ! -f "$REPO_DIR/.env" ]; then
      ui_line "$C_YELLOW" "  [AVISO] Falta .env en el repositorio (pulsa [C] o [P])."
    fi
    local sinfo
    if sinfo="$(get_saldo_line | tr -d '\r')"; then
      local s c l col="$C_GREEN"
      s="$(echo "$sinfo" | cut -d'|' -f1)"; c="$(echo "$sinfo" | cut -d'|' -f2)"; l="$(echo "$sinfo" | cut -d'|' -f3)"
      awk -v v="${c:-0}" 'BEGIN{exit !(v+0 > 0)}' && col="$C_YELLOW"
      ui_line "$col" "  Cuenta $ORIGEN: saldo=\$$s | consumidoHoy=\$$c / \$$l"
    fi
    ui_blank
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
      RESIZE)       continue ;;
      PREP)         show_clean_prep ;;
      STARTALL)     begin_frame 1; ensure_env || true; docker compose start; fetch_dock_sync; wait_slide_footer "Volver" 0; FIRST_FRAME=1 ;;
      EUREKA)       open_eureka ;;
      DOCK_REFRESH) fetch_dock_sync; update_dock_in_place ;;
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
  ui_blank
  box_top "FLUJO Y TOPOLOGIA DE RED (wallet-net)" "$C_CYAN"
  if [ "$INNER_W" -ge 71 ]; then
    local pad=""
    [ "$INNER_W" -ge 86 ] && pad="      "
    box_line "${pad}Cliente ─:8080─► [api-gateway] ◄──registro/latido 5s──► [eureka :8761]" "$C_CYAN" "$C_CYAN"
    box_line "${pad}                      │ lb:// Round-Robin" "$C_DIM" "$C_CYAN"
    box_line "${pad}        ┌─────────────┼─────────────┐" "$C_DIM" "$C_CYAN"
    box_line "${pad}        ▼             ▼             ▼" "$C_DIM" "$C_CYAN"
    box_line "${pad} [ms-cuentas-1] [ms-cuentas-2] [ms-transacciones]  (esquemas aislados:" "$C_GREEN" "$C_CYAN"
    box_line "${pad}     :8081          :8082            :8083          cuentas_db / tx_db)" "$C_GREEN" "$C_CYAN"
    box_line "${pad}        └─────────────┬─────────────┘  Enrutador JDBC (@UsarNodo)" "$C_MAGENTA" "$C_CYAN"
    box_line "${pad}     Escritura / RYOW │         Lecturas Ordinarias" "$C_DIM" "$C_CYAN"
    box_line "${pad}                      ▼" "$C_DIM" "$C_CYAN"
    box_line "${pad}       [primary :5432 R/W] ══WAL══► [replica1 :5433] + [replica2 :5434]" "$C_BLUE" "$C_CYAN"
  else
    box_line "Cliente :8080►[gateway]◄─5s─►[eureka :8761]" "$C_CYAN" "$C_CYAN"
    box_line "                  │ lb:// Round-Robin" "$C_DIM" "$C_CYAN"
    box_line "       ┌──────────┼──────────┐" "$C_DIM" "$C_CYAN"
    box_line "       ▼          ▼          ▼" "$C_DIM" "$C_CYAN"
    box_line " [cuentas-1] [cuentas-2] [ms-tx]  (cuentas_db / tx_db)" "$C_GREEN" "$C_CYAN"
    box_line "     :8081      :8082     :8083" "$C_GREEN" "$C_CYAN"
    box_line "       └──────────┬──────────┘  @UsarNodo JDBC" "$C_MAGENTA" "$C_CYAN"
    box_line "   Write / RYOW   │    Lecturas" "$C_DIM" "$C_CYAN"
    box_line "                  ▼" "$C_DIM" "$C_CYAN"
    box_line " [primary:5432]═WAL═►[rep1:5433]+[rep2:5434]" "$C_BLUE" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
  if [ "$INNER_W" -ge 70 ]; then
    ui_line "$C_DIM" "  ● Gateway balancea HTTP; Postgres separa escrituras y lecturas."
  else
    ui_line "$C_DIM" "  ● Gateway balancea HTTP; Postgres separa write/read."
  fi
  wait_slide_footer "Detalle del clúster"
}

slide_02() {
  local use_cache="${1:-0}"
  slide_chrome 2 1 "Clúster Docker Compose · Estado de Servicios"
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ "$CACHE_PS_READY" -eq 0 ]; then
    if docker compose ps -a --format '{{.Name}}|{{.Service}}|{{.Status}}|{{.Ports}}' > "$TMP/ps_raw.txt" 2>/dev/null; then
      CACHE_PS_READY=1
    else
      : > "$TMP/ps_raw.txt"
      CACHE_PS_READY=0
    fi
  fi
  box_top "TELEMETRIA DE CONTENEDORES (docker compose ps)" "$C_CYAN"
  if [ "$CACHE_PS_READY" -eq 1 ] && [ -s "$TMP/ps_raw.txt" ]; then
    local show_ports=0
    [ "$INNER_W" -ge 72 ] && show_ports=1
    if [ "$show_ports" -eq 1 ]; then
      box_line "$(printf '%-18s %-16s %-23s %s' "CONTENEDOR" "SERVICIO" "ESTADO" "PUERTOS")" "$C_CYAN" "$C_CYAN"
    else
      box_line "$(printf '%-18s %-16s %s' "CONTENEDOR" "SERVICIO" "ESTADO")" "$C_CYAN" "$C_CYAN"
    fi
    while IFS='|' read -r cname svc status ports; do
      [ -z "$cname" ] && continue
      status="${status//About an hour/~1h}"
      status="${status//(health: starting)/(starting)}"
      status="${status//Less than a second/<1s}"
      ports="$(echo "$ports" | sed -E 's/0\.0\.0\.0://g; s/\[::\]:[0-9]+->[0-9]+\/tcp,? *//g; s/\/tcp//g')"
      local col="$C_YELLOW"; echo "$status" | grep -q 'healthy' && col="$C_GREEN"
      if [ "$show_ports" -eq 1 ]; then
        box_line "$(printf '%-18s %-16s %-23s %s' "$cname" "$svc" "$status" "$ports")" "$col" "$C_CYAN"
      else
        box_line "$(printf '%-18s %-16s %s' "$cname" "$svc" "$status")" "$col" "$C_CYAN"
      fi
    done < <(tr -d '\r' < "$TMP/ps_raw.txt")
  else
    box_line "No se pudo consultar docker compose (verifica Docker)." "$C_RED" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
  wait_slide_footer "2. Descubrimiento en Eureka"
}

slide_03() {
  local use_cache="${1:-0}"
  slide_chrome 3 2 "Descubrimiento Dinámico con Netflix Eureka"
  ui_blank
  box_top "ARQUITECTURA DE DESCUBRIMIENTO" "$C_CYAN"
  box_line "● Auto-registro al iniciar y latido (heartbeat) cada 5s." "$C_WHITE" "$C_CYAN"
  box_line "● Gateway resuelve via lb://ms-cuentas, sin IPs fijas." "$C_WHITE" "$C_CYAN"
  box_bottom "$C_CYAN"
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_EUREKA_CODE" ]; then
    CACHE_EUREKA_CODE="$(api_req GET "$EUREKA/eureka/apps" "" 5)"
    cp "$BODY_FILE" "$TMP/eureka_cache.json" 2>/dev/null || true
  fi
  box_top "REGISTRO EUREKA EN VIVO (:8761/eureka/apps)" "$C_GREEN"
  if [ "$CACHE_EUREKA_CODE" = "200" ]; then
    case "$JSON_TOOL" in
      jq)
        jq -r '.applications.application[] | .name as $n | (if (.instance|type)=="array" then .instance[] else .instance end) | "\($n)|\(.instanceId)|\(.status)"' "$TMP/eureka_cache.json" 2>/dev/null | {
          prev=""
          while IFS='|' read -r name iid st; do
            iid="$(echo "$iid" | sed -E 's/:([0-9a-f]{6})[0-9a-f]{26}(:|$)/:\1\2/')"
            local col="$C_CYAN" prefix="                    "
            [ "$name" = "MS-CUENTAS" ] && col="$C_GREEN"
            if [ "$name" != "$prev" ]; then
              prefix="$(printf '%-16s -> ' "$name")"
              prev="$name"
            fi
            box_line "${prefix}${iid} [${st}]" "$col" "$C_GREEN"
          done
        }
        ;;
      python3|python)
        "$JSON_TOOL" - "$TMP/eureka_cache.json" <<'PY' | tr -d '\r' | {
import json, re, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    for app in d.get("applications", {}).get("application", []):
        name = app.get("name", "")
        insts = app.get("instance", [])
        if isinstance(insts, dict): insts = [insts]
        for idx, it in enumerate(insts):
            iid = re.sub(r":([0-9a-f]{6})[0-9a-f]{26}(?=:|$)", r":\1", str(it.get("instanceId", "")))
            prefix = f"{name:<16} -> " if idx == 0 else " " * 20
            print(f"{name}|{prefix}{iid} [{it.get('status', '')}]")
except Exception:
    pass
PY
          while IFS='|' read -r name line; do
            local col="$C_CYAN"; [ "$name" = "MS-CUENTAS" ] && col="$C_GREEN"
            box_line "$line" "$col" "$C_GREEN"
          done
        }
        ;;
      *) box_line "Respuesta Eureka OK (HTTP 200)." "$C_GREEN" "$C_GREEN" ;;
    esac
  else
    box_line "No responde Eureka en $EUREKA (HTTP $CACHE_EUREKA_CODE)." "$C_RED" "$C_GREEN"
  fi
  box_bottom "$C_GREEN"
  wait_slide_footer "Balanceo HTTP Round Robin"
}

slide_04() {
  local use_cache="${1:-0}"
  slide_chrome 4 2 "Balanceo de Carga HTTP · Round Robin"
  ui_blank
  if [ "$INNER_W" -ge 64 ]; then
    ui_line "$C_CYAN" "  20 peticiones a GET $GATEWAY/api/cuentas/instancia"
  else
    ui_line "$C_CYAN" "  20x GET /api/cuentas/instancia"
  fi
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ "$CACHE_BAL_READY" -eq 0 ]; then
    : > "$TMP/balanceo.txt"
    local i code inst ok_cnt=0
    for i in $(seq 1 20); do
      code="$(api_req GET "$GATEWAY/api/cuentas/instancia" "" 5)"
      [ "$code" = "200" ] && ok_cnt=$((ok_cnt + 1))
      inst="$(get_header "X-Service-Instance")"; [ -z "$inst" ] && inst="sin-cabecera"
      printf '%s %s\n' "$code" "$inst" >> "$TMP/balanceo.txt"
    done
    CACHE_BAL_OK="$ok_cnt"
    CACHE_BAL_READY=1
  fi
  local bar_w=$((INNER_W - 42))
  [ "$bar_w" -gt 30 ] && bar_w=30
  [ "$bar_w" -lt 8 ] && bar_w=8
  box_top "DISTRIBUCION POR INSTANCIA" "$C_GREEN"
  sort "$TMP/balanceo.txt" | uniq -c | while read -r cnt code inst; do
    local pct=$(( (cnt * 100) / 20 ))
    local filled=$(( (cnt * bar_w + 10) / 20 )); [ "$filled" -gt "$bar_w" ] && filled="$bar_w"
    local bar_str col="$C_GREEN"
    bar_str="$(repeat_char '█' "$filled")$(repeat_char '░' "$((bar_w - filled))")"
    [ "$code" != "200" ] && col="$C_RED"
    echo "$inst" | grep -q 'ms-cuentas-2' && [ "$code" = "200" ] && col="$C_CYAN"
    box_line "$(printf '%-20s [%s]  %s  %2d/20 (%3d%%)' "$inst" "$code" "$bar_str" "$cnt" "$pct")" "$col" "$C_GREEN"
  done
  box_bottom "$C_GREEN"
  local err_cnt=$((20 - CACHE_BAL_OK))
  local pcol="$C_GREEN"; [ "$err_cnt" -ne 0 ] && pcol="$C_RED"
  ui_line "$pcol" "  [ RESULTADO: $CACHE_BAL_OK/20 OK · ERRORES: $err_cnt · REPARTO ROUND ROBIN ]"
  wait_slide_footer "3. Comunicación entre servicios"
}

slide_05() {
  local use_cache="${1:-0}" code
  slide_chrome 5 3 "Orquestación P2P entre Microservicios · Transferencia"
  ui_blank
  local flow="  POST :8080 ─► ms-transacciones ─► ms-cuentas ─ACID─► PRIMARY"
  if [ "$INNER_W" -ge 88 ]; then
    flow="  Cliente ─POST :8080─► [ms-transacciones :8083] ─Eureka─► [ms-cuentas] ─ACID─► PRIMARY"
  elif [ "$INNER_W" -lt 66 ]; then
    flow="  POST :8080 ► ms-tx ► ms-cuentas ► PRIMARY"
  fi
  ui_line "$C_CYAN" "$flow"
  ui_blank

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

  local nbd_disp="$nbd" nbd_lbl="Nodo Base de Datos : "
  if [ "$INNER_W" -lt 66 ]; then
    nbd_disp="${nbd//recovery=/rec=}"
    nbd_lbl="Nodo BD            : "
  fi

  box_top "COMPROBANTE DE TRANSFERENCIA  [ HTTP $code ]" "$bcol"
  box_line "Estado / Mensaje   : $msg" "$bcol" "$bcol"
  box_line "Comprobante        : $cod  (Monto: \$25.00)" "$C_WHITE" "$bcol"
  box_line "Saldo Origen Post. : \$$sal  ($ORIGEN -> $DESTINO)" "$C_WHITE" "$bcol"
  box_line "Instancia Cuentas  : $ic" "$C_CYAN" "$bcol"
  box_line "${nbd_lbl}${nbd_disp}" "$C_YELLOW" "$bcol"
  box_line "Politica Enrutado  : $pol" "$C_WHITE" "$bcol"
  box_bottom "$bcol"
  local acid="  ● Debito y credito en una sola transaccion ACID con bloqueo ordenado."
  [ "$INNER_W" -lt 68 ] && acid="  ● Debito/credito en 1 transaccion ACID con bloqueo ordenado."
  ui_line "$C_DIM" "$acid"
  wait_slide_footer "Validación saldo insuficiente"
}

slide_06() {
  local use_cache="${1:-0}" code
  slide_chrome 6 3 "Validación de Reglas de Negocio · Error Controlado"
  ui_blank
  local pnod="$(fmt_node_width "$LAST_TX_NODO")"
  if [ "$INNER_W" -ge 74 ]; then
    ui_line "$C_CYAN" "  Escritura previa ($LAST_TX_CODIGO) -> $pnod"
  else
    ui_line "$C_CYAN" "  Escritura ($LAST_TX_CODIGO) -> $pnod"
  fi
  ui_blank

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
  local mlbl="Mensaje devuelto   : "
  [ "$INNER_W" -lt 72 ] && mlbl="Mensaje  : "

  box_top "RECHAZO CONTROLADO  [ HTTP $code ]" "$bcol"
  box_line "${mlbl}${msg}" "$bcol" "$bcol"
  box_line "Monto solicitado   : \$9999.00  (supera saldo disponible)" "$C_WHITE" "$bcol"
  box_line "Integridad ACID    : Transaccion revertida; saldos intactos" "$C_GREEN" "$bcol"
  box_line "Auditoria nodoBD   : $(fmt_node_width "$nbd")" "$C_CYAN" "$bcol"
  box_bottom "$bcol"
  wait_slide_footer "4. Persistencia replicada"
}

fetch_lecturas_data() {
  local tag="$1" t0 t1
  t0="$(now_ms)"
  : > "$TMP/lect_${tag}.txt"
  : > "$TMP/lect_errs_${tag}.txt"
  local i u code node fb ok_cnt=0 fb_cnt=0 err_cnt=0
  for i in $(seq 1 10); do
    for u in "cuentas/$ORIGEN/contactos" "transacciones/historial/$ORIGEN"; do
      code="$(api_req GET "$GATEWAY/api/$u" "" 5)"
      if [ "$code" = "200" ]; then
        ok_cnt=$((ok_cnt + 1))
      else
        err_cnt=$((err_cnt + 1))
        printf 'HTTP %s\n' "$code" >> "$TMP/lect_errs_${tag}.txt"
      fi
      node="$(get_header "X-Db-Node")"; [ -z "$node" ] && node="desconocido"
      fb="$(get_header "X-Db-Fallback")"; [ -z "$fb" ] && fb="false"
      [ "$fb" = "true" ] && fb_cnt=$((fb_cnt + 1))
      printf '%s|%s|%s\n' "$code" "$node" "$fb" >> "$TMP/lect_${tag}.txt"
    done
  done
  t1="$(now_ms)"
  local err_detail="0"
  [ "$err_cnt" -gt 0 ] && err_detail="$(sort "$TMP/lect_errs_${tag}.txt" | uniq -c | awk '{printf "%s %s x%s, ", $2, $3, $1}' | sed 's/, $//')"
  printf '%s|%s|%s|%s|%s\n' "$ok_cnt" "$err_cnt" "$err_detail" "$fb_cnt" "$(fmt_ms_sec $((t1 - t0)))" > "$TMP/lect_meta_${tag}.txt"
}

fmt_node_width() {
  local n="$1"
  if [ "$INNER_W" -ge 72 ]; then
    printf '%s' "$n"
  else
    printf '%s' "$n" | sed -E 's/\([^)]*recovery=([^)]+)\)/(rec=\1)/g; s/, */ /g'
  fi
}

render_lecturas_from_cache() {
  local tag="$1" bcol="${2:-$C_GREEN}"
  local max_node=20 dn
  while IFS='|' read -r _c _n _f; do
    dn="$(fmt_node_width "$_n")"
    [ "${#dn}" -gt "$max_node" ] && max_node="${#dn}"
  done < "$TMP/lect_${tag}.txt"
  local bar_w=$((INNER_W - 25 - max_node))
  [ "$bar_w" -gt 18 ] && bar_w=18
  [ "$bar_w" -lt 4 ] && bar_w=4
  box_top "20 LECTURAS ORDINARIAS (contactos + historial)" "$bcol"
  sort "$TMP/lect_${tag}.txt" | uniq -c | while read -r line; do
    local cnt rest code node dnode fb filled bar_str col
    cnt="$(echo "$line" | awk '{print $1}')"
    rest="$(echo "$line" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')"
    code="$(echo "$rest" | cut -d'|' -f1)"
    node="$(echo "$rest" | cut -d'|' -f2)"
    fb="$(echo "$rest" | cut -d'|' -f3)"
    dnode="$(fmt_node_width "$node")"
    filled=$(( (cnt * bar_w + 10) / 20 )); [ "$filled" -gt "$bar_w" ] && filled="$bar_w"
    bar_str="$(repeat_char '█' "$filled")$(repeat_char '░' "$((bar_w - filled))")"
    col="$C_GREEN"; [ "$fb" = "true" ] && col="$C_YELLOW"; [ "$code" != "200" ] && col="$C_RED"
    box_line "$(printf '%2d/20 [%s] %s  %s  fb=%s' "$cnt" "$code" "$bar_str" "$dnode" "$fb")" "$col" "$bcol"
  done
  box_bottom "$bcol"
  IFS='|' read -r LECT_OK LECT_ERR LECT_ERR_DETAIL LECT_FB LECT_SEC < "$TMP/lect_meta_${tag}.txt"
}

slide_07() {
  local use_cache="${1:-0}"
  slide_chrome 7 4 "Enrutamiento de Base de Datos · Primario vs Réplicas"
  ui_blank
  local wnod="$(fmt_node_width "$LAST_TX_NODO")"
  if [ "$INNER_W" -ge 80 ]; then
    ui_line "$C_CYAN" "  Escrituras -> $wnod  |  Lecturas -> REPLICA_1 / REPLICA_2"
  else
    ui_line "$C_CYAN" "  Write -> $wnod | Read -> REP1/REP2"
  fi
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ "$CACHE_LECT07_READY" -eq 0 ]; then
    fetch_lecturas_data "07"
    CACHE_LECT07_READY=1
  fi
  render_lecturas_from_cache "07" "$C_GREEN"
  local col="$C_GREEN"; [ "$LECT_ERR" -gt 0 ] && col="$C_RED"
  ui_line "$col" "  [ $LECT_OK/20 OK · ERRORES: $LECT_ERR_DETAIL · REPLICAS (recovery=true) · ${LECT_SEC}s ]"
  wait_slide_footer "Lectura crítica RYOW"
}

slide_08() {
  local use_cache="${1:-0}"
  slide_chrome 8 4 "Consistencia Inmediata · Read-Your-Own-Writes (RYOW)"
  ui_blank
  box_top "ARQUITECTURA DE CONSISTENCIA" "$C_CYAN"
  if [ "$INNER_W" -ge 68 ]; then
    box_line "● Las replicas WAL pueden presentar retardo minimo tras escribir." "$C_WHITE" "$C_CYAN"
    box_line "● /saldo-critico fuerza lectura al PRIMARIO (RYOW garantizado)." "$C_WHITE" "$C_CYAN"
  else
    box_line "● Replicas WAL pueden tener retardo minimo tras escribir." "$C_WHITE" "$C_CYAN"
    box_line "● /saldo-critico fuerza lectura en PRIMARIO (RYOW)." "$C_WHITE" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_CRIT_CODE" ]; then
    CACHE_CRIT_CODE="$(api_req GET "$GATEWAY/api/cuentas/$ORIGEN/saldo-critico" "" 5)"
    cp "$BODY_FILE" "$TMP/crit_cache.json" 2>/dev/null || true
  fi
  local box_t8="LECTURA CRITICA  [ GET /api/cuentas/$ORIGEN/saldo-critico ]"
  [ "$INNER_W" -lt 68 ] && box_t8="LECTURA CRITICA (GET /saldo-critico)"
  box_top "$box_t8" "$C_GREEN"
  if [ "$CACHE_CRIT_CODE" = "200" ]; then
    local fields sal nbd pol
    fields="$(extract_critico_fields "$TMP/crit_cache.json" | tr -d '\r')"
    IFS='|' read -r sal nbd pol <<< "$fields"
    box_line "Saldo inmediato    : \$$sal" "$C_GREEN" "$C_GREEN"
    box_line "Nodo Base de Datos : $(fmt_node_width "$nbd")" "$C_CYAN" "$C_GREEN"
    box_line "Politica Enrutado  : $pol" "$C_YELLOW" "$C_GREEN"
  else
    box_line "HTTP $CACHE_CRIT_CODE al consultar saldo-critico" "$C_RED" "$C_GREEN"
  fi
  box_bottom "$C_GREEN"
  wait_slide_footer "5. Simulación de fallos"
}

slide_09() {
  local use_cache="${1:-0}"
  slide_chrome 9 5 "Alta Disponibilidad HTTP · Caída de ms-cuentas-2"

  if [ "$use_cache" -eq 1 ] && [ "${#LAST_BURST_LINES[@]}" -gt 0 ]; then
    ui_blank
    local rcol="$C_GREEN"
    echo "${LAST_BURST_LINES[0]}" | grep -q 'Errores: 0$' || rcol="$C_YELLOW"
    box_top "RESUMEN DE FALLO Y CONVERGENCIA" "$rcol"
    local ln
    for ln in "${LAST_BURST_LINES[@]}"; do
      box_line "$ln" "$C_WHITE" "$rcol"
    done
    box_bottom "$rcol"
    wait_slide_footer "5b. Caída de réplica PostgreSQL"
    return
  fi

  local phase=1 total_req=0 err_req=0 c1=0 c2=0
  local event_msg="Trafico continuo activo contra Gateway :8080"
  local ring=() abort_act="" hdr="$TMP/traf_hdr.txt" code inst ts col
  local stop_trig_ms=0 start_trig_ms=0 detect_ms=-1 rejoin_ms=-1 consec_c1=0 streak_ms=0 now_m
  : > "$TMP/s9_errs.txt"

  render_s9_body() {
    [ -t 1 ] && printf '\033[%d;1H' "$((DOCK_ROW + 4))"
    local status_txt err_codes="" tot_line
    if [ "$INNER_W" -ge 74 ]; then
      case "$phase" in
        1) status_txt="Trafico activo (ms-cuentas-1 + ms-cuentas-2)  |  [ESPACIO] Detener :8082" ;;
        2) status_txt="ms-cuentas-2 DETENIDA · Midiendo deteccion  |  [ESPACIO] Reiniciar :8082" ;;
        3) status_txt="Recuperando instancia (~25s JVM)              |  [ESPACIO] Ver resumen" ;;
      esac
    else
      case "$phase" in
        1) status_txt="Activo (:8081 + :8082) | [ESPACIO] Detener :8082" ;;
        2) status_txt=":8082 DETENIDA (deteccion) | [ESPACIO] Reiniciar" ;;
        3) status_txt="Recuperando JVM (~25s) | [ESPACIO] Ver resumen" ;;
      esac
    fi
    if [ "$err_req" -gt 0 ]; then
      err_codes=" [$(sort "$TMP/s9_errs.txt" | uniq -c | awk '{printf "%s %s x%s, ", $2, $3, $1}' | sed 's/, $//')]"
    fi
    tot_line="$(printf 'Total: %-4d  cta-1: %-4d  cta-2: %-4d  Errores: %d%s' "$total_req" "$c1" "$c2" "$err_req" "$err_codes")"
    [ "${#tot_line}" -gt "$INNER_W" ] && tot_line="Tot:${total_req} c1:${c1} c2:${c2} Err:${err_req}${err_codes}"
    local ccol="$C_GREEN"; [ "$err_req" -gt 0 ] && ccol="$C_RED"
    box_top "TELEMETRIA EN VIVO (VENTANA FIJA)" "$C_YELLOW"
    box_line "$status_txt" "$C_YELLOW" "$C_YELLOW"
    box_line "$tot_line" "$ccol" "$C_YELLOW"
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
    printf '%s  %s%s%s%s\n' "$MARGIN" "$C_CYAN" "$(pad_fixed "$event_msg" "$INNER_W")" "$C_RESET" "$CLR_EOL"
    end_frame
  }

  while true; do
    if [ "$RESIZED" -eq 1 ]; then
      slide_chrome 9 5 "Alta Disponibilidad HTTP · Caída de ms-cuentas-2"
    fi
    start_dock_probe_bg

    code="$(curl -s --max-time 3 -o /dev/null -D "$hdr" -w '%{http_code}' "$GATEWAY/api/cuentas/$ORIGEN" 2>/dev/null)" || code="000"
    [ -z "$code" ] && code="000"
    inst="$(grep -i '^X-Service-Instance:' "$hdr" 2>/dev/null | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/\r$//')"
    [ -z "$inst" ] && inst="sin-instancia"
    now_m="$(now_ms)"
    ts="$(date +%T)"
    total_req=$((total_req + 1))
    if [ "$code" != "200" ]; then
      err_req=$((err_req + 1)); col="$C_RED"
      printf 'HTTP %s\n' "$code" >> "$TMP/s9_errs.txt"
      consec_c1=0; streak_ms=0
    elif echo "$inst" | grep -q 'ms-cuentas-2'; then
      c2=$((c2 + 1)); col="$C_CYAN"
      consec_c1=0; streak_ms=0
      if [ "$phase" -eq 3 ] && [ "$rejoin_ms" -lt 0 ] && [ "$start_trig_ms" -gt 0 ]; then
        rejoin_ms=$((now_m - start_trig_ms))
        event_msg="[EVENTO] ms-cuentas-2 reincorporada en $(fmt_ms_sec "$rejoin_ms")s!"
      fi
    else
      c1=$((c1 + 1)); col="$C_GREEN"
      if [ "$phase" -ge 2 ] && [ "$detect_ms" -lt 0 ] && [ "$stop_trig_ms" -gt 0 ]; then
        [ "$consec_c1" -eq 0 ] && streak_ms="$now_m"
        consec_c1=$((consec_c1 + 1))
        if [ "$consec_c1" -ge 3 ]; then
          detect_ms=$((streak_ms - stop_trig_ms))
          event_msg="[EVENTO] Convergencia exclusiva a ms-cuentas-1 ($(fmt_ms_sec "$detect_ms")s)"
        fi
      fi
    fi
    ring+=("$col|[$ts]  HTTP $code  ->  $inst")
    if [ "${#ring[@]}" -gt 6 ]; then
      ring=("${ring[@]:1}")
    fi

    render_s9_body

    local k=""
    if [ "${BASH_VERSINFO[0]:-3}" -ge 4 ]; then
      if IFS= read -rsn1 -t 0.25 k; then parse_key_char "$k"; else ACT=""; fi
    else
      if IFS= read -rsn1 -t 1 k; then parse_key_char "$k"; else ACT=""; fi
    fi

    if [ -n "$ACT" ]; then
      case "$ACT" in
        QUIT|HOME|PREV|B[1-6]) abort_act="$ACT"; break ;;
        EUREKA) open_eureka ;;
        *)
          if [ "$phase" -eq 1 ]; then
            phase=2
            stop_trig_ms="$(now_ms)"; consec_c1=0; streak_ms=0
            event_msg="[ACCION] Deteniendo ms-cuentas-2 (docker compose stop)"
            ( docker compose stop ms-cuentas-2 >/dev/null 2>&1 ) &
            BG_DOCKER_PID=$!
          elif [ "$phase" -eq 2 ]; then
            phase=3
            start_trig_ms="$(now_ms)"
            event_msg="[ACCION] Reiniciando ms-cuentas-2 (docker compose start)"
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

  local err_summary det_str rej_str rcol="$C_GREEN"
  if [ "$err_req" -gt 0 ]; then
    err_summary="$(sort "$TMP/s9_errs.txt" | uniq -c | awk '{printf "%s %s x%s, ", $2, $3, $1}' | sed 's/, $//')"
    rcol="$C_YELLOW"
  else
    err_summary="ninguno (reintento GET en Gateway)"
  fi
  if [ "$detect_ms" -ge 0 ]; then det_str="$(fmt_ms_sec "$detect_ms")s"; else det_str="inmediata"; fi
  if [ "$rejoin_ms" -ge 0 ]; then rej_str="$(fmt_ms_sec "$rejoin_ms")s"; else rej_str="~25s JVM"; fi

  LAST_BURST_LINES=(
    "Total: $total_req  |  Exitosas (200): $((total_req - err_req))  |  Errores: $err_req"
    "Errores transitorios : $err_summary"
    "Distribucion : ms-cuentas-1=$c1  |  ms-cuentas-2=$c2"
    "Deteccion    : $det_str  |  Retorno: $rej_str"
    "Limitacion   : Gateway reintenta GET (no POST /transferir)"
  )

  slide_chrome 9 5 "Alta Disponibilidad HTTP · Errores y Tiempos Observados"
  ui_blank
  box_top "RESUMEN DE FALLO Y CONVERGENCIA" "$rcol"
  box_line "${LAST_BURST_LINES[0]}" "$rcol" "$rcol"
  box_line "${LAST_BURST_LINES[1]}" "$( [ "$err_req" -eq 0 ] && echo "$C_GREEN" || echo "$C_RED" )" "$rcol"
  box_line "${LAST_BURST_LINES[2]}" "$C_WHITE" "$rcol"
  box_line "${LAST_BURST_LINES[3]}" "$C_CYAN" "$rcol"
  box_line "${LAST_BURST_LINES[4]}" "$C_DIM" "$rcol"
  box_bottom "$rcol"
  wait_slide_footer "5b. Caída de réplica PostgreSQL"
}

slide_10() {
  slide_chrome 10 5 "Alta Disponibilidad de Datos · Caída de Réplica PG"
  ui_blank
  box_top "ESCENARIO: FALLO DE NODO DE LECTURA EN CALIENTE" "$C_YELLOW"
  box_line "" "$C_WHITE" "$C_YELLOW"
  box_line "  ● Se detiene replica1 mientras el servicio recibe consultas." "$C_WHITE" "$C_YELLOW"
  if [ "$INNER_W" -ge 68 ]; then
    box_line "  ● @UsarNodo captura la excepcion y reintenta sobre la replica" "$C_WHITE" "$C_YELLOW"
    box_line "    sana (X-Db-Fallback: true) hasta que la sonda actua." "$C_WHITE" "$C_YELLOW"
    box_line "" "$C_WHITE" "$C_YELLOW"
    box_line "  PRUEBA: docker compose stop replica1  +  20 lecturas" "$C_CYAN" "$C_YELLOW"
  else
    box_line "  ● @UsarNodo reintenta sobre replica sana (X-Db-Fallback)" "$C_WHITE" "$C_YELLOW"
    box_line "    hasta que la sonda cada 3s marca replica1 caida." "$C_WHITE" "$C_YELLOW"
    box_line "" "$C_WHITE" "$C_YELLOW"
    box_line "  PRUEBA: stop replica1 + 20 lecturas consecutivas" "$C_CYAN" "$C_YELLOW"
  fi
  box_line "" "$C_WHITE" "$C_YELLOW"
  box_bottom "$C_YELLOW"
  wait_slide_footer "Caída replica1 + lecturas"
}

slide_11() {
  local use_cache="${1:-0}"
  if [ "$use_cache" -eq 0 ] || [ "$CACHE_LECT11_READY" -eq 0 ]; then
    docker compose stop replica1 >/dev/null 2>&1 || true
    STOP_REP_MS="$(now_ms)"
    fetch_dock_sync
    fetch_lecturas_data "11"
    CACHE_LECT11_READY=1
  fi
  slide_chrome 11 5 "Failover Transparente · Lecturas sobre REPLICA_2"
  ui_blank
  ui_line "$C_CYAN" "  \$ docker compose stop replica1  [OK]"
  ui_blank
  render_lecturas_from_cache "11" "$C_YELLOW"
  local col="$C_GREEN"; [ "$LECT_ERR" -gt 0 ] && col="$C_YELLOW"
  ui_line "$col" "  [ $LECT_OK/20 OK · ERRORES: $LECT_ERR_DETAIL · FALLBACK=$LECT_FB · TIEMPO=${LECT_SEC}s ]"
  wait_slide_footer "Estado de salud de réplicas"
}

render_db_estado_box() {
  local title="$1" code="$2" json_file="$3"
  box_top "$title" "$C_CYAN"
  if [ "$code" = "200" ]; then
    case "$JSON_TOOL" in
      jq)
        local srv ct
        srv="$(jq -r '.servicio // empty' "$json_file" 2>/dev/null)"
        ct="$(jq -r 'if .consultasTotales then " · Consultas: PRI=\(.consultasTotales.PRIMARY // 0) R1=\(.consultasTotales.REPLICA_1 // 0) R2=\(.consultasTotales.REPLICA_2 // 0)" else "" end' "$json_file" 2>/dev/null)"
        [ -n "$srv$ct" ] && box_line "Instancia: $srv$ct" "$C_DIM" "$C_CYAN"
        jq -r '.replicas[] | "\(.nodo)|\(.available)|\(.consecutiveSuccesses)|\(.lastReplayLsn // "-")"' "$json_file" 2>/dev/null | \
          while IFS='|' read -r nodo avail succ lsn; do
            local badge col="$C_RED"
            if [ "$INNER_W" -ge 66 ]; then
              badge="[✗ CAIDA  · available=false]"
              [ "$avail" = "true" ] && badge="[● ACTIVA · available=true ]" && col="$C_GREEN"
              box_line "$(printf '%-10s %s  exitos=%-3s LSN=%s' "$nodo" "$badge" "$succ" "$lsn")" "$col" "$C_CYAN"
            else
              badge="[✗ CAIDA ]"
              [ "$avail" = "true" ] && badge="[● ACTIVA]" && col="$C_GREEN"
              box_line "$(printf '%-10s %s ok=%-4s LSN=%s' "$nodo" "$badge" "$succ" "$lsn")" "$col" "$C_CYAN"
            fi
          done
        ;;
      python3|python)
        "$JSON_TOOL" - "$json_file" <<'PY' | tr -d '\r' | while IFS='|' read -r kind f1 f2 f3 f4; do
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    srv = d.get("servicio") or ""
    ct = d.get("consultasTotales")
    ct_txt = f" · Consultas: PRI={ct.get('PRIMARY',0)} R1={ct.get('REPLICA_1',0)} R2={ct.get('REPLICA_2',0)}" if ct else ""
    if srv or ct_txt:
        print(f"SRV|{srv}{ct_txt}|||")
    for rep in d.get("replicas", []):
        print(f"REP|{rep.get('nodo')}|{str(rep.get('available')).lower()}|{rep.get('consecutiveSuccesses')}|{rep.get('lastReplayLsn')}")
except Exception:
    pass
PY
          if [ "$kind" = "SRV" ]; then
            box_line "Instancia: $f1" "$C_DIM" "$C_CYAN"
          else
            local badge col="$C_RED"
            if [ "$INNER_W" -ge 66 ]; then
              badge="[✗ CAIDA  · available=false]"
              [ "$f2" = "true" ] && badge="[● ACTIVA · available=true ]" && col="$C_GREEN"
              box_line "$(printf '%-10s %s  exitos=%-3s LSN=%s' "$f1" "$badge" "$f3" "$f4")" "$col" "$C_CYAN"
            else
              badge="[✗ CAIDA ]"
              [ "$f2" = "true" ] && badge="[● ACTIVA]" && col="$C_GREEN"
              box_line "$(printf '%-10s %s ok=%-4s LSN=%s' "$f1" "$badge" "$f3" "$f4")" "$col" "$C_CYAN"
            fi
          fi
        done
        ;;
      *) box_line "$(cat "$json_file")" "$C_WHITE" "$C_CYAN" ;;
    esac
  else
    box_line "HTTP $code al consultar db/estado" "$C_RED" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
}

slide_12() {
  local use_cache="${1:-0}"
  slide_chrome 12 5 "Detección Automática de Réplica Caída (Sondeo 3s)"
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_EST12_CODE" ]; then
    CACHE_EST12_CODE="$(api_req GET "$GATEWAY/api/cuentas/db/estado" "" 5)"
    cp "$BODY_FILE" "$TMP/est12_cache.json" 2>/dev/null || true
  fi
  render_db_estado_box "SALUD DE REPLICAS (/api/cuentas/db/estado)" "$CACHE_EST12_CODE" "$TMP/est12_cache.json"
  ui_blank
  local elap="sondeo cada 3.0s"
  [ "$STOP_REP_MS" -gt 0 ] && elap="$(fmt_ms_sec $(( $(now_ms) - STOP_REP_MS )))s tras stop"
  box_top "DETECCION Y LIMITACIONES" "$C_DIM"
  box_line "● Deteccion: $elap (ReplicaHealthTracker, c/3s)." "$C_WHITE" "$C_DIM"
  box_line "● Limitacion: failover solo lectura (no promueve PRIMARY)." "$C_YELLOW" "$C_DIM"
  box_bottom "$C_DIM"
  wait_slide_footer "Reiniciar replica1 (recuperación WAL)"
}

slide_13() {
  local use_cache="${1:-0}"
  if [ "$use_cache" -eq 0 ]; then
    docker compose start replica1 >/dev/null 2>&1 || true
    START_REP_MS="$(now_ms)"
    fetch_dock_sync
  fi
  slide_chrome 13 5 "Recuperación de Réplica · Streaming WAL y Umbral 2/2"
  ui_blank
  ui_line "$C_CYAN" "  \$ docker compose start replica1  [OK]"
  ui_blank
  box_top "SINCRONIZACION AUTOMATICA EN CURSO" "$C_GREEN"
  box_line "[✓] Contenedor replica1 reiniciado." "$C_GREEN" "$C_GREEN"
  box_line "[~] Sincronizando registros WAL desde el nodo primario." "$C_YELLOW" "$C_GREEN"
  box_line "[~] Umbral de retorno: 2 chequeos sanos seguidos (2 x 3s)." "$C_CYAN" "$C_GREEN"
  box_bottom "$C_GREEN"
  wait_slide_footer "Verificar retorno al Round-Robin"
}

slide_14() {
  local use_cache="${1:-0}"
  slide_chrome 14 5 "Reincorporación Automática de replica1 al Round-Robin"
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_EST14_CODE" ]; then
    CACHE_EST14_CODE="$(api_req GET "$GATEWAY/api/cuentas/db/estado" "" 5)"
    cp "$BODY_FILE" "$TMP/est14_cache.json" 2>/dev/null || true
  fi
  render_db_estado_box "SALUD DE REPLICAS TRAS RECUPERACION (/api/cuentas/db/estado)" "$CACHE_EST14_CODE" "$TMP/est14_cache.json"
  ui_blank
  local elap="~6-8s habituales"
  [ "$START_REP_MS" -gt 0 ] && elap="$(fmt_ms_sec $(( $(now_ms) - START_REP_MS )))s tras start"
  box_top "RETORNO AUTOMATICO Y LIMITACION" "$C_DIM"
  box_line "● Retorno: $elap (2x pg_is_in_recovery=true)." "$C_WHITE" "$C_DIM"
  box_line "● Limitacion: depende de wal_keep_size (usar slots en prod)." "$C_YELLOW" "$C_DIM"
  box_bottom "$C_DIM"
  wait_slide_footer "6. Conclusiones técnicas"
}

slide_15() {
  slide_chrome 15 6 "Conclusiones Técnicas · Decisiones, Limitaciones y Mejoras"
  ui_blank
  if [ "$INNER_W" -ge 72 ]; then
    write_three_col_cards "DECISIONES" "LIMITACIONES" "MEJORAS FUTURAS" "$C_GREEN" "$C_YELLOW" "$C_CYAN" \
      "· BD por @UsarNodo|· Sin failover primario|· Failover (Patroni)" \
      "  write->PRI  read->REP|· Eureka unico (SPOF)|· Claves idempotencia" \
      "· Round Robin + salud|· /movimiento-interno|· Retry conexion en" \
      "  chequeo 2 de 2|  expuesto en Gateway|  ms-transacciones" \
      "· Eureka sin cache +|· Limite diario no se|· Health Eureka real" \
      "  retry GET (0 err P03)|  reinicia solo|· Bloquear ruta interna" \
      "· Flyway advisory lock|· Sin idempotencia P2P|  y Sagas / Outbox"
  else
    write_three_col_cards "DECISIONES" "LIMITACIONES" "MEJORAS" "$C_GREEN" "$C_YELLOW" "$C_CYAN" \
      "· @UsarNodo JDBC|· Sin failover PRI|· Failover Patroni" \
      "  W:PRI R:REPLICA|· Eureka unico|· Idempotencia P2P" \
      "· Round-Robin 2/2|· /mov-interno en|· Retry conexion" \
      "  salud verificada|  ruta del Gateway|  ms-transacciones" \
      "· Eureka sin cache|· Limite diario|· Health Eureka" \
      "  + retry GET GW|  sin auto-reset|· Cerrar /mov-int" \
      "· Flyway adv. lock|· Sin idempotencia|  + Sagas / Outbox"
  fi
  local quote='"Mas de uno de todo, y saber esquivar al que falla. Sistema distribuido."'
  [ "$INNER_W" -lt 74 ] && quote='"Replicar cada capa y esquivar al nodo que falla."'
  box_top "SINTESIS FINAL" "$C_CYAN"
  box_line "$(pad_center "$quote" "$INNER_W")" "$C_CYAN" "$C_CYAN"
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
      RESIZE) use_cache=1; continue ;;
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
        FIRST_FRAME=1
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
  local last_sal_poll=0 sinfo=""
  while true; do
    begin_frame
    DOCK_ROW=$((PAD_T + 5))
    local ptitle="BILLETERA DIGITAL DISTRIBUIDA · DEMO EN VIVO"
    local psub="Replicacion PostgreSQL WAL, descubrimiento Eureka y failover"
    [ "$INNER_W" -lt 66 ] && ptitle="BILLETERA DIGITAL · DEMO EN VIVO"
    [ "$INNER_W" -lt 70 ] && psub="Replicacion Postgres WAL, Eureka y tolerancia a fallos"

    printf '%s%s╔%s╗%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '═' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    printf '%s%s║ %s%s%s ║%s%s\n' "$MARGIN" "$C_CYAN" "${C_BOLD}${C_CYAN}" "$(pad_center "$ptitle" "$INNER_W")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    printf '%s%s║ %s%s%s ║%s%s\n' "$MARGIN" "$C_CYAN" "$C_DIM" "$(pad_center "$psub" "$INNER_W")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    printf '%s%s╚%s╝%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '═' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"

    render_cluster_dock
    if [ -t 1 ] && [ "$LAST_SCREEN_ID" != "PORTADA" ]; then
      printf '\033[J'
    fi
    LAST_SCREEN_ID="PORTADA"

    local leg="  ● En linea   ~ Iniciando   ✗ Caido     (actualizado en segundo plano)"
    [ "$INNER_W" -lt 72 ] && leg="  ● En linea   ~ Iniciando   ✗ Caido"
    ui_line "$C_DIM" "$leg"
    ui_blank

    local ag_title="RECORRIDO (15 DIAPOSITIVAS) · ELIGE SECCION [1-6]"
    [ "$INNER_W" -lt 70 ] && ag_title="RECORRIDO (15 SLIDES) · PULSA [1-6]"
    box_top "$ag_title" "$C_CYAN"
    local col_l=$(( (INNER_W - 3) / 2 ))
    local col_r=$(( INNER_W - 3 - col_l ))
    local ag_rows
    if [ "$INNER_W" -ge 74 ]; then
      ag_rows=(
        "[1] Arquitectura y Docker  (01-02)|[4] Lecturas Replica y RYOW (07-08)"
        "[2] Eureka y Balanceo HTTP (03-04)|[5] Caidas: App y Postgres  (09-14)"
        "[3] Transferencia P2P ACID (05-06)|[6] Conclusiones Tecnicas      (15)"
      )
    else
      ag_rows=(
        "[1] Arquitectura    (01-02)|[4] Lecturas y RYOW (07-08)"
        "[2] Eureka/Balanceo (03-04)|[5] Fallos App/BD   (09-14)"
        "[3] P2P Transf ACID (05-06)|[6] Conclusiones       (15)"
      )
    fi
    local ar lhs rhs
    for ar in "${ag_rows[@]}"; do
      lhs="${ar%%|*}"
      rhs="${ar#*|}"
      printf '%s%s│ %s%s %s│ %s%s%s │%s%s\n' \
        "$MARGIN" "$C_CYAN" \
        "$C_WHITE" "$(pad_fixed "$lhs" "$col_l")" \
        "$C_DIM" \
        "$C_WHITE" "$(pad_fixed "$rhs" "$col_r")" \
        "$C_CYAN" "$C_RESET" "$CLR_EOL"
    done
    box_bottom "$C_CYAN"

    local now
    now=$(date +%s)
    if [ $((now - last_sal_poll)) -ge 4 ]; then
      sinfo="$(get_saldo_line | tr -d '\r' || true)"
      last_sal_poll="$now"
    fi

    ui_blank
    if [ -n "$sinfo" ]; then
      local s c l col="$C_GREEN" badge=" [LISTO]"
      s="$(echo "$sinfo" | cut -d'|' -f1)"; c="$(echo "$sinfo" | cut -d'|' -f2)"; l="$(echo "$sinfo" | cut -d'|' -f3)"
      if awk -v v="${c:-0}" 'BEGIN{exit !(v+0 > 0)}'; then
        col="$C_YELLOW"; badge=" [REINICIAR CON U->P]"
      fi
      ui_line "$col" "  Cuenta demo $ORIGEN : saldo=\$$s | hoy=\$$c/\$$l$badge"
    elif [ ! -f "$REPO_DIR/.env" ]; then
      ui_line "$C_YELLOW" "  [AVISO] Gateway sin respuesta y falta .env -> [U] -> [C] / [P]"
    else
      ui_line "$C_DIM" "  Gateway :8080 sin conexion -> Pulsa [U] para iniciar servicios"
    fi

    write_divider
    local sp="  ► [ESPACIO / ENTER] Iniciar Presentacion (Diapositiva 1/15)"
    local np="    Atajos: [1-6] Ir a seccion   [B] Eureka   [U] Utilidades   [Q] Salir"
    [ "$UI_W" -lt 68 ] && sp="  ► [ESPACIO/→] Iniciar Presentacion (1/15)"
    [ "$UI_W" -lt 74 ] && np="    [1-6] Seccion  [B] Eureka  [U] Utils  [Q] Salir"
    ui_line "${C_BOLD}${C_GREEN}" "$sp"
    ui_line "$C_DIM" "$np"
    end_frame

    read_slide_key_live 1
    case "$ACT" in
      RESIZE)       continue ;;
      QUIT)         return ;;
      EUREKA)       open_eureka ;;
      DOCK_REFRESH) fetch_dock_sync; update_dock_in_place ;;
      PREP)         show_clean_prep; last_sal_poll=0 ;;
      UTILS)
        show_utils_panel; FIRST_FRAME=1; last_sal_poll=0
        [ "$ACT" = "QUIT" ] && return
        if [[ "$ACT" =~ ^B[1-6]$ ]]; then run_deck "$(block_to_idx "$ACT")"; fi
        ;;
      B[1-6]) run_deck "$(block_to_idx "$ACT")"; last_sal_poll=0 ;;
      NEXT|REPEAT) run_deck 0; last_sal_poll=0 ;;
      *) ;;
    esac
    [ "$ACT" = "QUIT" ] && return
  done
}

show_portada
