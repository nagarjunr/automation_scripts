#!/usr/bin/env bash

#===============================================================================
# Backup Organizer Script
#===============================================================================
# Description:
#   Cleans backup folders by removing temporary/cache directories (venv, 
#   node_modules, __pycache__, etc.), optionally finds duplicates, and 
#   creates compressed archives.
#
# Features:
#   - Removes common development artifacts and cache directories
#   - Optional deduplication across multiple folders
#   - Creates compressed tar.gz archives
#   - Dry-run mode for safe preview
#   - Detailed logging with timestamps
#   - Progress indicators for long operations
#
# Usage:
#   ./organize_backups.sh [OPTIONS] FOLDER [FOLDER...]
#
# Options:
#   --apply              Actually perform operations (default is dry-run)
#   --dedupe=MODE        Deduplication mode: off|report|interactive (default: off)
#   --out=DIR            Output directory for archives (default: ./archives)
#   --skip-size-calc     Skip initial/final size calculations (faster)
#   --clean-only         Only clean junk, skip deduplication and archiving
#   --verbose            Enable verbose output
#   --help               Show this help message
#
# Examples:
#   # Dry-run (preview what would be cleaned):
#   ./organize_backups.sh --out=./archives backup1 backup2
#
#   # Actually clean and create archives:
#   ./organize_backups.sh --apply --out=./archives backup1 backup2
#
#   # Clean + generate duplicate report:
#   ./organize_backups.sh --apply --dedupe=report backup1 backup2
#
#   # Clean only, skip archiving (faster):
#   ./organize_backups.sh --apply --clean-only --skip-size-calc backup1 backup2
#
#===============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Default settings
APPLY="no"
DEDUPE="off"          # off | report | interactive
OUT_DIR="./archives"
SKIP_SIZE="no"
CLEAN_ONLY="no"
VERBOSE="no"

#===============================================================================
# Cleanup Patterns
#===============================================================================
# Directories to be removed during cleanup phase
readonly REMOVE_DIRS=(
  # Python virtual environments and caches
  "venv"
  "venv*"
  ".venv"
  "env"
  "PythonVirEnv"
  "python_venv"
  "__pycache__"
  ".pytest_cache"
  ".mypy_cache"
  ".ruff_cache"
  ".tox"
  "*.egg-info"
  "dist"
  "build"
  
  # Node.js
  "node_modules"
  ".npm"
  ".npm-cache"
  
  # Ruby
  ".bundle"
  "vendor/bundle"
  
  # Java/Gradle/Maven
  ".gradle"
  "target"
  
  # IDE specific
  ".idea"
  ".vscode/extensions"
  ".vs"
  
  # OS specific (uncomment if needed - can slow down scan)
  # ".DS_Store"
  # ".Spotlight-V100"
  # ".Trashes"
  # "Thumbs.db"
  # "desktop.ini"
)

#===============================================================================
# Functions
#===============================================================================

# Display help message
show_help() {
  cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Backup Organizer

USAGE:
  ${SCRIPT_NAME} [OPTIONS] FOLDER [FOLDER...]

OPTIONS:
  --apply              Actually perform operations (default: dry-run)
  --dedupe=MODE        Deduplication mode: off|report|interactive (default: off)
  --out=DIR            Output directory for archives (default: ./archives)
  --skip-size-calc     Skip initial/final size calculations (faster)
  --clean-only         Only clean junk, skip deduplication and archiving
  --verbose            Enable verbose output
  --help               Show this help message

DEDUPLICATION MODES:
  off                  No deduplication (default)
  report               Generate a report of duplicate files (no deletion)
  interactive          Interactively choose which duplicates to delete (requires --apply)

EXAMPLES:
  # Preview what would be cleaned (dry-run):
  ${SCRIPT_NAME} --out=./archives backup1 backup2

  # Actually clean and create archives:
  ${SCRIPT_NAME} --apply --out=./archives backup1 backup2

  # Clean + generate duplicate report:
  ${SCRIPT_NAME} --apply --dedupe=report backup1 backup2

  # Quick clean only (no archiving):
  ${SCRIPT_NAME} --apply --clean-only --skip-size-calc backup1 backup2

CLEANED PATTERNS:
  - Python: venv/, __pycache__/, .pytest_cache/, *.egg-info/, dist/, build/
  - Node.js: node_modules/, .npm/, .npm-cache/
  - Ruby: .bundle/, vendor/bundle/
  - Java: .gradle/, target/
  - IDE: .idea/, .vscode/extensions/, .vs/

EOF
}

# Logging function with timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Verbose logging (only shown if --verbose is enabled)
log_verbose() {
  if [[ "$VERBOSE" == "yes" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" | tee -a "$LOG_FILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" >> "$LOG_FILE"
  fi
}

# Error logging
log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# Check if required command exists
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Missing required command: $1"
    log_error "Please install $1 and try again."
    exit 1
  fi
}

# Get human-readable size of a file or directory
human_size() {
  local target="$1"
  if [[ -e "$target" ]]; then
    du -sh "$target" 2>/dev/null | awk '{print $1}'
  else
    echo "N/A"
  fi
}

# Progress indicator for long operations
show_progress() {
  local current=$1
  local total=$2
  local operation=$3
  local percent=$((current * 100 / total))
  printf "\r  Progress: %d/%d (%d%%) %s" "$current" "$total" "$percent" "$operation"
}

#===============================================================================
# Core Operations
#===============================================================================

# Remove junk directories from a given folder
remove_junk() {
  local root="$1"
  local folder_name
  folder_name="$(basename "$root")"

  log "Scanning for junk in: $folder_name"
  log_verbose "Full path: $root"

  # Build find command dynamically
  local find_expr="find \"$root\" \\("
  local first=true
  for pattern in "${REMOVE_DIRS[@]}"; do
    if [[ "$first" == "true" ]]; then
      find_expr="$find_expr -name \"$pattern\""
      first=false
    else
      find_expr="$find_expr -o -name \"$pattern\""
    fi
  done
  find_expr="$find_expr \\) -print"

  log_verbose "Executing: $find_expr"

  # Find matching items
  local matches
  matches=$(eval "$find_expr" 2>/dev/null || true)

  if [[ -z "${matches// }" ]]; then
    log "  ✓ No junk found in $folder_name"
    return 0
  fi

  # Count matches
  local count
  count=$(echo "$matches" | wc -l | tr -d ' ')
  log "  Found $count junk items in $folder_name"

  # Show sample of items (first 20)
  log_verbose "Sample of items to be removed:"
  echo "$matches" | head -n 20 | while read -r item; do
    log_verbose "    - $(basename "$item")"
  done

  if [[ "$APPLY" == "yes" ]]; then
    log "  Deleting $count junk items..."
    
    # Build delete command
    local delete_expr="find \"$root\" \\("
    first=true
    for pattern in "${REMOVE_DIRS[@]}"; do
      if [[ "$first" == "true" ]]; then
        delete_expr="$delete_expr -name \"$pattern\""
        first=false
      else
        delete_expr="$delete_expr -o -name \"$pattern\""
      fi
    done
    delete_expr="$delete_expr \\) -exec rm -rf {} + 2>/dev/null || true"
    
    log_verbose "Executing: $delete_expr"
    eval "$delete_expr" >>"$LOG_FILE" 2>&1 || true
    log "  ✓ Deletion complete for $folder_name"
  else
    log "  [DRY-RUN] Would delete $count items. Use --apply to actually delete."
  fi
}

# Deduplicate across all folders
dedupe_all() {
  log "Starting deduplication (mode: $DEDUPE)"

  if [[ "$DEDUPE" == "report" ]]; then
    log "Generating duplicate report using content-based comparison..."
    log "This may take several minutes depending on data size."
    log ""
    
    # Run jdupes with progress indicator
    log "Running: jdupes -r ${FOLDERS[*]}"
    jdupes -r "${FOLDERS[@]}" 2>&1 | tee -a "$LOG_FILE"
    
    log ""
    log "✓ Duplicate report generated and saved to: $LOG_FILE"
    log "  Review the log file to see all duplicate groups."
    
  elif [[ "$DEDUPE" == "interactive" ]]; then
    log "Starting interactive deduplication..."
    log "You will be prompted to choose which duplicates to delete."
    log "TIP: Keep files from the newest/most important backup, delete from others."
    log ""
    
    if [[ "$APPLY" != "yes" ]]; then
      log_error "Interactive dedupe requires --apply flag"
      exit 1
    fi
    
    # Interactive mode - let user choose which duplicates to delete
    jdupes -rd "${FOLDERS[@]}" 2>&1 | tee -a "$LOG_FILE"
    
    log ""
    log "✓ Interactive deduplication completed"
    
  else
    log "Deduplication disabled (use --dedupe=report or --dedupe=interactive)"
  fi
}

# Create compressed archive of a folder
archive_folder() {
  local folder="$1"
  local base
  base="$(basename "$folder")"
  local stamp
  stamp="$(date +%Y%m%d_%H%M%S)"
  local out="$OUT_DIR/${base}_${stamp}.tar.gz"

  log "Preparing to archive: $base"
  log_verbose "Source: $folder"
  log_verbose "Destination: $out"

  # Build tar exclude patterns
  local tar_excludes=()
  for pattern in "${REMOVE_DIRS[@]}"; do
    tar_excludes+=( "--exclude=$pattern" )
  done
  # Exclude git metadata by default
  tar_excludes+=( "--exclude=.git" )
  tar_excludes+=( "--exclude=.gitignore" )

  if [[ "$APPLY" == "yes" ]]; then
    log "  Creating archive (this may take several minutes)..."
    log_verbose "  Command: tar -czf \"$out\" ${tar_excludes[*]} -C \"$(dirname "$folder")\" \"$base\""
    
    if tar -czf "$out" "${tar_excludes[@]}" -C "$(dirname "$folder")" "$base" >>"$LOG_FILE" 2>&1; then
      local archive_size
      archive_size="$(human_size "$out")"
      log "  ✓ Archive created: $(basename "$out") ($archive_size)"
    else
      log_error "  ✗ Failed to create archive for $base"
      return 1
    fi
  else
    log "  [DRY-RUN] Would create: $(basename "$out")"
    log "  Use --apply to actually create archives"
  fi
}

#===============================================================================
# Main Execution
#===============================================================================

# Parse command-line arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      show_help
      exit 0
      ;;
    --apply) 
      APPLY="yes"
      shift || true
      ;;
    --dedupe=*) 
      DEDUPE="${arg#*=}"
      shift || true
      ;;
    --out=*) 
      OUT_DIR="${arg#*=}"
      shift || true
      ;;
    --skip-size-calc) 
      SKIP_SIZE="yes"
      shift || true
      ;;
    --clean-only) 
      CLEAN_ONLY="yes"
      shift || true
      ;;
    --verbose|-v)
      VERBOSE="yes"
      shift || true
      ;;
    --) 
      shift
      break
      ;;
    -*) 
      echo "ERROR: Unknown option: $arg"
      echo "Run '$SCRIPT_NAME --help' for usage information."
      exit 1
      ;;
    *) 
      break
      ;;
  esac
done

# Validate arguments
if [[ $# -lt 1 ]]; then
  echo "ERROR: Please provide one or more folders to process."
  echo ""
  show_help
  exit 1
fi

if [[ "$DEDUPE" != "off" && "$DEDUPE" != "report" && "$DEDUPE" != "interactive" ]]; then
  echo "ERROR: --dedupe must be one of: off, report, interactive"
  echo "Current value: $DEDUPE"
  exit 1
fi

# Interactive dedupe requires --apply
if [[ "$DEDUPE" == "interactive" && "$APPLY" != "yes" ]]; then
  echo "ERROR: Interactive deduplication requires --apply flag"
  echo "This mode will delete files, so explicit confirmation is required."
  exit 1
fi

# Create output directory and log file
mkdir -p "$OUT_DIR"
readonly LOG_FILE="$OUT_DIR/backup_organizer_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"

# Store folder arguments
FOLDERS=("$@")

# Check required commands
need_cmd find
need_cmd du
need_cmd tar
need_cmd stat
need_cmd awk

# Check for jdupes if deduplication is enabled
if [[ "$DEDUPE" != "off" ]]; then
  if ! command -v jdupes >/dev/null 2>&1; then
    log_error "jdupes not found. Deduplication requires jdupes to be installed."
    log ""
    log "Installation instructions:"
    log "  macOS:          brew install jdupes"
    log "  Ubuntu/Debian:  sudo apt-get install jdupes"
    log "  Fedora/RHEL:    sudo dnf install jdupes"
    log "  Arch Linux:     sudo pacman -S jdupes"
    exit 1
  fi
fi

# Log script start
log "=========================================="
log "${SCRIPT_NAME} v${SCRIPT_VERSION}"
log "=========================================="
log "Mode:        $([ "$APPLY" == "yes" ] && echo "APPLY (will make changes)" || echo "DRY-RUN (preview only)")"
log "Dedupe:      $DEDUPE"
log "Output dir:  $OUT_DIR"
log "Skip sizes:  $SKIP_SIZE"
log "Clean only:  $CLEAN_ONLY"
log "Verbose:     $VERBOSE"
log "Folders:     ${#FOLDERS[@]}"
for f in "${FOLDERS[@]}"; do
  log "  - $f"
done
log ""

# Validate input folders
log "Validating input folders..."
for f in "${FOLDERS[@]}"; do
  if [[ ! -d "$f" ]]; then
    log_error "Not a directory: $f"
    exit 1
  fi
  if [[ ! -r "$f" ]]; then
    log_error "Directory not readable: $f"
    exit 1
  fi
  log_verbose "  ✓ Valid: $f"
done
log "✓ All folders validated successfully"
log ""

# Calculate initial sizes
if [[ "$SKIP_SIZE" == "no" ]]; then
  log "Calculating initial sizes..."
  for f in "${FOLDERS[@]}"; do
    local size
    size="$(human_size "$f")"
    log "  $(printf '%-10s' "$size") $(basename "$f")"
  done
  log ""
else
  log "Initial size calculation skipped (--skip-size-calc)"
  log ""
fi

# Phase 1: Clean junk directories
log "=========================================="
log "PHASE 1: Cleaning Junk Directories"
log "=========================================="
log "Patterns to remove: ${#REMOVE_DIRS[@]} types"
log_verbose "Full pattern list:"
for pattern in "${REMOVE_DIRS[@]}"; do
  log_verbose "  - $pattern"
done
log ""

folder_num=0
for f in "${FOLDERS[@]}"; do
  folder_num=$((folder_num + 1))
  log "[$folder_num/${#FOLDERS[@]}] Processing: $(basename "$f")"
  remove_junk "$f"
  log ""
done
log "✓ Phase 1 complete: Junk cleanup finished"
log ""

# Phase 2: Optional deduplication
if [[ "$CLEAN_ONLY" != "yes" ]]; then
  log "=========================================="
  log "PHASE 2: Deduplication"
  log "=========================================="
  if [[ "$DEDUPE" != "off" ]]; then
    dedupe_all
  else
    log "Deduplication disabled"
    log "Use --dedupe=report or --dedupe=interactive to enable"
  fi
  log ""
  log "✓ Phase 2 complete"
  log ""

  # Phase 3: Create archives
  log "=========================================="
  log "PHASE 3: Creating Archives"
  log "=========================================="
  folder_num=0
  for f in "${FOLDERS[@]}"; do
    folder_num=$((folder_num + 1))
    log "[$folder_num/${#FOLDERS[@]}] Archiving: $(basename "$f")"
    archive_folder "$f"
    log ""
  done
  log "✓ Phase 3 complete: All archives created"
  log ""
else
  log "Clean-only mode: Skipping deduplication and archiving phases"
  log ""
fi

# Calculate final sizes
if [[ "$SKIP_SIZE" == "no" ]]; then
  log "=========================================="
  log "Final Sizes"
  log "=========================================="
  for f in "${FOLDERS[@]}"; do
    local size
    size="$(human_size "$f")"
    log "  $(printf '%-10s' "$size") $(basename "$f")"
  done
  log ""
fi

# Summary
log "=========================================="
log "SUMMARY"
log "=========================================="
log "✓ All operations completed successfully"
log "Log file: $LOG_FILE"
if [[ "$APPLY" != "yes" ]]; then
  log ""
  log "NOTE: This was a DRY-RUN. No changes were made."
  log "To actually perform these operations, run with --apply flag"
fi
log "=========================================="

exit 0
