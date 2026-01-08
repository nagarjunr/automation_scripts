#!/usr/bin/env bash
set -euo pipefail

# backup_pack.sh
# Cleans backups (removes venv + caches), optionally dedupes, then archives each folder.
#
# Usage:
#   ./backup_pack.sh [--apply] [--dedupe=off|report|interactive] [--out=DIR] FOLDER [FOLDER...]
#
# Examples:
#   ./backup_pack.sh --out=./archives backup1 backup2 backup3 backup4
#   ./backup_pack.sh --apply --out=./archives backup1 backup2 backup3 backup4
#   ./backup_pack.sh --apply --dedupe=report --out=./archives backup1 backup2 backup3 backup4
#   ./backup_pack.sh --apply --dedupe=interactive --out=./archives backup1 backup2 backup3 backup4

APPLY="no"
DEDUPE="off"          # off | report | interactive
OUT_DIR="./archives"

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY="yes"; shift || true ;;
    --dedupe=*) DEDUPE="${arg#*=}"; shift || true ;;
    --out=*) OUT_DIR="${arg#*=}"; shift || true ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "ERROR: Provide one or more folders."
  echo "Usage: ./backup_pack.sh [--apply] [--dedupe=off|report|interactive] [--out=DIR] FOLDER [FOLDER...]"
  exit 1
fi

if [[ "$DEDUPE" != "off" && "$DEDUPE" != "report" && "$DEDUPE" != "interactive" ]]; then
  echo "ERROR: --dedupe must be one of: off, report, interactive"
  exit 1
fi

mkdir -p "$OUT_DIR"
LOG_FILE="$OUT_DIR/backup_pack_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "ERROR: Missing command: $1"; exit 1; }
}

need_cmd find
need_cmd du
need_cmd tar

# jdupes is optional unless dedupe is enabled
if [[ "$DEDUPE" != "off" ]]; then
  if ! command -v jdupes >/dev/null 2>&1; then
    log "ERROR: jdupes not found. Install:"
    log "  macOS: brew install jdupes"
    log "  Ubuntu/Debian: sudo apt-get install jdupes"
    exit 1
  fi
fi

FOLDERS=("$@")

log "Mode: APPLY=$APPLY, DEDUPE=$DEDUPE, OUT_DIR=$OUT_DIR"
log "Folders: ${FOLDERS[*]}"

human_size() {
  # portable-ish human size using du -sh
  du -sh "$1" 2>/dev/null | awk '{print $1}'
}

log "Initial sizes:"
for f in "${FOLDERS[@]}"; do
  if [[ ! -d "$f" ]]; then
    log "ERROR: Not a directory: $f"
    exit 1
  fi
  log "  $(human_size "$f")  $f"
done

# Patterns to remove (directories)
# Add more if you want.
REMOVE_DIRS=(
  "venv"
  ".venv"
  "env"
  "__pycache__"
  ".pytest_cache"
  ".mypy_cache"
  ".ruff_cache"
  ".tox"
)

log "Directories marked for removal:"
printf '  - %s\n' "${REMOVE_DIRS[@]}" | tee -a "$LOG_FILE"

remove_junk() {
  local root="$1"

  log "Scanning for junk in: $root"

  # Build the find expression: \( -name "a" -o -name "b" ... \) -prune -print
  local expr=""
  for d in "${REMOVE_DIRS[@]}"; do
    if [[ -z "$expr" ]]; then
      expr="-name \"$d\""
    else
      expr="$expr -o -name \"$d\""
    fi
  done

  # shellcheck disable=SC2086
  local matches
  matches=$(eval "find \"$root\" -type d \\( $expr \\) -prune -print" || true)

  if [[ -z "${matches// }" ]]; then
    log "  No matching junk dirs found under $root"
    return 0
  fi

  log "  Found junk dirs (sample up to 50 shown):"
  echo "$matches" | head -n 50 | sed 's/^/    /' | tee -a "$LOG_FILE"

  if [[ "$APPLY" == "yes" ]]; then
    log "  Deleting junk dirs under $root"
    # shellcheck disable=SC2086
    eval "find \"$root\" -type d \\( $expr \\) -prune -exec rm -rf {} +" >>"$LOG_FILE" 2>&1
  else
    log "  Dry run only. Use --apply to actually delete."
  fi
}

# Optional dedupe across all folders
dedupe_all() {
  log "Deduplication: $DEDUPE"

  if [[ "$DEDUPE" == "report" ]]; then
    log "Generating duplicate report (content-based). This can take time on huge trees."
    jdupes -r "${FOLDERS[@]}" | tee -a "$LOG_FILE" >/dev/null
    log "Duplicate report written to: $LOG_FILE"
  elif [[ "$DEDUPE" == "interactive" ]]; then
    log "Interactive dedupe started. You will be prompted to choose which duplicates to delete."
    log "Tip: Keep the newest backup copy, delete older ones."
    if [[ "$APPLY" != "yes" ]]; then
      log "ERROR: interactive dedupe requires --apply because it deletes files."
      exit 1
    fi
    jdupes -rd "${FOLDERS[@]}" | tee -a "$LOG_FILE" >/dev/null
    log "Interactive dedupe completed."
  else
    log "Deduplication disabled."
  fi
}

archive_folder() {
  local folder="$1"
  local base
  base="$(basename "$folder")"
  local stamp
  stamp="$(date +%Y%m%d_%H%M%S)"
  local out="$OUT_DIR/${base}_${stamp}.tar.gz"

  log "Archiving: $folder -> $out"

  # tar excludes: apply the same junk patterns.
  # Note: --exclude patterns are relative matches.
  local tar_excludes=()
  for d in "${REMOVE_DIRS[@]}"; do
    tar_excludes+=( "--exclude=$d" )
  done
  # Exclude git metadata by default (optional, comment out if you want it)
  tar_excludes+=( "--exclude=.git" )

  if [[ "$APPLY" == "yes" ]]; then
    tar -czf "$out" "${tar_excludes[@]}" -C "$(dirname "$folder")" "$base" >>"$LOG_FILE" 2>&1
    log "  Archive created: $out ($(human_size "$out"))"
  else
    log "  Dry run only. Would create: $out"
    log "  Use --apply to actually create archives."
  fi
}

# 1) Clean junk
for f in "${FOLDERS[@]}"; do
  remove_junk "$f"
done

# 2) Optional dedupe
if [[ "$DEDUPE" != "off" ]]; then
  dedupe_all
fi

# 3) Archive each folder
for f in "${FOLDERS[@]}"; do
  archive_folder "$f"
done

log "Final sizes:"
for f in "${FOLDERS[@]}"; do
  log "  $(human_size "$f")  $f"
done

log "Done. Log: $LOG_FILE"
