#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SESSION_NAME=""
RUN_ID=""
LOG_FILE=""
STATUS_FILE=""
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"

MAIL_ENABLED="${MAIL_ENABLED:-1}"
MAIL_FROM_NAME="${MAIL_FROM_NAME:-机器人}"
MAIL_FROM_ADDR="${MAIL_FROM_ADDR:-$(whoami)@$(hostname)}"
MAIL_TO="${MAIL_TO:-}"
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-Node Android Build}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
SMTP_HOST="${SMTP_HOST:-smtp.qq.com}"
SMTP_PORT="${SMTP_PORT:-587}"

NODE_ANDROID_BUILD_COMMAND="${NODE_ANDROID_BUILD_COMMAND:-}"

START_TIME=""
END_TIME=""
FINAL_STATE="UNKNOWN"
FINAL_EXIT_CODE=""
RUNNER_EXIT_HANDLED=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build/node-android-build-runner.sh \
    --session-name <name> \
    --run-id <id> \
    --log-file <path> \
    --status-file <path> \
    [--build-jobs <n>]
EOF
}

log() {
  printf '[RUNNER] %s\n' "$*"
}

die() {
  printf '[RUNNER][ERROR] %s\n' "$*" >&2
  exit 1
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

write_status_file() {
  mkdir -p "$(dirname "$STATUS_FILE")"
  {
    printf 'SESSION_NAME=%q\n' "$SESSION_NAME"
    printf 'RUN_ID=%q\n' "$RUN_ID"
    printf 'STATE=%q\n' "$FINAL_STATE"
    printf 'EXIT_CODE=%q\n' "$FINAL_EXIT_CODE"
    printf 'START_TIME=%q\n' "$START_TIME"
    printf 'END_TIME=%q\n' "$END_TIME"
    printf 'LOG_FILE=%q\n' "$LOG_FILE"
    printf 'ROOT_DIR=%q\n' "$ROOT_DIR"
    printf 'BUILD_JOBS=%q\n' "$BUILD_JOBS"
    printf 'HOSTNAME_VALUE=%q\n' "$(hostname)"
    printf 'USER_VALUE=%q\n' "$(whoami)"
  } > "$STATUS_FILE"
}

find_artifact() {
  find "$ROOT_DIR/dist" -maxdepth 3 -type f -name 'libnode.so' 2>/dev/null | sort | tail -n 1
}

mail_env_ready() {
  [[ -n "$MAIL_TO" && -n "$SMTP_USER" && -n "$SMTP_PASS" ]]
}

send_notification_mail() {
  local artifact_path subject body tail_excerpt

  artifact_path="$(find_artifact || true)"
  tail_excerpt="$(tail -n 40 "$LOG_FILE" 2>/dev/null || true)"
  subject="${MAIL_SUBJECT_PREFIX} ${FINAL_STATE}: ${SESSION_NAME}"

  body="$(cat <<EOF
Session: ${SESSION_NAME}
Run ID: ${RUN_ID}
State: ${FINAL_STATE}
Exit code: ${FINAL_EXIT_CODE}
Host: $(hostname)
User: $(whoami)
Started: ${START_TIME}
Ended: ${END_TIME}
Log file: ${LOG_FILE}
Artifact: ${artifact_path:-<not-found>}
Working directory: ${ROOT_DIR}
Build jobs: ${BUILD_JOBS}
EOF
)"

  if [[ "$FINAL_STATE" != "SUCCESS" && -n "$tail_excerpt" ]]; then
    body+=$'\n\nLast 40 log lines:\n'
    body+="$tail_excerpt"
  fi

  curl -sS --ssl-reqd \
    --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
    --user "${SMTP_USER}:${SMTP_PASS}" \
    --mail-from "$SMTP_USER" \
    --login-options AUTH=LOGIN \
    --mail-rcpt "$MAIL_TO" \
    --upload-file - <<EOF
From: ${MAIL_FROM_NAME} <${MAIL_FROM_ADDR}>
To: ${MAIL_TO}
Subject: ${subject}
Content-Type: text/plain; charset=UTF-8

${body}
EOF
}

handle_exit() {
  local exit_code="${1:-1}"

  if [[ "$RUNNER_EXIT_HANDLED" == "1" ]]; then
    return
  fi
  RUNNER_EXIT_HANDLED=1

  END_TIME="$(timestamp)"
  FINAL_EXIT_CODE="$exit_code"

  if [[ "$exit_code" == "0" ]]; then
    FINAL_STATE="SUCCESS"
  else
    FINAL_STATE="FAILED"
  fi

  write_status_file
  log "build finished with state=${FINAL_STATE} exit_code=${FINAL_EXIT_CODE}"

  if [[ "$MAIL_ENABLED" != "1" ]]; then
    log "mail notification disabled"
  elif ! mail_env_ready; then
    log "mail notification skipped: MAIL_TO/SMTP_USER/SMTP_PASS not fully set in environment"
  elif ! send_notification_mail; then
    log "mail notification failed"
  else
    log "mail notification sent"
  fi
}

run_build() {
  if [[ -f /etc/profile.d/node-android-env.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/node-android-env.sh
  fi

  cd "$ROOT_DIR"

  if [[ -n "$NODE_ANDROID_BUILD_COMMAND" ]]; then
    log "running custom build command from NODE_ANDROID_BUILD_COMMAND"
    bash -lc "$NODE_ANDROID_BUILD_COMMAND"
  else
    BUILD_JOBS="$BUILD_JOBS" "$ROOT_DIR/scripts/build/build-node-android.sh" build
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-name)
        SESSION_NAME="${2:?missing value for --session-name}"
        shift 2
        ;;
      --run-id)
        RUN_ID="${2:?missing value for --run-id}"
        shift 2
        ;;
      --log-file)
        LOG_FILE="${2:?missing value for --log-file}"
        shift 2
        ;;
      --status-file)
        STATUS_FILE="${2:?missing value for --status-file}"
        shift 2
        ;;
      --build-jobs)
        BUILD_JOBS="${2:?missing value for --build-jobs}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  [[ -n "$SESSION_NAME" ]] || die "missing --session-name"
  [[ -n "$RUN_ID" ]] || die "missing --run-id"
  [[ -n "$LOG_FILE" ]] || die "missing --log-file"
  [[ -n "$STATUS_FILE" ]] || die "missing --status-file"
}

main() {
  parse_args "$@"

  mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATUS_FILE")"
  touch "$LOG_FILE"

  exec > >(tee -a "$LOG_FILE") 2>&1

  START_TIME="$(timestamp)"
  END_TIME=""
  FINAL_STATE="RUNNING"
  FINAL_EXIT_CODE=""
  write_status_file

  trap 'handle_exit $?' EXIT

  log "session=${SESSION_NAME}"
  log "run_id=${RUN_ID}"
  log "log_file=${LOG_FILE}"
  log "status_file=${STATUS_FILE}"
  log "build_jobs=${BUILD_JOBS}"
  log "started_at=${START_TIME}"

  run_build
}

main "$@"
