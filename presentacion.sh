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
SLIDE_BOX_W=78
DUAL_PANE=0
LEFT_W=78
RIGHT_W=0
RIGHT_INNER=0
PAD_L=1
PAD_T=0
MARGIN=" "
DOCK_ROW=3
DUAL_BODY_ROW=4
FRAME_ROWS=0
BUFFERING_LEFT=0
LEFT_TITLE="WORKSPACE"
RESIZED=0

LAST_DOCK_SIG=""
LAST_LOG_DOCK_SIG=""
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
LEFT_BUF_FILE="$TMP/left_buf.txt"
LOG_FILE="$TMP/event_log.txt"
TRACE_DIR="$TMP/traces"
mkdir -p "$TRACE_DIR"
TRACE_SEQ=0
: > "$LOG_FILE"
: > "$LEFT_BUF_FILE"
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

clip_clean() {
  local txt="${1//$'\r'/}" w="$2"
  [ "$w" -le 0 ] && return
  if [ "${#txt}" -le "$w" ]; then
    printf '%s' "$txt"
  elif [ "$w" -eq 1 ]; then
    printf '…'
  else
    printf '%s…' "${txt:0:$((w - 1))}"
  fi
}

add_event_log() {
  local lvl="$1" cat="$2" msg="$3" ts
  msg="${msg//$'\r'/}"
  msg="${msg//|//}"
  ts="$(date +%H:%M:%S)"
  printf '%s|%s|%s|%s\n' "$ts" "$lvl" "$cat" "$msg" >> "$LOG_FILE"
  local lc
  lc="$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')"
  if [ "${lc:-0}" -gt 70 ]; then
    tail -n 60 "$LOG_FILE" > "$TMP/log_trim.tmp" && mv "$TMP/log_trim.tmp" "$LOG_FILE"
  fi
}
add_event_log "INFO" "SYS" "Presentacion iniciada"

shopt -s checkwinsize 2>/dev/null || true

update_ui_metrics() {
  local force_single="${1:-0}"
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

  local dual=0 new_ui_w new_rw=0 new_lw new_sbw new_inw new_ri=0
  if [ "$force_single" -eq 0 ] && [ "$w" -ge 112 ]; then
    dual=1
    new_ui_w=$((w - 2)); [ "$new_ui_w" -gt 136 ] && new_ui_w=136
    new_rw=37; [ "$new_ui_w" -ge 128 ] && new_rw=42
    new_lw=$((new_ui_w - new_rw - 1))
    new_sbw=$((new_lw - 4))
    new_inw=$((new_sbw - 4))
    new_ri=$((new_rw - 4))
  else
    new_ui_w=$((w - 2))
    [ "$new_ui_w" -gt 100 ] && new_ui_w=100
    [ "$new_ui_w" -lt 64 ] && new_ui_w=64
    new_lw="$new_ui_w"
    new_sbw="$new_ui_w"
    new_inw=$((new_sbw - 4))
  fi

  local new_pad_l=$(( (w - new_ui_w) / 2 ))
  [ "$new_pad_l" -lt 0 ] && new_pad_l=0
  local new_pad_t=0
  if [ -t 1 ] && [ "$h" -ge 28 ]; then
    new_pad_t=$(( (h - 24) / 3 ))
    [ "$new_pad_t" -gt 3 ] && new_pad_t=3
  fi
  if [ "$new_ui_w" -ne "$UI_W" ] || [ "$new_pad_l" -ne "$PAD_L" ] || [ "$new_pad_t" -ne "$PAD_T" ] || [ "$dual" -ne "$DUAL_PANE" ]; then
    FORCE_CLEAR=1
  fi
  WIN_W="$w"; WIN_H="$h"; DUAL_PANE="$dual"; UI_W="$new_ui_w"; LEFT_W="$new_lw"
  RIGHT_W="$new_rw"; RIGHT_INNER="$new_ri"; SLIDE_BOX_W="$new_sbw"; INNER_W="$new_inw"
  PAD_L="$new_pad_l"; PAD_T="$new_pad_t"
  MARGIN="$(repeat_char ' ' "$new_pad_l")"
  RESIZED=0
}

emit_slide_row() {
  local raw="$1"
  if [ "$BUFFERING_LEFT" -eq 1 ]; then
    printf '%s\n' "$raw" >> "$LEFT_BUF_FILE"
  else
    printf '%s%s%s%s\n' "$MARGIN" "$raw" "$C_RESET" "$CLR_EOL"
    FRAME_ROWS=$((FRAME_ROWS + 1))
  fi
}

ui_blank() {
  if [ "$BUFFERING_LEFT" -eq 1 ]; then
    printf '%*s\n' "$SLIDE_BOX_W" '' >> "$LEFT_BUF_FILE"
  else
    printf '%s\n' "$CLR_EOL"
    FRAME_ROWS=$((FRAME_ROWS + 1))
  fi
}

ui_line() {
  local col="${1:-}" txt="${2:-}"
  if [ "$BUFFERING_LEFT" -eq 1 ]; then
    emit_slide_row "${col}$(pad_fixed "$txt" "$SLIDE_BOX_W")${C_RESET}"
  else
    printf '%s%s%s%s%s\n' "$MARGIN" "$col" "$txt" "$C_RESET" "$CLR_EOL"
    FRAME_ROWS=$((FRAME_ROWS + 1))
  fi
}

begin_frame() {
  local hard="${1:-0}" modal="${2:-0}"
  BUFFERING_LEFT=0
  : > "$LEFT_BUF_FILE"
  update_ui_metrics "$modal"
  FRAME_ROWS=0
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
  local max_t=$((SLIDE_BOX_W - 6))
  [ "${#title}" -gt "$max_t" ] && title="${title:0:$max_t}"
  local fill=$(( (SLIDE_BOX_W - 3) - ${#title} ))
  [ "$fill" -lt 2 ] && fill=2
  emit_slide_row "${col}╭─${title}$(repeat_char '─' "$fill")╮${C_RESET}"
}

box_line() {
  local txt="$1" tcol="${2:-$C_WHITE}" bcol="${3:-$C_DIM}"
  emit_slide_row "${bcol}│ ${tcol}$(pad_fixed "$txt" "$INNER_W")${bcol} │${C_RESET}"
}

box_bottom() {
  local col="${1:-$C_DIM}"
  emit_slide_row "${col}╰$(repeat_char '─' "$((SLIDE_BOX_W - 2))")╯${C_RESET}"
}

write_divider() {
  printf '%s%s%s%s%s\n' "$MARGIN" "$C_DIM" "$(repeat_char '─' "$UI_W")" "$C_RESET" "$CLR_EOL"
  FRAME_ROWS=$((FRAME_ROWS + 1))
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
  local hkey="${DOCK_OK}|${DOCK_HEALTHY}|${DOCK_RUNNING}"
  if [ -n "$LAST_LOG_DOCK_SIG" ] && [ "$hkey" != "$LAST_LOG_DOCK_SIG" ]; then
    if [ "$DOCK_OK" -eq 0 ]; then
      add_event_log "ERR" "DOCK" "Docker desconectado"
    elif [ "$DOCK_HEALTHY" -eq 8 ]; then
      add_event_log "OK" "DOCK" "Cluster 8/8 healthy"
    else
      add_event_log "WARN" "DOCK" "Cluster ${DOCK_HEALTHY}/8 healthy (${DOCK_RUNNING}/8 ON)"
    fi
  fi
  LAST_LOG_DOCK_SIG="$hkey"
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

badge_str() {
  local label="$1" key="${2//-/_}" sym col
  eval "sym=\"\$D_SYM_${key}\"; col=\"\$D_COL_${key}\""
  printf '%s[%s %s]%s' "$col" "$sym" "$label" "$C_RESET"
}

badge_vis_len() {
  local label="$1"
  echo $((4 + ${#label}))
}

dock_title_meta() {
  if [ "$DOCK_OK" -eq 0 ]; then
    DOCK_T="MONITOR EN VIVO · DOCKER DESCONECTADO"
    DOCK_S="MONITOR · DOCKER CAIDO"
    DOCK_TC="$C_RED"
  elif [ "$DOCK_HEALTHY" -eq 8 ]; then
    DOCK_T="MONITOR EN VIVO · 8/8 EN LINEA"
    DOCK_S="MONITOR · 8/8 EN LINEA"
    DOCK_TC="$C_GREEN"
  else
    DOCK_T="MONITOR EN VIVO · ${DOCK_HEALTHY}/8 HEALTHY · ${DOCK_RUNNING}/8 ON"
    DOCK_S="MONITOR · ${DOCK_HEALTHY}/8 OK · ${DOCK_RUNNING}/8 ON"
    DOCK_TC="$C_YELLOW"
  fi
}

render_cluster_dock() {
  local fused="${1:-1}"
  [ ! -f "$DOCK_RAW" ] && fetch_dock_sync || parse_dock_raw
  LAST_DOCK_SIG="$DOCK_SIG"
  dock_title_meta
  local bcol="$C_CYAN" t=" $DOCK_T " max_t=$((UI_W - 6))
  [ "${#t}" -gt "$max_t" ] && t="${t:0:$max_t}"
  local fill=$(( (UI_W - 3) - ${#t} )); [ "$fill" -lt 2 ] && fill=2
  local top_l="╭─" top_r="╮" bot_l="└" bot_r="┘"
  if [ "$fused" -eq 1 ]; then
    top_l="├─"; top_r="┤"; bot_l="╰"; bot_r="╯"
  fi
  printf '%s%s%s%s%s%s%s%s%s\n' "$MARGIN" "$bcol" "$top_l" "$DOCK_TC" "$t" "$bcol" "$(repeat_char '─' "$fill")" "$top_r" "${C_RESET}${CLR_EOL}"

  local inner_full=$((UI_W - 4))
  if [ "$inner_full" -ge 74 ]; then
    local mid=$(( (inner_full - 71) / 2 )); [ "$mid" -lt 2 ] && mid=2
    local rem1=$((inner_full - (71 + mid))); [ "$rem1" -lt 0 ] && rem1=0
    printf '%s%s│ %sRED  %s %s%*s%sBD %s %s %s%*s %s│%s%s\n' \
      "$MARGIN" "$bcol" "$C_DIM" \
      "$(badge_str "gateway :8080" "api-gateway")" \
      "$(badge_str "eureka :8761" "eureka-server")" \
      "$mid" "" "$C_DIM" \
      "$(badge_str "primary" "primary")" \
      "$(badge_str "rep1" "replica1")" \
      "$(badge_str "rep2" "replica2")" \
      "$rem1" "" "$bcol" "$C_RESET" "$CLR_EOL"

    local rem2=$((inner_full - 68)); [ "$rem2" -lt 0 ] && rem2=0
    printf '%s%s│ %sAPPS %s %s %s%*s %s│%s%s\n' \
      "$MARGIN" "$bcol" "$C_DIM" \
      "$(badge_str "cuentas-1 :8081" "ms-cuentas-1")" \
      "$(badge_str "cuentas-2 :8082" "ms-cuentas-2")" \
      "$(badge_str "transacciones :8083" "ms-transacciones")" \
      "$rem2" "" "$bcol" "$C_RESET" "$CLR_EOL"
  else
    local rem1=$((inner_full - 57)); [ "$rem1" -lt 0 ] && rem1=0
    printf '%s%s│ %sRED  %s %s   %sBD %s %s %s%*s %s│%s%s\n' \
      "$MARGIN" "$bcol" "$C_DIM" \
      "$(badge_str "gw" "api-gateway")" \
      "$(badge_str "eureka" "eureka-server")" \
      "$C_DIM" \
      "$(badge_str "primary" "primary")" \
      "$(badge_str "rep1" "replica1")" \
      "$(badge_str "rep2" "replica2")" \
      "$rem1" "" "$bcol" "$C_RESET" "$CLR_EOL"

    local rem2=$((inner_full - 50)); [ "$rem2" -lt 0 ] && rem2=0
    printf '%s%s│ %sAPPS %s %s %s%*s %s│%s%s\n' \
      "$MARGIN" "$bcol" "$C_DIM" \
      "$(badge_str "cuentas-1" "ms-cuentas-1")" \
      "$(badge_str "cuentas-2" "ms-cuentas-2")" \
      "$(badge_str "transacciones" "ms-transacciones")" \
      "$rem2" "" "$bcol" "$C_RESET" "$CLR_EOL"
  fi
  printf '%s%s%s%s%s%s%s\n' "$MARGIN" "$bcol" "$bot_l" "$(repeat_char '─' "$((UI_W - 2))")" "$bot_r" "$C_RESET" "$CLR_EOL"
  FRAME_ROWS=$((FRAME_ROWS + 4))
}

format_log_line() {
  local line="$1" w="$2" ts lvl cat msg sym col mcol
  IFS='|' read -r ts lvl cat msg <<< "$line"
  case "$lvl" in
    OK)   sym="●"; col="$C_GREEN"; mcol="$C_WHITE" ;;
    WARN) sym="~"; col="$C_YELLOW"; mcol="$C_YELLOW" ;;
    ERR)  sym="✗"; col="$C_RED"; mcol="$C_RED" ;;
    *)    sym="►"; col="$C_CYAN"; mcol="$C_WHITE" ;;
  esac
  local body="$(clip_clean "${cat} ${msg}" "$((w - 11))")"
  local pad=$((w - 11 - ${#body})); [ "$pad" -lt 0 ] && pad=0
  printf '%s%s %s%s %s%s%*s%s' "$C_DIM" "$ts" "$col" "$sym" "$mcol" "$body" "$pad" "" "$C_RESET"
}

build_cluster_tile_file() {
  local out="$1"
  [ ! -f "$DOCK_RAW" ] && fetch_dock_sync || parse_dock_raw
  LAST_DOCK_SIG="$DOCK_SIG"
  dock_title_meta
  local bcol="$C_CYAN" hdr=" $(clip_clean "$DOCK_S" "$((RIGHT_W - 5))") "
  local fill=$(( (RIGHT_W - 3) - ${#hdr} )); [ "$fill" -lt 2 ] && fill=2
  local ri="$RIGHT_INNER"
  : > "$out"
  printf '%s╭─%s%s%s%s╮%s\n' "$bcol" "$DOCK_TC" "$hdr" "$bcol" "$(repeat_char '─' "$fill")" "$C_RESET" >> "$out"

  local r1_vis=31 r2_vis=29 r3_vis=31 r4_vis=26
  printf '%s│ %sRED %s %s%*s%s │%s\n' "$bcol" "$C_DIM" "$(badge_str "gw:8080" "api-gateway")" "$(badge_str "eureka:8761" "eureka-server")" "$((ri - r1_vis))" "" "$bcol" "$C_RESET" >> "$out"
  printf '%s│ %sBD  %s %s %s%*s%s │%s\n' "$bcol" "$C_DIM" "$(badge_str "pri" "primary")" "$(badge_str "rep1" "replica1")" "$(badge_str "rep2" "replica2")" "$((ri - r2_vis))" "" "$bcol" "$C_RESET" >> "$out"
  printf '%s│ %sAPP %s %s%*s%s │%s\n' "$bcol" "$C_DIM" "$(badge_str "cta1:8081" "ms-cuentas-1")" "$(badge_str "cta2:8082" "ms-cuentas-2")" "$((ri - r3_vis))" "" "$bcol" "$C_RESET" >> "$out"
  printf '%s│     %s%*s%s │%s\n' "$bcol" "$(badge_str "transacciones:8083" "ms-transacciones")" "$((ri - r4_vis))" "" "$bcol" "$C_RESET" >> "$out"
  printf '%s╰%s╯%s\n' "$bcol" "$(repeat_char '─' "$((RIGHT_W - 2))")" "$C_RESET" >> "$out"
}

build_log_tile_file() {
  local out="$1" tot_h="$2"
  local bcol="$C_DIM" hdr=" LOG EN VIVO "
  local fill=$(( (RIGHT_W - 3) - ${#hdr} )); [ "$fill" -lt 2 ] && fill=2
  : > "$out"
  printf '%s╭─%s%s%s%s╮%s\n' "$bcol" "$C_CYAN" "$hdr" "$bcol" "$(repeat_char '─' "$fill")" "$C_RESET" >> "$out"

  local slots=$((tot_h - 2)); [ "$slots" -lt 1 ] && slots=1
  local cnt
  cnt="$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')"
  cnt="${cnt:-0}"
  mapfile -t _logs < <(tail -n "$slots" "$LOG_FILE" 2>/dev/null || true)
  local i rev_idx
  for ((i = 0; i < slots; i++)); do
    rev_idx=$(( ${#_logs[@]} - 1 - i ))
    if [ "$rev_idx" -ge 0 ]; then
      printf '%s│ %s%s │%s\n' "$bcol" "$(format_log_line "${_logs[$rev_idx]}" "$RIGHT_INNER")" "$bcol" "$C_RESET" >> "$out"
    elif [ "$i" -eq 0 ] && [ "$cnt" -eq 0 ]; then
      printf '%s│ %s%s%s │%s\n' "$bcol" "$C_DIM" "$(pad_fixed "(sin eventos)" "$RIGHT_INNER")" "$bcol" "$C_RESET" >> "$out"
    else
      printf '%s│ %*s │%s\n' "$bcol" "$RIGHT_INNER" '' "$C_RESET" >> "$out"
    fi
  done

  local foot=" [L] Historial ($cnt) "
  [ "${#foot}" -gt $((RIGHT_W - 5)) ] && foot=" [L] Log "
  local fill_b=$(( (RIGHT_W - 3) - ${#foot} )); [ "$fill_b" -lt 2 ] && fill_b=2
  printf '%s╰─%s%s╯%s\n' "$bcol" "$foot" "$(repeat_char '─' "$fill_b")" "$C_RESET" >> "$out"
}

flush_dual_frame() {
  BUFFERING_LEFT=0
  local lw="$LEFT_W" li="$SLIDE_BOX_W" bcol="$C_CYAN"
  local left_cnt h
  left_cnt="$(wc -l < "$LEFT_BUF_FILE" 2>/dev/null | tr -d ' ')"
  left_cnt="${left_cnt:-0}"
  h=$((left_cnt + 2))
  [ "$h" -lt 14 ] && h=14

  local l_tile="$TMP/left_tile.txt" c_tile="$TMP/c_tile.txt" g_tile="$TMP/g_tile.txt" r_tile="$TMP/r_tile.txt"
  local lt=" $(clip_clean "$LEFT_TITLE" "$((lw - 6))") "
  local lfill=$(( (lw - 3) - ${#lt} )); [ "$lfill" -lt 2 ] && lfill=2
  : > "$l_tile"
  printf '%s╭─%s%s╮%s\n' "$bcol" "$lt" "$(repeat_char '─' "$lfill")" "$C_RESET" >> "$l_tile"
  local slots=$((h - 2)) idx=0
  while IFS= read -r lrow; do
    printf '%s│ %s%s │%s\n' "$bcol" "$lrow" "$bcol" "$C_RESET" >> "$l_tile"
    idx=$((idx + 1))
  done < "$LEFT_BUF_FILE"
  while [ "$idx" -lt "$slots" ]; do
    printf '%s│ %*s │%s\n' "$bcol" "$li" '' "$C_RESET" >> "$l_tile"
    idx=$((idx + 1))
  done
  printf '%s╰%s╯%s\n' "$bcol" "$(repeat_char '─' "$((lw - 2))")" "$C_RESET" >> "$l_tile"

  build_cluster_tile_file "$c_tile"
  build_log_tile_file "$g_tile" "$((h - 6))"
  cat "$c_tile" "$g_tile" > "$r_tile"

  mapfile -t _lt < "$l_tile"
  mapfile -t _rt < "$r_tile"
  local i
  for ((i = 0; i < h; i++)); do
    printf '%s%s %s%s%s\n' "$MARGIN" "${_lt[$i]}" "${_rt[$i]}" "$C_RESET" "$CLR_EOL"
    FRAME_ROWS=$((FRAME_ROWS + 1))
  done
}

render_log_strip() {
  [ "$DUAL_PANE" -eq 1 ] && return
  local avail=$((25 - FRAME_ROWS - 2)) slots=0
  if [ "$avail" -ge 4 ]; then slots=2; elif [ "$avail" -ge 3 ]; then slots=1; fi
  if [ "$slots" -le 0 ]; then write_divider; return; fi
  local hdr=" LOG EN VIVO ([L] historial) "
  local fill=$(( (UI_W - 3) - ${#hdr} )); [ "$fill" -lt 2 ] && fill=2
  printf '%s%s╭─%s%s%s%s╮%s%s\n' "$MARGIN" "$C_DIM" "$C_CYAN" "$hdr" "$C_DIM" "$(repeat_char '─' "$fill")" "$C_RESET" "$CLR_EOL"
  FRAME_ROWS=$((FRAME_ROWS + 1))
  mapfile -t _logs < <(tail -n "$slots" "$LOG_FILE" 2>/dev/null || true)
  local w_in=$((UI_W - 4)) i rev_idx
  for ((i = 0; i < slots; i++)); do
    rev_idx=$(( ${#_logs[@]} - 1 - i ))
    if [ "$rev_idx" -ge 0 ]; then
      printf '%s%s│ %s%s │%s%s\n' "$MARGIN" "$C_DIM" "$(format_log_line "${_logs[$rev_idx]}" "$w_in")" "$C_DIM" "$C_RESET" "$CLR_EOL"
    else
      printf '%s%s│ %s%s │%s%s\n' "$MARGIN" "$C_DIM" "$(pad_fixed "(sin eventos)" "$w_in")" "$C_DIM" "$C_RESET" "$CLR_EOL"
    fi
    FRAME_ROWS=$((FRAME_ROWS + 1))
  done
  printf '%s%s╰%s╯%s%s\n' "$MARGIN" "$C_DIM" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
  FRAME_ROWS=$((FRAME_ROWS + 1))
}

update_dock_in_place() {
  [ ! -t 1 ] && return
  if [ "$DUAL_PANE" -eq 1 ]; then
    local c_tile="$TMP/c_tile.txt" col_x=$((PAD_L + LEFT_W + 2)) r=0
    build_cluster_tile_file "$c_tile"
    printf '\033[s'
    while IFS= read -r crow; do
      printf '\033[%d;%dH%s' "$((DUAL_BODY_ROW + r))" "$col_x" "$crow"
      r=$((r + 1))
    done < "$c_tile"
    printf '\033[u'
  else
    printf '\033[s\033[%d;1H' "$DOCK_ROW"
    render_cluster_dock 1
    printf '\033[u'
  fi
}

slide_chrome() {
  local num="$1" active="$2" title="$3" cached="${4:-0}" is_live="${5:-0}"
  begin_frame
  local labels tab_len bar_len=10
  if [ "$UI_W" -lt 76 ]; then
    labels=("[1]" "[2]" "[3]" "[4]" "[5]" "[6]")
    tab_len=23
  else
    labels=("[1:Arq]" "[2:Eur]" "[3:P2P]" "[4:Rep]" "[5:Fal]" "[6:Fin]")
    tab_len=47
  fi
  [ "$UI_W" -ge 94 ] && bar_len=14
  local right badge="" badge_col="$C_DIM"
  right="$(printf '%02d/15 %s' "$num" "$(get_progress_bar "$num" 15 "$bar_len")")"
  if [ "$cached" -eq 1 ]; then
    [ "$UI_W" -ge 74 ] && badge="[CACHE · R]" || badge="[CACHE]"
    badge_col="${C_BOLD}${C_YELLOW}"
  elif [ "$is_live" -eq 1 ]; then
    [ "$UI_W" -ge 74 ] && badge="[EN VIVO]" || badge="[VIVO]"
    badge_col="${C_BOLD}${C_GREEN}"
  fi
  local r_combo="$right"
  [ "$DUAL_PANE" -eq 1 ] && [ -n "$badge" ] && r_combo="$right $badge"
  local fill=$(( (UI_W - 8) - tab_len - ${#r_combo} ))
  [ "$fill" -lt 1 ] && fill=1

  printf '%s%s╭─ ' "$MARGIN" "$C_CYAN"
  local i col
  for i in 0 1 2 3 4 5; do
    col="$C_DIM"
    [ $((i + 1)) -eq "$active" ] && col="${C_BOLD}${C_YELLOW}"
    printf '%s%s%s' "$col" "${labels[$i]}" "$C_RESET"
    [ "$i" -lt 5 ] && printf ' '
  done
  printf '%s %s %s%s' "$C_CYAN" "$(repeat_char '─' "$fill")" "$C_CYAN" "$right"
  [ "$DUAL_PANE" -eq 1 ] && [ -n "$badge" ] && printf ' %s%s%s' "$badge_col" "$badge" "$C_RESET"
  printf ' %s─╮%s%s\n' "$C_CYAN" "$C_RESET" "$CLR_EOL"
  FRAME_ROWS=$((FRAME_ROWS + 1))

  local inner_full=$((UI_W - 4)) left_title="► $title"
  if [ "$DUAL_PANE" -eq 1 ]; then
    local hy="Hyprland · ${WIN_W}c"
    local gap2=$((inner_full - ${#left_title} - ${#hy})); [ "$gap2" -lt 1 ] && gap2=1
    printf '%s%s│ %s%s%*s%s%s%s │%s%s\n' \
      "$MARGIN" "$C_CYAN" "${C_BOLD}${C_WHITE}" "$left_title" "$gap2" "" "$C_DIM" "$hy" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    printf '%s%s╰%s╯%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    FRAME_ROWS=$((FRAME_ROWS + 2))
    DUAL_BODY_ROW=$((PAD_T + 4))
    DOCK_ROW="$DUAL_BODY_ROW"
    BUFFERING_LEFT=1
    : > "$LEFT_BUF_FILE"
    LEFT_TITLE="WORKSPACE · SECCION $active"
  else
    if [ -n "$badge" ] && [ $(( ${#left_title} + 1 + ${#badge} )) -le "$inner_full" ]; then
      local gap2=$((inner_full - ${#left_title} - ${#badge}))
      printf '%s%s│ %s%s%*s%s%s%s │%s%s\n' \
        "$MARGIN" "$C_CYAN" "${C_BOLD}${C_WHITE}" "$left_title" "$gap2" "" "$badge_col" "$badge" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    else
      printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$C_CYAN" "${C_BOLD}${C_WHITE}" "$(pad_fixed "$left_title" "$inner_full")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    fi
    FRAME_ROWS=$((FRAME_ROWS + 1))
    DOCK_ROW=$((PAD_T + 3))
    render_cluster_dock 1
  fi

  if [ -t 1 ] && [ "$LAST_SCREEN_ID" != "S${num}" ]; then
    printf '\033[J'
  fi
  LAST_SCREEN_ID="S${num}"
}

show_pending_msg() {
  [ ! -t 1 ] && return
  printf '\033[s'
  printf '%s%s  [~] %s%s%s\n' "$MARGIN" "$C_YELLOW" "$1" "$C_RESET" "$CLR_EOL"
  printf '\033[J'
}

restore_pending_msg() {
  [ -t 1 ] && printf '\033[u' || true
}

open_eureka() {
  add_event_log "INFO" "SYS" "Abriendo Eureka en navegador"
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
      "OP"|"[[A")      ACT="HELP" ;;
      "")              ACT="HOME" ;;
      *)               ACT="NEXT" ;;
    esac
    return
  fi
  if [ "$k" = $'\x7f' ] || [ "$k" = $'\b' ]; then
    ACT="PREV"; return
  fi
  case "$k" in
    a|A)   ACT="PREV" ;;
    n|N)   ACT="NEXT" ;;
    r|R)   ACT="REPEAT" ;;
    m|M)   ACT="HOME" ;;
    q|Q)   ACT="QUIT" ;;
    b|B)   ACT="EUREKA" ;;
    u|U)   ACT="UTILS" ;;
    p|P)   ACT="PREP" ;;
    s|S)   ACT="STARTALL" ;;
    t|T)   ACT="SUITE" ;;
    c|C)   ACT="ENV" ;;
    w|W)   ACT="DOCK_REFRESH" ;;
    l|L)   ACT="LOG" ;;
    e|E)   ACT="EXPORT" ;;
    h|H|\?) ACT="HELP" ;;
    [1-6]) ACT="B$k" ;;
    *)     ACT="NEXT" ;;
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
  local next_lbl="${1:-Siguiente}" allow_back="${2:-1}" next_col="${3:-${C_BOLD}${C_GREEN}}"
  if [ "$DUAL_PANE" -eq 1 ] && [ "$BUFFERING_LEFT" -eq 1 ]; then
    flush_dual_frame
  elif [[ "$LAST_SCREEN_ID" == S* ]]; then
    render_log_strip
  else
    write_divider
  fi
  if [ "$allow_back" -eq 1 ]; then
    local nav_line="  [ESPACIO/→] ${next_lbl}   [←/Backspace] Anterior"
    if [ "${#nav_line}" -gt "$UI_W" ]; then
      nav_line="  [ESPACIO/→] ${next_lbl}   [←] Anterior"
    fi
    if [ "${#nav_line}" -gt "$UI_W" ]; then
      nav_line="  [ESPACIO] ${next_lbl}  [←] Atras"
    fi
    ui_line "$next_col" "$nav_line"
  else
    ui_line "$next_col" "  [ESPACIO/→] $next_lbl"
  fi
  local help_line
  if [ "$UI_W" -ge 98 ]; then
    help_line="  [1-6] Sec  [R] Act  [M] Inicio  [B] Eureka  [U] Utils  [L] Log  [E] Exportar  [?] Ayuda  [Q] Salir"
  elif [ "$UI_W" -ge 77 ]; then
    help_line="  [1-6] Sec [R] Act [M] Ini [B] Eur [U] Util [L] Log [E] Rep [?] Ayuda [Q] Salir"
  else
    help_line="  [1-6] Sec [R] Act [M] Ini [U] Util [L] Log [E] Rep [?] Ayuda [Q] Sal"
  fi
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

show_help_modal() {
  FIRST_FRAME=1
  LAST_SCREEN_ID="HELP"
  while true; do
    begin_frame 0 1
    printf '%s%s╭%s╮%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$C_CYAN" "${C_BOLD}${C_CYAN}" "$(pad_center "AYUDA RAPIDA Y ATAJOS DEL PRESENTADOR" "$INNER_W")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    printf '%s%s╰%s╯%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    ui_blank
    box_top "NAVEGACION Y CONTROL" "$C_CYAN"
    box_line "Espacio/Enter/->/N : Siguiente diapositiva" "$C_WHITE" "$C_CYAN"
    box_line "<- / Backspace / A : Anterior (desde cache sin mutar)" "$C_WHITE" "$C_CYAN"
    box_line "1 .. 6             : Saltar directo a Seccion 1..6" "$C_WHITE" "$C_CYAN"
    box_line "R                  : Re-ejecutar en vivo el slide actual" "$C_YELLOW" "$C_CYAN"
    box_line "M / Esc            : Volver a la Portada principal" "$C_WHITE" "$C_CYAN"
    box_line "B / U / W          : Abrir Eureka / Utilidades / Dock" "$C_WHITE" "$C_CYAN"
    box_line "L  |  E            : Ver log completo | Exportar reporte (.md)" "$C_CYAN" "$C_CYAN"
    box_line "H / ? / F1         : Abrir esta ayuda" "$C_CYAN" "$C_CYAN"
    box_line "Q                  : Salir de la presentacion" "$C_DIM" "$C_CYAN"
    box_bottom "$C_CYAN"
    ui_blank
    box_top "SIGNIFICADO DE ESTADOS E INDICADORES" "$C_CYAN"
    box_line "● En linea (verde)   ~ Arranque (amarillo)   ! / ✗ Caido" "$C_WHITE" "$C_CYAN"
    box_line "[EN VIVO] Prueba actual   [CACHE · R] Vista guardada" "$C_WHITE" "$C_CYAN"
    box_bottom "$C_CYAN"
    ui_line "${C_BOLD}${C_GREEN}" "  [Cualquier tecla] Volver exactamente donde estabas"
    end_frame
    [ ! -t 0 ] && break
    read_slide_key_live 0
    [ "$ACT" = "RESIZE" ] && continue
    break
  done
  FIRST_FRAME=1
}

show_log_modal() {
  FIRST_FRAME=1
  LAST_SCREEN_ID="LOG"
  while true; do
    begin_frame 0 1
    printf '%s%s╭%s╮%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$C_CYAN" "${C_BOLD}${C_CYAN}" "$(pad_center "BITACORA DE EVENTOS EN VIVO (LOG)" "$INNER_W")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    printf '%s%s╰%s╯%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    ui_blank
    local cnt
    cnt="$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')"
    cnt="${cnt:-0}"
    box_top "HISTORIAL RECIENTE ($cnt EVENTOS)" "$C_CYAN"
    if [ "$cnt" -eq 0 ]; then
      box_line "  (Sin eventos registrados todavia)" "$C_DIM" "$C_CYAN"
    else
      mapfile -t _logs < <(tail -n 14 "$LOG_FILE" 2>/dev/null || true)
      local i rev_idx
      for ((i = 0; i < ${#_logs[@]}; i++)); do
        rev_idx=$(( ${#_logs[@]} - 1 - i ))
        printf '%s%s│ %s%s │%s%s\n' "$MARGIN" "$C_CYAN" "$(format_log_line "${_logs[$rev_idx]}" "$INNER_W")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
      done
    fi
    box_bottom "$C_CYAN"
    ui_line "${C_BOLD}${C_GREEN}" "  [C] Limpiar bitacora   [Otra tecla] Volver"
    end_frame
    [ ! -t 0 ] && break
    read_slide_key_live 0
    [ "$ACT" = "RESIZE" ] && continue
    if [ "$ACT" = "ENV" ]; then
      : > "$LOG_FILE"
      add_event_log "INFO" "SYS" "Bitacora reiniciada"
      continue
    fi
    break
  done
  FIRST_FRAME=1
}

record_http_trace() {
  local method="$1" url="$2" req_json="$3" code="$4" ms="$5" hdr_f="$6" body_f="$7" note="${8:-}"
  local seq_f="$TRACE_DIR/.seq"
  local seq=0
  [ -f "$seq_f" ] && seq="$(cat "$seq_f" 2>/dev/null || echo 0)"
  seq=$((seq + 1))
  printf '%s' "$seq" > "$seq_f"
  TRACE_SEQ="$seq"
  local id
  printf -v id '%04d' "$seq"
  local ts scr
  ts="$(date +%H:%M:%S)"
  scr="${LAST_SCREEN_ID:-PORTADA}"
  printf '%s|%s|%s|%s|%s|%s|%s\n' "$ts" "$scr" "$method" "$url" "$code" "$ms" "${note//|//}" > "$TRACE_DIR/${id}.meta"
  rm -f "$TRACE_DIR/${id}.req" "$TRACE_DIR/${id}.hdr" "$TRACE_DIR/${id}.body"
  [ -n "$req_json" ] && printf '%s' "$req_json" > "$TRACE_DIR/${id}.req"
  [ -f "$hdr_f" ] && cp "$hdr_f" "$TRACE_DIR/${id}.hdr"
  [ -f "$body_f" ] && cp "$body_f" "$TRACE_DIR/${id}.body"
}

pretty_json_file() {
  local f="$1"
  [ -s "$f" ] || return 0
  case "$JSON_TOOL" in
    jq) jq . "$f" 2>/dev/null || cat "$f" ;;
    python3|python)
      "$JSON_TOOL" -m json.tool "$f" 2>/dev/null || cat "$f"
      ;;
    *) cat "$f" ;;
  esac
}

pretty_json_str() {
  local s="$1"
  [ -n "$s" ] || return 0
  case "$JSON_TOOL" in
    jq) printf '%s' "$s" | jq . 2>/dev/null || printf '%s\n' "$s" ;;
    python3|python)
      printf '%s' "$s" | "$JSON_TOOL" -m json.tool 2>/dev/null || printf '%s\n' "$s"
      ;;
    *) printf '%s\n' "$s" ;;
  esac
}

export_presentation_report() {
  local rep_dir="$REPO_DIR/reportes"
  mkdir -p "$rep_dir"
  local ts_file fname full_path
  ts_file="$(date +%Y%m%d-%H%M%S)"
  fname="reporte-${ts_file}.md"
  full_path="$rep_dir/$fname"

  {
    printf '# Reporte de Ejecución — Billetera Digital Distribuida\n\n'
    printf -- '- **Fecha y hora:** %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf -- '- **Generador:** `presentacion.sh` (Bash)\n'
    printf -- '- **Gateway:** `%s`\n' "$GATEWAY"
    printf -- '- **Eureka:** `%s`\n' "$EUREKA"
    printf -- '- **Cuentas de prueba:** Origen `%s` / Destino `%s`\n\n' "$ORIGEN" "$DESTINO"

    printf '## 1. Estado del Clúster Docker\n\n'
    fetch_dock_sync
    if [ -s "$DOCK_RAW" ]; then
      printf '| Contenedor | Estado | Salud |\n|---|---|---|\n'
      local cname line st hl
      for cname in primary replica1 replica2 eureka-server ms-cuentas-1 ms-cuentas-2 ms-transacciones api-gateway; do
        line="$(grep "^${cname}|" "$DOCK_RAW" 2>/dev/null | head -n 1 || true)"
        if [ -n "$line" ]; then
          st="$(echo "$line" | cut -d'|' -f2)"
          hl="$(echo "$line" | cut -d'|' -f3)"
          [ -z "$hl" ] && hl="-"
          printf '| `%s` | %s | %s |\n' "$cname" "$st" "$hl"
        else
          printf '| `%s` | no encontrado | - |\n' "$cname"
        fi
      done
    else
      printf '_No se pudo obtener estado de Docker Compose (daemon inactivo o sin contenedores)._\n'
    fi
    printf '\n'

    printf '## 2. Resumen de Pruebas Ejecutadas en la Sesión\n\n'
    local has_sum=0 sum_rows=""
    if [ "${CACHE_BAL_READY:-0}" -eq 1 ]; then
      has_sum=1
      sum_rows="${sum_rows}| Slide 04 · Balanceo HTTP | ${CACHE_BAL_OK:-0}/20 respuestas HTTP 200 (Round Robin) |\n"
    fi
    if [ -n "$CACHE_TX_OK_FILE" ] && [ -f "$CACHE_TX_OK_FILE" ]; then
      has_sum=1
      local c5 cod5
      c5="$(cat "$TMP/cache_tx_ok.code" 2>/dev/null || echo "-")"
      cod5="$(extract_transfer_fields "$CACHE_TX_OK_FILE" | tr -d '\r' | cut -d'|' -f2)"
      sum_rows="${sum_rows}| Slide 05 · Transferencia P2P ACID | HTTP $c5 · Comprobante \`$cod5\` |\n"
    fi
    if [ -n "$CACHE_TX_ERR_FILE" ] && [ -f "$CACHE_TX_ERR_FILE" ]; then
      has_sum=1
      local c6 msg6
      c6="$(cat "$TMP/cache_tx_err.code" 2>/dev/null || echo "-")"
      msg6="$(extract_transfer_fields "$CACHE_TX_ERR_FILE" | tr -d '\r' | cut -d'|' -f1)"
      sum_rows="${sum_rows}| Slide 06 · Rechazo Controlado | HTTP $c6 · $msg6 |\n"
    fi
    if [ "${CACHE_LECT07_READY:-0}" -eq 1 ] && [ -f "$TMP/lect_meta_07.txt" ]; then
      has_sum=1
      local ok7 sec7
      ok7="$(cut -d'|' -f1 "$TMP/lect_meta_07.txt")"
      sec7="$(cut -d'|' -f5 "$TMP/lect_meta_07.txt")"
      sum_rows="${sum_rows}| Slide 07 · Lecturas en Réplicas | $ok7/20 HTTP 200 (${sec7}s) |\n"
    fi
    if [ "${CACHE_LECT11_READY:-0}" -eq 1 ] && [ -f "$TMP/lect_meta_11.txt" ]; then
      has_sum=1
      local ok11 sec11 fb11
      ok11="$(cut -d'|' -f1 "$TMP/lect_meta_11.txt")"
      sec11="$(cut -d'|' -f5 "$TMP/lect_meta_11.txt")"
      fb11="$(cut -d'|' -f4 "$TMP/lect_meta_11.txt")"
      sum_rows="${sum_rows}| Slide 11 · Failover en Réplica 2 | $ok11/20 HTTP 200 (fallback=$fb11, ${sec11}s) |\n"
    fi
    if [ -n "$CACHE_CRIT_CODE" ]; then
      has_sum=1
      sum_rows="${sum_rows}| Slide 08 · Lectura Crítica RYOW | HTTP $CACHE_CRIT_CODE |\n"
    fi
    if [ -n "$CACHE_EST12_CODE" ]; then
      has_sum=1
      sum_rows="${sum_rows}| Slide 12 · Estado BD tras Caída | HTTP $CACHE_EST12_CODE |\n"
    fi
    if [ -n "$CACHE_EST14_CODE" ]; then
      has_sum=1
      sum_rows="${sum_rows}| Slide 14 · Estado BD Recuperación | HTTP $CACHE_EST14_CODE |\n"
    fi
    if [ "$has_sum" -eq 1 ]; then
      printf '| Prueba / Diapositiva | Resultado |\n|---|---|\n'
      printf '%b' "$sum_rows"
    else
      printf '_Aún no se han ejecutado diapositivas en vivo en esta sesión._\n'
    fi
    printf '\n'

    printf '## 3. Salidas de Peticiones HTTP (GET / POST)\n\n'
    local mf idx=0
    shopt -s nullglob
    local metas=("$TRACE_DIR"/*.meta)
    shopt -u nullglob
    if [ "${#metas[@]}" -eq 0 ]; then
      printf '_No se capturaron peticiones HTTP en esta sesión. Recorre las diapositivas [1-6] antes de exportar._\n\n'
    else
      for mf in "${metas[@]}"; do
        idx=$((idx + 1))
        local base="${mf%.meta}"
        local ts scr method url code ms note short_url
        IFS='|' read -r ts scr method url code ms note < "$mf"
        short_url="$(echo "$url" | sed -E 's|^https?://[^/]+||')"
        [ -z "$short_url" ] && short_url="$url"
        printf '### %d. `%s %s` -> HTTP `%s` (%s ms)\n\n' "$idx" "$method" "$short_url" "$code" "$ms"
        printf -- '- **Hora:** %s | **Pantalla:** `%s` | **URL:** `%s`' "$ts" "$scr" "$url"
        [ -n "$note" ] && printf ' | **Nota:** %s' "$note"
        printf '\n'

        if [ -s "${base}.req" ]; then
          printf '\n**Request Body:**\n```json\n'
          pretty_json_file "${base}.req"
          printf '\n```\n'
        fi

        if [ -s "${base}.hdr" ]; then
          local rel_hdrs="" hk hv
          for hk in X-Gateway-Handled X-Service-Instance X-Db-Node X-Db-Fallback X-Consistencia Content-Type; do
            hv="$(grep -i "^${hk}:" "${base}.hdr" 2>/dev/null | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/\r$//' || true)"
            if [ -n "$hv" ]; then
              [ -n "$rel_hdrs" ] && rel_hdrs="${rel_hdrs} · "
              rel_hdrs="${rel_hdrs}\`${hk}: ${hv}\`"
            fi
          done
          [ -n "$rel_hdrs" ] && printf -- '- **Headers de respuesta:** %s\n' "$rel_hdrs"
        fi

        printf '\n**Response Body:**\n'
        if [ ! -s "${base}.body" ]; then
          printf '_Sin cuerpo de respuesta._\n\n'
        else
          local pretty_out lang="text" first_ch
          pretty_out="$(pretty_json_file "${base}.body")"
          first_ch="$(printf '%s' "$pretty_out" | sed 's/^[[:space:]]*//' | head -c 1)"
          [ "$first_ch" = "{" ] || [ "$first_ch" = "[" ] && lang="json"
          [ "$first_ch" = "<" ] && lang="xml"
          printf '```%s\n' "$lang"
          if [ "${#pretty_out}" -gt 6000 ]; then
            printf '%s\n... [truncado a 6000 caracteres]\n' "${pretty_out:0:6000}"
          else
            printf '%s\n' "$pretty_out"
          fi
          printf '```\n\n'
        fi
      done
    fi

    printf '## 4. Bitácora de Eventos de la Sesión\n\n'
    if [ ! -s "$LOG_FILE" ]; then
      printf '_Sin eventos registrados._\n'
    else
      printf '```text\n'
      while IFS='|' read -r lts llvl lcat lmsg; do
        printf '%s [%-4s] [%-4s] %s\n' "$lts" "$llvl" "$lcat" "$lmsg"
      done < "$LOG_FILE"
      printf '```\n'
    fi
  } > "$full_path"

  add_event_log "OK" "SYS" "Reporte exportado: reportes/$fname"
  EXPORT_LAST_PATH="$full_path"
  EXPORT_LAST_REL="reportes/$fname"
  EXPORT_LAST_TRACES="$(cat "$TRACE_DIR/.seq" 2>/dev/null || echo "$TRACE_SEQ")"
  EXPORT_LAST_EVENTS="$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')"
}

show_export_modal() {
  FIRST_FRAME=1
  LAST_SCREEN_ID="EXPORT"
  export_presentation_report
  while true; do
    begin_frame 0 1
    printf '%s%s╭%s╮%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$C_CYAN" "${C_BOLD}${C_CYAN}" "$(pad_center "EXPORTACION DE REPORTE MARKDOWN" "$INNER_W")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    printf '%s%s╰%s╯%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    ui_blank
    box_top "REPORTE GENERADO EXITOSAMENTE" "$C_GREEN"
    box_line "Archivo    : $EXPORT_LAST_REL" "$C_GREEN" "$C_GREEN"
    box_line "Ruta       : $(clip_clean "$EXPORT_LAST_PATH" "$((INNER_W - 14))")" "$C_WHITE" "$C_GREEN"
    box_line "Peticiones : $EXPORT_LAST_TRACES salidas GET/POST capturadas" "$C_CYAN" "$C_GREEN"
    box_line "Eventos    : ${EXPORT_LAST_EVENTS:-0} registros en bitacora + estado Docker" "$C_WHITE" "$C_GREEN"
    box_bottom "$C_GREEN"
    ui_blank
    if [ "${EXPORT_LAST_TRACES:-0}" -eq 0 ]; then
      ui_line "$C_YELLOW" "  [TIP] Recorre las diapositivas [1-6] antes de exportar para incluir salidas GET/POST."
    else
      ui_line "$C_DIM" "  [OK] Listo para adjuntar o copiar en tu informe."
    fi
    ui_line "${C_BOLD}${C_GREEN}" "  [Cualquier tecla] Volver exactamente donde estabas"
    end_frame
    [ ! -t 0 ] && break
    read_slide_key_live 0
    [ "$ACT" = "RESIZE" ] && continue
    break
  done
  FIRST_FRAME=1
}

api_req() {
  local method="$1" url="$2" json="${3:-}" tout="${4:-10}" quiet="${5:-0}" note="${6:-}" code t0=0 t1=0
  [ "$quiet" -eq 0 ] && t0="$(now_ms)"
  local args=(-s --max-time "$tout" -o "$BODY_FILE" -D "$HEADERS_FILE" -w '%{http_code}' -X "$method" "$url")
  if [ -n "$json" ]; then
    args+=(-H 'Content-Type: application/json' -d "$json")
  else
    args+=(-H 'Accept: application/json')
  fi
  code="$(curl "${args[@]}" 2>/dev/null)" || code="000"
  [ -z "$code" ] && code="000"
  if [ "$quiet" -eq 0 ]; then
    t1="$(now_ms)"
    local short_p lvl="ERR" ms=$((t1 - t0))
    short_p="$(echo "$url" | sed -E 's|^https?://[^/]+||; s|/api/(cuentas|transacciones)/|/|')"
    [[ "$code" == 2* ]] && lvl="OK"
    [ "$code" = "409" ] && lvl="WARN"
    add_event_log "$lvl" "HTTP" "$method $short_p -> $code (${ms}ms)"
    record_http_trace "$method" "$url" "$json" "$code" "$ms" "$HEADERS_FILE" "$BODY_FILE" "$note"
  fi
  echo "$code"
}

get_header() {
  grep -i "^$1:" "$HEADERS_FILE" 2>/dev/null | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/\r$//'
}

ensure_env() {
  if [ ! -f "$REPO_DIR/.env" ]; then
    if [ -f "$REPO_DIR/.env.example" ]; then
      cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
      add_event_log "OK" "SYS" "Archivo .env creado desde .env.example"
      printf '%s  %s[OK] Archivo .env creado desde .env.example.%s\n' "$MARGIN" "$C_GREEN" "$C_RESET"
      return 0
    fi
    add_event_log "ERR" "SYS" "Falta .env y .env.example"
    printf '%s  %s[ERROR] No existe .env ni .env.example.%s\n' "$MARGIN" "$C_RED" "$C_RESET"
    return 1
  fi
  return 0
}

write_three_col_cards() {
  local t1="$1" t2="$2" t3="$3" c1="$4" c2="$5" c3="$6"
  shift 6
  local cw_base=$(( (SLIDE_BOX_W - 2) / 3 ))
  local rem=$(( (SLIDE_BOX_W - 2) - cw_base * 3 ))
  local cw0=$cw_base cw1=$cw_base cw2=$cw_base
  [ "$rem" -ge 1 ] && cw0=$((cw0 + 1))
  [ "$rem" -ge 2 ] && cw1=$((cw1 + 1))
  local cws=($cw0 $cw1 $cw2)
  local titles=("$t1" "$t2" "$t3")
  local i t cw ci fill maxt top_row="" bot_row=""

  for i in 0 1 2; do
    cw="${cws[$i]}"; maxt=$((cw - 3))
    t=" ${titles[$i]} "
    [ "${#t}" -gt "$maxt" ] && t="${t:0:$maxt}"
    fill=$(( (cw - 3) - ${#t} )); [ "$fill" -lt 1 ] && fill=1
    top_row="${top_row}${C_CYAN}╭─${t}$(repeat_char '─' "$fill")╮${C_RESET}"
    bot_row="${bot_row}${C_DIM}╰$(repeat_char '─' "$((cw - 2))")╯${C_RESET}"
    if [ "$i" -lt 2 ]; then
      top_row="${top_row} "
      bot_row="${bot_row} "
    fi
  done
  emit_slide_row "$top_row"

  local row f1 f2 f3 line_row
  for row in "$@"; do
    f1="$(echo "$row" | cut -d'|' -f1)"
    f2="$(echo "$row" | cut -d'|' -f2)"
    f3="$(echo "$row" | cut -d'|' -f3)"
    line_row="${c1}│${C_WHITE}$(pad_fixed "$f1" "$((cw0 - 2))")${c1}│ ${c2}│${C_WHITE}$(pad_fixed "$f2" "$((cw1 - 2))")${c2}│ ${c3}│${C_WHITE}$(pad_fixed "$f3" "$((cw2 - 2))")${c3}│${C_RESET}"
    emit_slide_row "$line_row"
  done
  emit_slide_row "$bot_row"
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
  code="$(api_req GET "$GATEWAY/api/cuentas/$ORIGEN/saldo-critico" "" 2 1)"
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

test_docker_ready() {
  docker info >/dev/null 2>&1
}

show_clean_prep() {
  LAST_SCREEN_ID="PREP"
  begin_frame 1 1
  printf '%s%s╭%s╮%s%s\n' "$MARGIN" "$C_YELLOW" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
  printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$C_YELLOW" "$C_YELLOW" "$(pad_center "REINICIO LIMPIO DEL ENTORNO (down -v + up -d --build)" "$INNER_W")" "$C_YELLOW" "$C_RESET" "$CLR_EOL"
  printf '%s%s╰%s╯%s%s\n' "$MARGIN" "$C_YELLOW" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
  ui_blank
  if ! test_docker_ready; then
    add_event_log "ERR" "DOCK" "Docker daemon no responde"
    box_top "DOCKER NO DISPONIBLE" "$C_RED"
    box_line "[ERROR] Docker Desktop / daemon no esta ejecutandose." "$C_RED" "$C_RED"
    box_line "Inicia Docker y vuelve a intentarlo." "$C_WHITE" "$C_RED"
    box_bottom "$C_RED"
    wait_slide_footer "Volver" 0 "$C_YELLOW"
    FIRST_FRAME=1
    return
  fi
  if [ -t 0 ]; then
    box_top "CONFIRMAR ACCION DESTRUCTIVA" "$C_YELLOW"
    box_line "[!] Se ejecutara: docker compose down -v + up -d --build" "$C_YELLOW" "$C_YELLOW"
    box_line "Se reiniciaran volumenes de BD y balances actuales." "$C_WHITE" "$C_YELLOW"
    box_bottom "$C_YELLOW"
    ui_blank
    ui_line "$C_YELLOW" "  [S] Confirmar reinicio limpio   [Otra tecla] Cancelar"
    end_frame
    local ck=""
    IFS= read -rsn1 ck || ck=""
    case "$ck" in
      s|S) ui_blank ;;
      *)
        ui_line "$C_DIM" "  [Cancelado] No se realizaron cambios en los contenedores."
        sleep 1
        FIRST_FRAME=1
        return
        ;;
    esac
  fi
  ensure_env || { wait_slide_footer "Volver" 0; FIRST_FRAME=1; return; }
  add_event_log "WARN" "SYS" "Ejecutando docker compose down -v + up --build"
  ui_line "$C_CYAN" "  \$ docker compose down -v && docker compose up -d --build"
  docker compose down -v
  docker compose up -d --build || {
    add_event_log "ERR" "DOCK" "docker compose up fallo"
    printf '\n  %s[ERROR] docker compose up fallo.%s\n' "$C_RED" "$C_RESET"
    wait_slide_footer "Volver" 0 "$C_YELLOW"; FIRST_FRAME=1; return
  }
  printf '\n  %sEsperando que los 8 contenedores esten healthy…%s\n' "$C_YELLOW" "$C_RESET"
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
  add_event_log "OK" "DOCK" "Reinicio limpio completo (8/8 healthy)"
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
    begin_frame 0 1
    DOCK_ROW=$((PAD_T + 3))
    printf '%s%s╭%s╮%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$C_CYAN" "$C_CYAN" "$(pad_center "UTILIDADES DEL ENTORNO Y VERIFICACION" "$INNER_W")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    render_cluster_dock 1

    ui_blank
    if [ ! -f "$REPO_DIR/.env" ]; then
      ui_line "$C_YELLOW" "  [AVISO] Falta .env en el repositorio (pulsa [C] o [P])."
    else
      ui_line "$C_DIM" "  [OK] Archivo .env configurado."
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
    box_line "[P] Reinicio limpio (down -v + up -d --build + Eureka)" "$C_YELLOW" "$C_CYAN"
    box_line "[S] Arrancar contenedores detenidos (docker compose start)" "$C_WHITE" "$C_CYAN"
    local eb="[C] Verificar/crear .env   |   [B] Abrir Eureka ($EUREKA)"
    [ "${#eb}" -gt "$INNER_W" ] && eb="[C] Crear .env  |  [B] Abrir Eureka ($EUREKA)"
    [ "${#eb}" -gt "$INNER_W" ] && eb="[C] Crear .env  |  [B] Abrir Eureka en navegador"
    box_line "$eb" "$C_WHITE" "$C_CYAN"
    box_line "[T] Ejecutar suite automatizada P01-P08" "$C_WHITE" "$C_CYAN"
    box_line "[E] Exportar reporte completo con salidas GET/POST (.md)" "$C_YELLOW" "$C_CYAN"
    box_line "[1..6] Ir a Seccion 1..6   |   [W] Refrescar  |  [L] Log" "$C_CYAN" "$C_CYAN"
    box_line "[M / Esc] Volver a Portada |   [?] Ayuda      |  [Q] Salir" "$C_GREEN" "$C_CYAN"
    box_bottom "$C_CYAN"
    end_frame

    read_slide_key_live 1
    case "$ACT" in
      RESIZE)       continue ;;
      HELP)         show_help_modal ;;
      LOG)          show_log_modal ;;
      EXPORT)       show_export_modal ;;
      PREP)         show_clean_prep ;;
      STARTALL)
        begin_frame 1 1
        if ! test_docker_ready; then
          add_event_log "ERR" "DOCK" "Docker daemon no responde"
          ui_line "$C_RED" "  [ERROR] Docker / daemon no responde."
        else
          add_event_log "INFO" "DOCK" "Ejecutando docker compose start"
          ensure_env || true; docker compose start; fetch_dock_sync
        fi
        wait_slide_footer "Volver" 0; FIRST_FRAME=1
        ;;
      EUREKA)       open_eureka ;;
      DOCK_REFRESH) fetch_dock_sync; update_dock_in_place ;;
      ENV)
        if [ -f "$REPO_DIR/.env" ]; then
          ui_line "$C_GREEN" "  [OK] El archivo .env ya existe."
        else
          ensure_env || true
        fi
        sleep 1
        ;;
      SUITE)
        begin_frame 1 1
        add_event_log "INFO" "SYS" "Ejecutando suite curl-p01-p08.sh"
        if [ -f "$REPO_DIR/docs/api/curl-p01-p08.sh" ]; then
          bash "$REPO_DIR/docs/api/curl-p01-p08.sh"
        else
          ui_line "$C_YELLOW" "  [AVISO] No se encontro docs/api/curl-p01-p08.sh"
        fi
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
  slide_chrome 1 1 "Arquitectura del Sistema · 8 Contenedores Docker" 0 0
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
    ui_line "$C_DIM" "  ● Gateway balancea HTTP; PostgreSQL separa escrituras y lecturas."
  else
    ui_line "$C_DIM" "  ● Gateway balancea HTTP; PostgreSQL separa write/read."
  fi
  wait_slide_footer "Detalle del clúster"
}

slide_02() {
  local use_cache="${1:-0}"
  slide_chrome 2 1 "Clúster Docker Compose · Estado de Servicios" "$use_cache" 1
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ "$CACHE_PS_READY" -eq 0 ]; then
    show_pending_msg "Consultando estado de contenedores (docker compose ps)…"
    if docker compose ps -a --format '{{.Name}}|{{.Service}}|{{.Status}}|{{.Ports}}' > "$TMP/ps_raw.txt" 2>/dev/null; then
      CACHE_PS_READY=1
      add_event_log "OK" "DOCK" "docker ps -> $(wc -l < "$TMP/ps_raw.txt" | tr -d ' ') filas"
    else
      : > "$TMP/ps_raw.txt"
      CACHE_PS_READY=0
      add_event_log "ERR" "DOCK" "docker compose ps sin respuesta"
    fi
    restore_pending_msg
  fi
  box_top "TELEMETRIA DE CONTENEDORES (docker compose ps)" "$C_CYAN"
  if [ "$CACHE_PS_READY" -eq 1 ] && [ -s "$TMP/ps_raw.txt" ]; then
    local show_ports=0
    [ "$INNER_W" -ge 72 ] && show_ports=1
    if [ "$show_ports" -eq 1 ]; then
      box_line "$(printf '%-18s %-16s %-23s %s' "CONTENEDOR" "SERVICIO" "ESTADO" "PUERTOS")" "$C_DIM" "$C_CYAN"
    else
      box_line "$(printf '%-18s %-16s %s' "CONTENEDOR" "SERVICIO" "ESTADO")" "$C_DIM" "$C_CYAN"
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
    box_line "[ERROR] Sin respuesta de docker compose." "$C_RED" "$C_CYAN"
    box_line "Accion: Verifica Docker activo o inicia con [U] -> [S]." "$C_YELLOW" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
  wait_slide_footer "2. Descubrimiento en Eureka"
}

slide_03() {
  local use_cache="${1:-0}"
  slide_chrome 3 2 "Descubrimiento Dinámico con Netflix Eureka" "$use_cache" 1
  ui_blank
  box_top "ARQUITECTURA DE DESCUBRIMIENTO" "$C_CYAN"
  box_line "● Auto-registro al iniciar y latido (heartbeat) cada 5s." "$C_WHITE" "$C_CYAN"
  box_line "● Gateway resuelve vía lb://ms-cuentas, sin IPs fijas." "$C_WHITE" "$C_CYAN"
  box_bottom "$C_CYAN"
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_EUREKA_CODE" ]; then
    show_pending_msg "Consultando registro en Eureka (:8761/eureka/apps)…"
    CACHE_EUREKA_CODE="$(api_req GET "$EUREKA/eureka/apps" "" 5 0 "Catalogo de servicios registrados en Eureka")"
    cp "$BODY_FILE" "$TMP/eureka_cache.json" 2>/dev/null || true
    restore_pending_msg
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
  elif [ "$CACHE_EUREKA_CODE" = "000" ]; then
    box_line "Sin conexion con Eureka ($EUREKA)." "$C_RED" "$C_GREEN"
    box_line "Accion: Revisa [U] Utilidades o pulsa [R] para reintentar." "$C_YELLOW" "$C_GREEN"
  else
    box_line "Eureka no responde (HTTP $CACHE_EUREKA_CODE). Pulsa [R] para reintentar." "$C_RED" "$C_GREEN"
  fi
  box_bottom "$C_GREEN"
  wait_slide_footer "Balanceo HTTP Round Robin"
}

slide_04() {
  local use_cache="${1:-0}"
  slide_chrome 4 2 "Balanceo de Carga HTTP · Round Robin" "$use_cache" 1
  ui_blank
  local sub="  Objetivo: Verificar reparto 50/50 en GET $GATEWAY/api/cuentas/instancia"
  [ "${#sub}" -gt "$INNER_W" ] && sub="  Objetivo: Reparto 50/50 en GET /api/cuentas/instancia (20 peticiones)"
  [ "${#sub}" -gt "$INNER_W" ] && sub="  20x GET /api/cuentas/instancia (Round Robin)"
  ui_line "$C_CYAN" "$sub"
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ "$CACHE_BAL_READY" -eq 0 ]; then
    show_pending_msg "Ejecutando 20 peticiones HTTP GET contra Gateway :8080…"
    : > "$TMP/balanceo.txt"
    local i code inst ok_cnt=0
    for i in $(seq 1 20); do
      code="$(api_req GET "$GATEWAY/api/cuentas/instancia" "" 5 1)"
      [ "$i" -eq 1 ] && record_http_trace "GET" "$GATEWAY/api/cuentas/instancia" "" "$code" "0" "$HEADERS_FILE" "$BODY_FILE" "Muestra testigo de balanceo Round Robin (lote de 20 peticiones)"
      [ "$code" = "200" ] && ok_cnt=$((ok_cnt + 1))
      inst="$(get_header "X-Service-Instance")"; [ -z "$inst" ] && inst="sin-cabecera"
      printf '%s %s\n' "$code" "$inst" >> "$TMP/balanceo.txt"
    done
    CACHE_BAL_OK="$ok_cnt"
    CACHE_BAL_READY=1
    local lvl="ERR"; [ "$ok_cnt" -eq 20 ] && lvl="OK"; [ "$ok_cnt" -gt 0 ] && [ "$ok_cnt" -lt 20 ] && lvl="WARN"
    add_event_log "$lvl" "HTTP" "20x GET /instancia -> $ok_cnt/20 OK"
    restore_pending_msg
  fi
  local bar_w=$((INNER_W - 42))
  [ "$bar_w" -gt 30 ] && bar_w=30
  [ "$bar_w" -lt 8 ] && bar_w=8
  box_top "DISTRIBUCION POR INSTANCIA (20 PETICIONES)" "$C_GREEN"
  box_line "$(printf '%-20s %-5s  %-*s  %s' "INSTANCIA" "HTTP" "$bar_w" "REPARTO" "CONTEO")" "$C_DIM" "$C_GREEN"
  sort "$TMP/balanceo.txt" | uniq -c | while read -r cnt code inst; do
    local pct=$(( (cnt * 100) / 20 ))
    local filled=$(( (cnt * bar_w + 10) / 20 )); [ "$filled" -gt "$bar_w" ] && filled="$bar_w"
    local bar_str col="$C_GREEN"
    bar_str="$(repeat_char '█' "$filled")$(repeat_char '░' "$((bar_w - filled))")"
    [ "$code" != "200" ] && col="$C_RED"
    echo "$inst" | grep -q 'ms-cuentas-2' && [ "$code" = "200" ] && col="$C_CYAN"
    box_line "$(printf '%-20s [%s]  %s  %2d/20 (%3d%%)' "$inst" "$code" "$bar_str" "$cnt" "$pct")" "$col" "$C_GREEN"
  done
  if [ "$CACHE_BAL_OK" -eq 0 ] && grep -q '^000 ' "$TMP/balanceo.txt"; then
    box_line "Gateway sin respuesta (HTTP 000). Revisa api-gateway en [U]." "$C_YELLOW" "$C_GREEN"
  fi
  box_bottom "$C_GREEN"
  local err_cnt=$((20 - CACHE_BAL_OK))
  local pcol="$C_GREEN"; [ "$err_cnt" -ne 0 ] && pcol="$C_RED"
  ui_line "$pcol" "  [ RESULTADO: $CACHE_BAL_OK/20 OK · ERRORES: $err_cnt · REPARTO ROUND ROBIN ]"
  wait_slide_footer "3. Comunicación entre servicios"
}

slide_05() {
  local use_cache="${1:-0}" code
  slide_chrome 5 3 "Orquestación P2P entre Microservicios · ACID" "$use_cache" 1
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
    show_pending_msg 'Ejecutando transferencia P2P de prueba ($25.00)…'
    local payload="{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":25,\"motivo\":\"Transferencia P2P\"}"
    code="$(api_req POST "$GATEWAY/api/transacciones/transferir" "$payload" 10 0 "Transferencia P2P exitosa (ACID)")"
    cp "$BODY_FILE" "$TMP/cache_tx_ok.json"
    printf '%s' "$code" > "$TMP/cache_tx_ok.code"
    CACHE_TX_OK_FILE="$TMP/cache_tx_ok.json"
    restore_pending_msg
  else
    code="$(cat "$TMP/cache_tx_ok.code")"
  fi

  local bcol="$C_YELLOW"
  [ "$code" = "201" ] || [ "$code" = "200" ] && bcol="$C_GREEN"
  [ "$code" = "000" ] && bcol="$C_RED"
  local fields msg cod sal ic nbd pol
  fields="$(extract_transfer_fields "$CACHE_TX_OK_FILE" | tr -d '\r')"
  IFS='|' read -r msg cod sal ic nbd pol <<< "$fields"
  [ "$code" = "000" ] && msg="Sin conexion con Gateway :8080 ([U]/[R])"
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
  box_line "Política Enrutado  : $pol" "$C_WHITE" "$bcol"
  box_bottom "$bcol"
  local acid="  ● Debito y credito en una sola transaccion ACID con bloqueo ordenado."
  [ "$INNER_W" -lt 68 ] && acid="  ● Debito/credito en 1 transaccion ACID con bloqueo ordenado."
  ui_line "$C_DIM" "$acid"
  wait_slide_footer "Validación saldo insuficiente"
}

slide_06() {
  local use_cache="${1:-0}" code
  slide_chrome 6 3 "Validación de Reglas de Negocio · Error Controlado" "$use_cache" 1
  ui_blank
  local pnod="$(fmt_node_width "$LAST_TX_NODO")"
  if [ "$INNER_W" -ge 74 ]; then
    ui_line "$C_CYAN" "  Escritura previa ($LAST_TX_CODIGO) -> $pnod"
  else
    ui_line "$C_CYAN" "  Escritura ($LAST_TX_CODIGO) -> $pnod"
  fi
  ui_blank

  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_TX_ERR_FILE" ] || [ ! -f "$CACHE_TX_ERR_FILE" ]; then
    show_pending_msg 'Validando rechazo controlado (monto $9999.00 > saldo)…'
    local payload="{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":9999,\"motivo\":\"Prueba limite\"}"
    code="$(api_req POST "$GATEWAY/api/transacciones/transferir" "$payload" 10 0 "Validacion de saldo insuficiente (HTTP 409)")"
    cp "$BODY_FILE" "$TMP/cache_tx_err.json"
    printf '%s' "$code" > "$TMP/cache_tx_err.code"
    CACHE_TX_ERR_FILE="$TMP/cache_tx_err.json"
    restore_pending_msg
  else
    code="$(cat "$TMP/cache_tx_err.code")"
  fi

  local bcol="$C_RED"; [ "$code" = "409" ] && bcol="$C_YELLOW"
  local fields msg cod sal ic nbd pol
  fields="$(extract_transfer_fields "$CACHE_TX_ERR_FILE" | tr -d '\r')"
  IFS='|' read -r msg cod sal ic nbd pol <<< "$fields"
  [ "$code" = "000" ] && msg="Sin conexion con Gateway :8080 ([U]/[R])"
  local mlbl="Mensaje devuelto   : "
  [ $(( ${#msg} + 21 )) -gt "$INNER_W" ] && mlbl="Mensaje  : "

  box_top "RECHAZO CONTROLADO  [ HTTP $code ]" "$bcol"
  box_line "${mlbl}${msg}" "$bcol" "$bcol"
  box_line "Monto solicitado   : \$9999.00  (supera saldo disponible)" "$C_WHITE" "$bcol"
  box_line "Integridad ACID    : Transaccion revertida; saldos intactos" "$C_GREEN" "$bcol"
  box_line "Auditoría nodoBD   : $(fmt_node_width "$nbd")" "$C_CYAN" "$bcol"
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
      code="$(api_req GET "$GATEWAY/api/$u" "" 5 1)"
      if [ "$i" -eq 1 ]; then
        local note_suffix="contactos"
        [[ "$u" == *historial* ]] && note_suffix="historial"
        local trace_note="Muestra testigo de lectura ordinaria en replica ($note_suffix, lote de 10 peticiones)"
        if [ "$tag" = "11" ]; then
          trace_note="Muestra testigo en replica superviviente tras caida de replica1 ($note_suffix, lote de 10 peticiones)"
        fi
        record_http_trace "GET" "$GATEWAY/api/$u" "" "$code" "0" "$HEADERS_FILE" "$BODY_FILE" "$trace_note"
      fi
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
  local max_node=16 dn
  while IFS='|' read -r _c _n _f; do
    dn="$(fmt_node_width "$_n")"
    [ "${#dn}" -gt "$max_node" ] && max_node="${#dn}"
  done < "$TMP/lect_${tag}.txt"
  local bar_w=$((INNER_W - 25 - max_node))
  [ "$bar_w" -gt 18 ] && bar_w=18
  [ "$bar_w" -lt 4 ] && bar_w=4
  box_top "20 LECTURAS ORDINARIAS (contactos + historial)" "$bcol"
  local bar_lbl="REPARTO"; [ "$bar_w" -lt 7 ] && bar_lbl="BAR"
  local hdr_row
  hdr_row="$(printf 'CANT  HTTP  %-*s  %-*s  FALLBACK' "$bar_w" "$bar_lbl" "$max_node" "NODO BD")"
  [ "${#hdr_row}" -le "$INNER_W" ] && box_line "$hdr_row" "$C_DIM" "$bcol"
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
    box_line "$(printf '%2d/20 [%s] %s  %-*s  fb=%s' "$cnt" "$code" "$bar_str" "$max_node" "$dnode" "$fb")" "$col" "$bcol"
  done
  box_bottom "$bcol"
  IFS='|' read -r LECT_OK LECT_ERR LECT_ERR_DETAIL LECT_FB LECT_SEC < "$TMP/lect_meta_${tag}.txt"
}

slide_07() {
  local use_cache="${1:-0}"
  slide_chrome 7 4 "Enrutamiento BD · Primario vs Réplicas WAL" "$use_cache" 1
  ui_blank
  local wnod="$(fmt_node_width "$LAST_TX_NODO")"
  if [ "$INNER_W" -ge 80 ]; then
    ui_line "$C_CYAN" "  Escrituras -> $wnod  |  Lecturas -> REPLICA_1 / REPLICA_2"
  else
    ui_line "$C_CYAN" "  Write -> $wnod | Read -> REP1/REP2"
  fi
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ "$CACHE_LECT07_READY" -eq 0 ]; then
    show_pending_msg "Ejecutando 20 lecturas ordinarias (contactos + historial)…"
    fetch_lecturas_data "07"
    CACHE_LECT07_READY=1
    IFS='|' read -r _ok07 _err07 _ed07 _fb07 _s07 < "$TMP/lect_meta_07.txt"
    local lvl07="OK"; [ "$_ok07" -ne 20 ] && lvl07="ERR"
    add_event_log "$lvl07" "HTTP" "20x lecturas R1/R2 -> $_ok07/20 OK fb=$_fb07"
    restore_pending_msg
  fi
  render_lecturas_from_cache "07" "$C_GREEN"
  local col="$C_GREEN"; [ "$LECT_ERR" -gt 0 ] && col="$C_RED"
  ui_line "$col" "  [ $LECT_OK/20 OK · ERRORES: $LECT_ERR_DETAIL · REPLICAS (recovery=true) · ${LECT_SEC}s ]"
  wait_slide_footer "Lectura crítica RYOW"
}

slide_08() {
  local use_cache="${1:-0}"
  slide_chrome 8 4 "Consistencia Inmediata · Read-Your-Own-Writes" "$use_cache" 1
  ui_blank
  box_top "ARQUITECTURA DE CONSISTENCIA" "$C_CYAN"
  if [ "$INNER_W" -ge 68 ]; then
    box_line "● Las réplicas WAL pueden presentar retardo mínimo tras escribir." "$C_WHITE" "$C_CYAN"
    box_line "● /saldo-critico fuerza lectura al PRIMARIO (RYOW garantizado)." "$C_WHITE" "$C_CYAN"
  else
    box_line "● Réplicas WAL pueden tener retardo mínimo tras escribir." "$C_WHITE" "$C_CYAN"
    box_line "● /saldo-critico fuerza lectura en PRIMARIO (RYOW)." "$C_WHITE" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_CRIT_CODE" ]; then
    show_pending_msg "Consultando /saldo-critico directo al PRIMARIO…"
    CACHE_CRIT_CODE="$(api_req GET "$GATEWAY/api/cuentas/$ORIGEN/saldo-critico" "" 5 0 "Lectura critica RYOW (consistencia inmediata en Primary)")"
    cp "$BODY_FILE" "$TMP/crit_cache.json" 2>/dev/null || true
    restore_pending_msg
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
    box_line "Política Enrutado  : $pol" "$C_YELLOW" "$C_GREEN"
  elif [ "$CACHE_CRIT_CODE" = "000" ]; then
    box_line "Sin conexion con Gateway :8080 — Verifica cluster con [U]." "$C_RED" "$C_GREEN"
  else
    box_line "HTTP $CACHE_CRIT_CODE al consultar saldo-critico" "$C_RED" "$C_GREEN"
  fi
  box_bottom "$C_GREEN"
  wait_slide_footer "5. Simulación de fallos (en vivo)" 1 "$C_YELLOW"
}

slide_09() {
  local use_cache="${1:-0}"
  slide_chrome 9 5 "Alta Disponibilidad HTTP · Caída ms-cuentas-2" "$use_cache" 1

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

  add_event_log "INFO" "FAIL" "Iniciada telemetria en vivo S09 (:8080)"
  local phase=1 total_req=0 err_req=0 c1=0 c2=0
  local event_msg="Tráfico continuo activo contra Gateway :8080"
  local ring=() abort_act="" hdr="$TMP/traf_hdr.txt" code inst ts col
  local stop_trig_ms=0 start_trig_ms=0 detect_ms=-1 rejoin_ms=-1 consec_c1=0 streak_ms=0 now_m
  : > "$TMP/s9_errs.txt"

  render_s9_body() {
    local status_txt err_codes="" tot_line s9_hint
    if [ "$INNER_W" -ge 74 ]; then
      case "$phase" in
        1) status_txt="Tráfico activo (ms-cuentas-1 + ms-cuentas-2)  |  [ESPACIO] Detener :8082" ;;
        2) status_txt="ms-cuentas-2 DETENIDA · Midiendo detección  |  [ESPACIO] Reiniciar :8082" ;;
        3) status_txt="Recuperando instancia (~25s JVM)              |  [ESPACIO] Ver resumen" ;;
      esac
    else
      case "$phase" in
        1) status_txt="Activo (:8081 + :8082) | [ESPACIO] Detener :8082" ;;
        2) status_txt=":8082 DETENIDA (detección) | [ESPACIO] Reiniciar" ;;
        3) status_txt="Recuperando JVM (~25s) | [ESPACIO] Ver resumen" ;;
      esac
    fi
    if [ "$err_req" -gt 0 ]; then
      err_codes=" [$(sort "$TMP/s9_errs.txt" | uniq -c | awk '{printf "%s %s x%s, ", $2, $3, $1}' | sed 's/, $//')]"
    fi
    tot_line="$(printf 'Total: %-4d  cta-1: %-4d  cta-2: %-4d  Errores: %d%s' "$total_req" "$c1" "$c2" "$err_req" "$err_codes")"
    [ "${#tot_line}" -gt "$INNER_W" ] && tot_line="Tot:${total_req} c1:${c1} c2:${c2} Err:${err_req}${err_codes}"
    if [ "$SLIDE_BOX_W" -ge 76 ]; then
      s9_hint="  [ESPACIO] Fase  [←] Atras  [B] Eureka  [M] Inicio  [L] Log  [?] Ayuda  [Q] Salir"
    else
      s9_hint="  [ESPACIO] Fase  [←] Atras  [L] Log  [M] Inicio  [?] Ayuda  [Q] Salir"
    fi

    if [ "$DUAL_PANE" -eq 1 ]; then
      [ -t 1 ] && printf '\033[%d;1H' "$DUAL_BODY_ROW"
      BUFFERING_LEFT=1
      : > "$LEFT_BUF_FILE"
      LEFT_TITLE="WORKSPACE · TRAFICO EN VIVO"
    else
      [ -t 1 ] && printf '\033[%d;1H' "$((DOCK_ROW + 4))"
      BUFFERING_LEFT=0
    fi

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
    ui_line "$C_CYAN" "  $(pad_fixed "$event_msg" "$INNER_W")"
    if [ "$DUAL_PANE" -eq 1 ]; then
      flush_dual_frame
      ui_line "$C_DIM" "$s9_hint"
    else
      ui_line "$C_DIM" "$s9_hint"
    fi
    end_frame
  }

  local seen_errs=""
  while true; do
    if [ "$RESIZED" -eq 1 ]; then
      slide_chrome 9 5 "Alta Disponibilidad HTTP · Caída ms-cuentas-2" 0 1
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
      if [[ "$seen_errs" != *"|$code|"* ]]; then
        seen_errs="${seen_errs}|$code|"
        add_event_log "ERR" "HTTP" "Detectado HTTP $code en rafaga S09"
      fi
      consec_c1=0; streak_ms=0
    elif echo "$inst" | grep -q 'ms-cuentas-2'; then
      c2=$((c2 + 1)); col="$C_CYAN"
      consec_c1=0; streak_ms=0
      if [ "$phase" -eq 3 ] && [ "$rejoin_ms" -lt 0 ] && [ "$start_trig_ms" -gt 0 ]; then
        rejoin_ms=$((now_m - start_trig_ms))
        local rsec="$(fmt_ms_sec "$rejoin_ms")s"
        event_msg="[EVENTO] ms-cuentas-2 reincorporada en $rsec!"
        add_event_log "OK" "FAIL" "Reincorporada ms-cuentas-2 ($rsec)"
      fi
    else
      c1=$((c1 + 1)); col="$C_GREEN"
      if [ "$phase" -ge 2 ] && [ "$detect_ms" -lt 0 ] && [ "$stop_trig_ms" -gt 0 ]; then
        [ "$consec_c1" -eq 0 ] && streak_ms="$now_m"
        consec_c1=$((consec_c1 + 1))
        if [ "$consec_c1" -ge 3 ]; then
          detect_ms=$((streak_ms - stop_trig_ms))
          local dsec="$(fmt_ms_sec "$detect_ms")s"
          event_msg="[EVENTO] Convergencia exclusiva a ms-cuentas-1 ($dsec)"
          add_event_log "OK" "FAIL" "Convergencia a ms-cuentas-1 ($dsec)"
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
        HELP)
          show_help_modal
          slide_chrome 9 5 "Alta Disponibilidad HTTP · Caída ms-cuentas-2" 0 1
          render_s9_body
          ;;
        LOG)
          show_log_modal
          slide_chrome 9 5 "Alta Disponibilidad HTTP · Caída ms-cuentas-2" 0 1
          render_s9_body
          ;;
        *)
          if [ "$phase" -eq 1 ]; then
            phase=2
            stop_trig_ms="$(now_ms)"; consec_c1=0; streak_ms=0
            event_msg="[ACCION] Deteniendo ms-cuentas-2 (docker compose stop)"
            add_event_log "WARN" "FAIL" "docker compose stop ms-cuentas-2"
            ( docker compose stop ms-cuentas-2 >/dev/null 2>&1 ) &
            BG_DOCKER_PID=$!
          elif [ "$phase" -eq 2 ]; then
            phase=3
            start_trig_ms="$(now_ms)"
            event_msg="[ACCION] Reiniciando ms-cuentas-2 (docker compose start)"
            add_event_log "INFO" "FAIL" "docker compose start ms-cuentas-2"
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
  add_event_log "$( [ "$err_req" -eq 0 ] && echo "OK" || echo "WARN" )" "FAIL" "Resumen S09: $total_req req, $err_req err, det=$det_str"

  LAST_BURST_LINES=(
    "Total: $total_req  |  Exitosas (200): $((total_req - err_req))  |  Errores: $err_req"
    "Errores transitorios : $err_summary"
    "Distribución : ms-cuentas-1=$c1  |  ms-cuentas-2=$c2"
    "Detección    : $det_str  |  Retorno: $rej_str"
    "Limitación   : Gateway reintenta GET (no POST /transferir)"
  )

  slide_chrome 9 5 "Alta Disponibilidad HTTP · Errores y Tiempos" 0 1
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
  slide_chrome 10 5 "Alta Disponibilidad BD · Caída de Réplica PG" 0 0
  ui_blank
  box_top "OBJETIVO Y MECANISMO DE FAILOVER EN CALIENTE" "$C_CYAN"
  if [ "$INNER_W" -ge 68 ]; then
    box_line "● Objetivo : Verificar continuidad de lecturas si cae replica1." "$C_WHITE" "$C_CYAN"
    box_line "● @UsarNodo: Captura el fallo SQL y reintenta en replica sana" "$C_WHITE" "$C_CYAN"
    box_line "             marcando cabecera X-Db-Fallback: true." "$C_WHITE" "$C_CYAN"
    box_line "● Sonda 3s : ReplicaHealthTracker retira replica1 tras fallar." "$C_WHITE" "$C_CYAN"
  else
    box_line "● Objetivo : Continuidad de lecturas ante caida de replica1." "$C_WHITE" "$C_CYAN"
    box_line "● @UsarNodo: Reintenta en replica sana (X-Db-Fallback: true)." "$C_WHITE" "$C_CYAN"
    box_line "● Sonda 3s : ReplicaHealthTracker retira replica1 al fallar." "$C_WHITE" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
  ui_blank
  box_top "ACCION EN VIVO AL AVANZAR (PREVENCION)" "$C_YELLOW"
  box_line "[!] Se ejecutara: docker compose stop replica1 + 20 lecturas." "$C_YELLOW" "$C_YELLOW"
  box_bottom "$C_YELLOW"
  wait_slide_footer "[!] Ejecutar: stop replica1 + 20 lecturas" 1 "$C_YELLOW"
}

slide_11() {
  local use_cache="${1:-0}"
  slide_chrome 11 5 "Failover Transparente · Lecturas sobre REPLICA_2" "$use_cache" 1
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ "$CACHE_LECT11_READY" -eq 0 ]; then
    show_pending_msg "Deteniendo replica1 y ejecutando 20 lecturas con failover…"
    add_event_log "WARN" "FAIL" "docker compose stop replica1"
    docker compose stop replica1 >/dev/null 2>&1 || true
    STOP_REP_MS="$(now_ms)"
    fetch_dock_sync
    update_dock_in_place
    fetch_lecturas_data "11"
    CACHE_LECT11_READY=1
    IFS='|' read -r _ok11 _err11 _ed11 _fb11 _s11 < "$TMP/lect_meta_11.txt"
    local lvl11="OK"; [ "$_err11" -gt 0 ] && lvl11="WARN"
    add_event_log "$lvl11" "FAIL" "Failover 20x -> $_ok11/20 OK ($_err11 err) fb=$_fb11"
    restore_pending_msg
  fi
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
  elif [ "$code" = "000" ]; then
    box_line "Sin conexion con Gateway :8080 — Verifica cluster con [U]." "$C_RED" "$C_CYAN"
  else
    box_line "HTTP $code al consultar db/estado" "$C_RED" "$C_CYAN"
  fi
  box_bottom "$C_CYAN"
}

slide_12() {
  local use_cache="${1:-0}"
  slide_chrome 12 5 "Detección Automática · Sondeo cada 3s" "$use_cache" 1
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_EST12_CODE" ]; then
    show_pending_msg "Consultando estado de salud (/api/cuentas/db/estado)…"
    CACHE_EST12_CODE="$(api_req GET "$GATEWAY/api/cuentas/db/estado" "" 5 0 "Estado del cluster PostgreSQL tras caida de replica1")"
    cp "$BODY_FILE" "$TMP/est12_cache.json" 2>/dev/null || true
    restore_pending_msg
  fi
  render_db_estado_box "SALUD DE REPLICAS (/api/cuentas/db/estado)" "$CACHE_EST12_CODE" "$TMP/est12_cache.json"
  ui_blank
  local elap="sondeo cada 3.0s"
  [ "$STOP_REP_MS" -gt 0 ] && elap="$(fmt_ms_sec $(( $(now_ms) - STOP_REP_MS )))s tras stop"
  box_top "DETECCIÓN Y LIMITACIONES" "$C_DIM"
  box_line "● Detección : $elap (ReplicaHealthTracker, c/3s)." "$C_WHITE" "$C_DIM"
  box_line "● Limitación: failover solo lectura (no promueve PRIMARY)." "$C_YELLOW" "$C_DIM"
  box_bottom "$C_DIM"
  wait_slide_footer "Reiniciar replica1 (recuperación WAL)" 1 "$C_CYAN"
}

slide_13() {
  local use_cache="${1:-0}"
  slide_chrome 13 5 "Recuperación WAL · Reinicio de replica1" "$use_cache" 1
  ui_blank
  if [ "$use_cache" -eq 0 ]; then
    show_pending_msg "Reiniciando replica1 y actualizando monitor…"
    add_event_log "INFO" "FAIL" "docker compose start replica1 (WAL sync)"
    docker compose start replica1 >/dev/null 2>&1 || true
    START_REP_MS="$(now_ms)"
    fetch_dock_sync
    update_dock_in_place
    restore_pending_msg
  fi
  ui_line "$C_CYAN" "  \$ docker compose start replica1  [OK]"
  ui_blank
  box_top "SINCRONIZACION AUTOMATICA EN CURSO" "$C_GREEN"
  box_line "[✓] Contenedor replica1 reiniciado y conectado al PRIMARY." "$C_GREEN" "$C_GREEN"
  box_line "[~] Replicando registros WAL atrasados de forma continua." "$C_YELLOW" "$C_GREEN"
  box_line "[~] Umbral de retorno: 2 chequeos sanos seguidos (2 x 3s)." "$C_CYAN" "$C_GREEN"
  box_bottom "$C_GREEN"
  wait_slide_footer "Verificar retorno al Round-Robin"
}

slide_14() {
  local use_cache="${1:-0}"
  slide_chrome 14 5 "Reincorporación Automática · Umbral 2/2" "$use_cache" 1
  ui_blank
  if [ "$use_cache" -eq 0 ] || [ -z "$CACHE_EST14_CODE" ]; then
    show_pending_msg "Consultando reincorporacion (/api/cuentas/db/estado)…"
    CACHE_EST14_CODE="$(api_req GET "$GATEWAY/api/cuentas/db/estado" "" 5 0 "Estado del cluster PostgreSQL tras reincorporacion de replica1")"
    cp "$BODY_FILE" "$TMP/est14_cache.json" 2>/dev/null || true
    restore_pending_msg
  fi
  render_db_estado_box "SALUD DE REPLICAS TRAS RECUPERACION (/api/cuentas/db/estado)" "$CACHE_EST14_CODE" "$TMP/est14_cache.json"
  ui_blank
  local elap="~6-8s habituales"
  [ "$START_REP_MS" -gt 0 ] && elap="$(fmt_ms_sec $(( $(now_ms) - START_REP_MS )))s tras start"
  box_top "RETORNO AUTOMATICO Y LIMITACION" "$C_DIM"
  box_line "● Retorno   : $elap (2x pg_is_in_recovery=true)." "$C_WHITE" "$C_DIM"
  box_line "● Limitación: depende de wal_keep_size (usar slots en prod)." "$C_YELLOW" "$C_DIM"
  box_line "● Tip       : si replica1 sigue iniciando, pulsa [R]." "$C_CYAN" "$C_DIM"
  box_bottom "$C_DIM"
  wait_slide_footer "6. Conclusiones técnicas"
}

slide_15() {
  slide_chrome 15 6 "Conclusiones · Decisiones, Limitaciones, Mejoras" 0 0
  ui_blank
  if [ "$INNER_W" -ge 72 ]; then
    write_three_col_cards "DECISIONES" "LIMITACIONES" "MEJORAS FUTURAS" "$C_GREEN" "$C_YELLOW" "$C_CYAN" \
      "· BD por @UsarNodo|· Sin failover primario|· Failover (Patroni)" \
      "  write->PRI read->REP|· Eureka único (SPOF)|· Claves idempotencia" \
      "· Round Robin + salud|· /movimiento-interno|· Retry conexión en" \
      "  chequeo 2 de 2|  expuesto en Gateway|  ms-transacciones" \
      "· Eureka sin cache +|· Límite diario no se|· Health Eureka real" \
      "  retry GET (0 err P03)|  reinicia solo|· Cerrar /mov-interno" \
      "· Flyway advisory lock|· Sin idempotencia P2P|  y Sagas / Outbox"
  else
    write_three_col_cards "DECISIONES" "LIMITACIONES" "MEJORAS" "$C_GREEN" "$C_YELLOW" "$C_CYAN" \
      "· @UsarNodo JDBC|· Sin failover PRI|· Failover Patroni" \
      "  W:PRI R:REPLICA|· Eureka único|· Idempotencia P2P" \
      "· Round-Robin 2/2|· /mov-interno en|· Retry conexión" \
      "  salud verificada|  ruta del Gateway|  ms-transacciones" \
      "· Eureka sin cache|· Límite diario|· Health Eureka" \
      "  + retry GET GW|  sin auto-reset|· Cerrar /mov-int" \
      "· Flyway adv. lock|· Sin idempotencia|  + Sagas / Outbox"
  fi
  local quote='"Redundancia en cada capa y failover transparente con integridad ACID."'
  [ "$INNER_W" -lt 74 ] && quote='"Redundancia activa, failover transparente e integridad ACID."'
  [ "$INNER_W" -lt 64 ] && quote='"Failover transparente e integridad ACID."'
  box_top "SÍNTESIS FINAL" "$C_CYAN"
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
      HELP)   show_help_modal; use_cache=1; continue ;;
      LOG)    show_log_modal;  use_cache=1; continue ;;
      EXPORT) show_export_modal; use_cache=1; continue ;;
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
    DOCK_ROW=$((PAD_T + 4))
    local inner_full=$((UI_W - 4))
    local ptitle="BILLETERA DIGITAL DISTRIBUIDA · DEMO EN VIVO"
    local psub="Replicación PostgreSQL WAL, descubrimiento Eureka y failover"
    [ "$inner_full" -lt 66 ] && ptitle="BILLETERA DIGITAL · DEMO EN VIVO"
    [ "$inner_full" -lt 70 ] && psub="Replicación Postgres WAL, Eureka y tolerancia a fallos"

    printf '%s%s╭%s╮%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
    printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$C_CYAN" "${C_BOLD}${C_CYAN}" "$(pad_center "$ptitle" "$inner_full")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    printf '%s%s│ %s%s%s │%s%s\n' "$MARGIN" "$C_CYAN" "$C_DIM" "$(pad_center "$psub" "$inner_full")" "$C_CYAN" "$C_RESET" "$CLR_EOL"
    FRAME_ROWS=$((FRAME_ROWS + 3))

    if [ "$DUAL_PANE" -eq 1 ]; then
      printf '%s%s╰%s╯%s%s\n' "$MARGIN" "$C_CYAN" "$(repeat_char '─' "$((UI_W - 2))")" "$C_RESET" "$CLR_EOL"
      FRAME_ROWS=$((FRAME_ROWS + 1))
      DUAL_BODY_ROW=$((PAD_T + 5))
      DOCK_ROW="$DUAL_BODY_ROW"
      BUFFERING_LEFT=1
      : > "$LEFT_BUF_FILE"
      LEFT_TITLE="MENU PRINCIPAL · RECORRIDO"
    else
      render_cluster_dock 1
    fi
    if [ -t 1 ] && [ "$LAST_SCREEN_ID" != "PORTADA" ]; then
      printf '\033[J'
    fi
    LAST_SCREEN_ID="PORTADA"

    [ "$DUAL_PANE" -eq 1 ] && ui_blank
    local leg="  ● En línea   ~ Iniciando   ✗ Caído     (actualizado en segundo plano)"
    [ "$INNER_W" -lt 72 ] && leg="  ● En línea   ~ Iniciando   ✗ Caído"
    ui_line "$C_DIM" "$leg"
    ui_blank

    local ag_title="RECORRIDO (15 DIAPOSITIVAS) · ELIGE SECCIÓN [1-6]"
    [ "$INNER_W" -lt 70 ] && ag_title="RECORRIDO (15 SLIDES) · PULSA [1-6]"
    box_top "$ag_title" "$C_CYAN"
    local col_l=$(( (INNER_W - 3) / 2 ))
    local col_r=$(( INNER_W - 3 - col_l ))
    local tw1=$((col_l - 11)) tw2=$((col_r - 11))
    [ "$tw1" -lt 8 ] && tw1=8
    [ "$tw2" -lt 8 ] && tw2=8
    local ag_items
    if [ "$INNER_W" -ge 72 ]; then
      ag_items=(
        "[1]|Arquitectura y Docker|(01-02)|[4]|Lecturas Réplica/RYOW|(07-08)"
        "[2]|Eureka y Balanceo HTTP|(03-04)|[5]|Caídas: App y Postgres|(09-14)"
        "[3]|Transferencia P2P ACID|(05-06)|[6]|Conclusiones Técnicas|   (15)"
      )
    else
      ag_items=(
        "[1]|Arquitectura|(01-02)|[4]|Lecturas y RYOW|(07-08)"
        "[2]|Eureka/Balanceo|(03-04)|[5]|Fallos App/BD|(09-14)"
        "[3]|P2P Transf ACID|(05-06)|[6]|Conclusiones|   (15)"
      )
    fi
    local ar b1 t1 r1 b2 t2 r2 row_str
    for ar in "${ag_items[@]}"; do
      IFS='|' read -r b1 t1 r1 b2 t2 r2 <<< "$ar"
      row_str="${C_CYAN}│ ${C_BOLD}${C_YELLOW}${b1} ${C_WHITE}$(pad_fixed "$t1" "$tw1")${C_DIM}${r1} │ ${C_BOLD}${C_YELLOW}${b2} ${C_WHITE}$(pad_fixed "$t2" "$tw2")${C_DIM}${r2}${C_CYAN} │${C_RESET}"
      emit_slide_row "$row_str"
    done
    box_bottom "$C_CYAN"

    local now
    now=$(date +%s)
    if [ $((now - last_sal_poll)) -ge 4 ]; then
      sinfo="$(get_saldo_line | tr -d '\r' || true)"
      last_sal_poll="$now"
    fi

    [ "$DUAL_PANE" -eq 1 ] && ui_blank
    if [ -n "$sinfo" ]; then
      local s c l col="$C_GREEN" badge=" [LISTO]" acct_line
      s="$(echo "$sinfo" | cut -d'|' -f1)"; c="$(echo "$sinfo" | cut -d'|' -f2)"; l="$(echo "$sinfo" | cut -d'|' -f3)"
      if awk -v v="${c:-0}" 'BEGIN{exit !(v+0 > 0)}'; then
        col="$C_YELLOW"
        if [ "$SLIDE_BOX_W" -ge 86 ]; then
          badge=" [REINICIAR CON U->P]"
        elif [ "$SLIDE_BOX_W" -ge 72 ]; then
          badge=" [REINICIAR U->P]"
        else
          badge=" [U->P]"
        fi
      fi
      if [ "$SLIDE_BOX_W" -ge 86 ]; then
        acct_line="  Cuenta demo $ORIGEN : saldo=\$$s | hoy=\$$c/\$$l$badge"
      elif [ "$SLIDE_BOX_W" -ge 72 ]; then
        acct_line="  Cuenta $ORIGEN: saldo=\$$s | hoy=\$$c/\$$l$badge"
      else
        acct_line="  $ORIGEN: saldo=\$$s | hoy=\$$c/\$$l$badge"
      fi
      ui_line "$col" "$acct_line"
    elif [ ! -f "$REPO_DIR/.env" ]; then
      ui_line "$C_YELLOW" "  [AVISO] Gateway sin respuesta y falta .env -> [U] -> [C] / [P]"
    else
      ui_line "$C_DIM" "  Gateway :8080 sin conexión -> Pulsa [U] para iniciar servicios"
    fi

    if [ "$DUAL_PANE" -eq 1 ]; then
      flush_dual_frame
    else
      render_log_strip
    fi
    local sp="  ► [ESPACIO / ENTER] Iniciar Presentación (Diapositiva 1/15)"
    local np="    Atajos: [1-6] Sec  [B] Eureka  [U] Utils  [L] Log  [E] Exportar  [?] Ayuda  [Q] Salir"
    [ "$UI_W" -lt 68 ] && sp="  ► [ESPACIO/→] Iniciar Presentación (1/15)"
    if [ "$UI_W" -lt 74 ]; then
      np="    [1-6] Sec [B] Eur [U] Util [L] Log [E] Rep [?] Ayuda [Q] Salir"
    elif [ "$UI_W" -lt 92 ]; then
      np="    [1-6] Sec  [B] Eureka  [U] Utils  [L] Log  [E] Rep  [?] Ayuda  [Q] Salir"
    fi
    ui_line "${C_BOLD}${C_GREEN}" "$sp"
    ui_line "$C_DIM" "$np"
    end_frame

    read_slide_key_live 1
    case "$ACT" in
      RESIZE)       continue ;;
      HELP)         show_help_modal; last_sal_poll=0 ;;
      LOG)          show_log_modal;  last_sal_poll=0 ;;
      EXPORT)       show_export_modal; last_sal_poll=0 ;;
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
