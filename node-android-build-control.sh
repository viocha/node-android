#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${ROOT_DIR}/.state/node-android-build"
LOG_DIR="${ROOT_DIR}/logs"
RUNNER_SCRIPT="${ROOT_DIR}/scripts/build/node-android-build-runner.sh"
CURRENT_ENV_FILE="${STATE_DIR}/current.env"

CONTROLLER_SESSION_NAME="${SESSION_NAME:-node-android-build}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"

usage() {
  cat <<'EOF'
Usage:
  ./node-android-build-control.sh <command>

Commands:
  start    Start the only detached zellij build session
  status   Show current build status
  attach   Attach to the current build session
  stop     Stop and delete the current build session
  logs     Print the current log path and the last 80 lines
  current  Print the current metadata file path

Notes:
  This controller is single-session by design.
  Only one build session can exist at a time.
EOF
}

log() {
  printf '[CONTROL] %s\n' "$*"
}

die() {
  printf '[CONTROL][ERROR] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

timestamp() {
  date -u '+%Y%m%dT%H%M%SZ'
}

session_line() {
  zellij list-sessions 2>/dev/null | sed -r 's/\x1B\[[0-9;]*[[:alpha:]]//g' | awk -v session="$CONTROLLER_SESSION_NAME" '$1 == session { print; exit }'
}

session_exists() {
  [[ -n "$(session_line)" ]]
}

session_active() {
  local line=""

  line="$(session_line)"
  [[ -n "$line" && "$line" != *"(EXITED"* ]]
}

load_current_env() {
  [[ -f "$CURRENT_ENV_FILE" ]] || die "current metadata not found: $CURRENT_ENV_FILE"
  # shellcheck disable=SC1090
  source "$CURRENT_ENV_FILE"
}

write_current_env() {
  mkdir -p "$STATE_DIR"
  {
    printf 'SESSION_NAME=%q\n' "$SESSION_NAME"
    printf 'RUN_ID=%q\n' "$RUN_ID"
    printf 'LOG_FILE=%q\n' "$LOG_FILE"
    printf 'STATUS_FILE=%q\n' "$STATUS_FILE"
    printf 'LAYOUT_FILE=%q\n' "$LAYOUT_FILE"
    printf 'BUILD_JOBS=%q\n' "$BUILD_JOBS"
    printf 'ROOT_DIR=%q\n' "$ROOT_DIR"
  } > "$CURRENT_ENV_FILE"
}

create_layout_file() {
  mkdir -p "$STATE_DIR"
  cat > "$LAYOUT_FILE" <<EOF
layout {
  pane command="${RUNNER_SCRIPT}" close_on_exit=false {
    args "--session-name" "${CONTROLLER_SESSION_NAME}" "--run-id" "${RUN_ID}" "--log-file" "${LOG_FILE}" "--status-file" "${STATUS_FILE}" "--build-jobs" "${BUILD_JOBS}"
  }
}
EOF
}

start_session() {
  need_cmd zellij
  need_cmd bash

  mkdir -p "$STATE_DIR" "$LOG_DIR"
  chmod +x "$RUNNER_SCRIPT"

  if session_active; then
    die "build session is already running: ${CONTROLLER_SESSION_NAME}"
  fi

  if session_exists; then
    zellij delete-session --force "$CONTROLLER_SESSION_NAME"
  fi

  RUN_ID="$(timestamp)"
  SESSION_NAME="$CONTROLLER_SESSION_NAME"
  LOG_FILE="${LOG_DIR}/${CONTROLLER_SESSION_NAME}-${RUN_ID}.log"
  STATUS_FILE="${STATE_DIR}/${CONTROLLER_SESSION_NAME}-${RUN_ID}.status"
  LAYOUT_FILE="${STATE_DIR}/${CONTROLLER_SESSION_NAME}.kdl"

  create_layout_file
  write_current_env

  zellij attach --create-background "$CONTROLLER_SESSION_NAME" options \
    --default-cwd "$ROOT_DIR" \
    --default-layout "$LAYOUT_FILE"

  log "started detached session: $CONTROLLER_SESSION_NAME"
  log "run id: $RUN_ID"
  log "attach with: zellij attach $CONTROLLER_SESSION_NAME"
  log "log file: $LOG_FILE"
  log "status file: $STATUS_FILE"
}

print_status() {
  local is_active="no"
  local log_lines="0"

  load_current_env

  if session_active; then
    is_active="yes"
  fi

  if [[ -f "$LOG_FILE" ]]; then
    log_lines="$(wc -l < "$LOG_FILE" | tr -d '[:space:]')"
  fi

  printf 'session      : %s\n' "$CONTROLLER_SESSION_NAME"
  printf 'run_id       : %s\n' "${RUN_ID:-unknown}"
  printf 'active       : %s\n' "$is_active"
  printf 'log_file     : %s\n' "$LOG_FILE"
  printf 'log_lines    : %s\n' "$log_lines"
  printf 'status_file  : %s\n' "$STATUS_FILE"

  if [[ -f "$STATUS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATUS_FILE"
    printf 'state        : %s\n' "${STATE:-UNKNOWN}"
    if [[ "${STATE:-UNKNOWN}" == "RUNNING" ]]; then
      printf 'exit_code    : %s\n' "running"
    elif [[ -n "${EXIT_CODE:-}" ]]; then
      printf 'exit_code    : %s\n' "$EXIT_CODE"
    else
      printf 'exit_code    : %s\n' "unknown"
    fi
    printf 'started      : %s\n' "${START_TIME:-unknown}"
    printf 'ended        : %s\n' "${END_TIME:-unknown}"
  else
    printf 'state        : %s\n' "PENDING"
  fi
}

attach_session() {
  if ! session_exists; then
    die "session not found: ${CONTROLLER_SESSION_NAME}"
  fi
  exec zellij attach "$CONTROLLER_SESSION_NAME"
}

stop_session() {
  if session_exists; then
    zellij delete-session --force "$CONTROLLER_SESSION_NAME"
    log "deleted session: $CONTROLLER_SESSION_NAME"
  else
    log "session not found: $CONTROLLER_SESSION_NAME"
  fi
}

show_logs() {
  load_current_env
  printf 'log_file: %s\n' "$LOG_FILE"

  if [[ -f "$LOG_FILE" ]]; then
    tail -n 80 "$LOG_FILE"
  else
    printf 'log file does not exist yet\n'
  fi
}

show_current() {
  printf '%s\n' "$CURRENT_ENV_FILE"
}

main() {
  local command="${1:-}"

  case "$command" in
    start)
      start_session
      ;;
    status)
      print_status
      ;;
    attach)
      attach_session
      ;;
    stop)
      stop_session
      ;;
    logs)
      show_logs
      ;;
    current)
      show_current
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      die "unknown command: $command"
      ;;
  esac
}

main "$@"
