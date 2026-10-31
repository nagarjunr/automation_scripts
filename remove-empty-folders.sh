#!/usr/bin/env bash

#===============================================================================
# Empty Folder Remover Script
#===============================================================================
# Description:
#   Removes empty directories recursively from specified folders.
#   Useful for cleaning up after junk removal or duplicate file deletion.
#
# Features:
#   - Bottom-up recursive removal (deepest folders first)
#   - Dry-run mode for safe preview
#   - Excludes important directories (.git, .svn, etc.)
#   - Minimum depth protection
#   - Progress indicators
#   - Detailed logging and statistics
#
# Usage:
#   ./remove_empty_folders.sh [OPTIONS] FOLDER [FOLDER...]
#
# Options:
#   --apply              Actually delete empty folders (default is dry-run)
#   --min-depth=N        Only remove folders at depth N or deeper (default: 1)
#   --include-hidden     Also remove hidden empty folders (starting with .)
#   --verbose            Show verbose output
#   --help               Show this help message
#
# Examples:
#   # Preview what would be removed (dry-run):
#   ./remove_empty_folders.sh /path/to/backup
#
#   # Actually remove empty folders:
#   ./remove_empty_folders.sh --apply /path/to/backup
#
#   # Remove empty folders at depth 2 or deeper:
#   ./remove_empty_folders.sh --apply --min-depth=2 /path/to/backup
#
#   # Chain with other cleanup scripts:
#   ./organize_backups.sh --apply --clean-only backup1 && \
#   ./remove_empty_folders.sh --apply backup1
#
#===============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Default settings
APPLY="no"
MIN_DEPTH=1
INCLUDE_HIDDEN="no"
VERBOSE="no"
FROM_REPORT=""

# Create archives directory for logs and reports
ARCHIVE_DIR="archives"
mkdir -p "$ARCHIVE_DIR"

# Log and report files
LOG_FILE="$ARCHIVE_DIR/remove-empty-folders_$(date '+%Y%m%d_%H%M%S').log"
REPORT_FILE="$ARCHIVE_DIR/empty_folders_$(date '+%Y%m%d_%H%M%S').txt"

# Directories to always exclude (even if empty)
readonly EXCLUDE_DIRS=(
  ".git"
  ".svn"
  ".hg"
  ".bzr"
  "CVS"
)

#===============================================================================
# Functions
#===============================================================================

# Display help message
show_help() {
  cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Empty Folder Remover

DESCRIPTION:
  Removes empty directories recursively from specified folders.
  Useful for cleaning up after junk removal or duplicate file deletion.

USAGE:
  ${SCRIPT_NAME} [OPTIONS] FOLDER [FOLDER...]

OPTIONS:
  --apply              Actually delete empty folders (default: dry-run)
  --min-depth=N        Only remove folders at depth N or deeper (default: 1)
                       This prevents accidentally removing the target folder itself
  --include-hidden     Also remove hidden empty folders (starting with .)
  --from-report=FILE   Read empty folder list from previous report (skips scanning)
  --verbose            Show verbose output including each folder processed
  --help               Show this help message

EXCLUDED DIRECTORIES:
  The following directories are never removed (even if empty):
  - .git/              - Git repository metadata
  - .svn/              - Subversion metadata
  - .hg/               - Mercurial metadata
  - .bzr/              - Bazaar metadata
  - CVS/               - CVS metadata

EXAMPLES:
  # Preview what would be removed (dry-run):
  ${SCRIPT_NAME} /path/to/backup

  # Actually remove empty folders:
  ${SCRIPT_NAME} --apply /path/to/backup

  # Remove empty folders from multiple locations:
  ${SCRIPT_NAME} --apply backup1 backup2 backup3

  # Remove only deeply nested empty folders (depth 2+):
  ${SCRIPT_NAME} --apply --min-depth=2 /path/to/backup

  # Include hidden directories in removal:
  ${SCRIPT_NAME} --apply --include-hidden /path/to/backup

  # Two-step process (scan then delete):
  ${SCRIPT_NAME} /path/to/backup              # Creates empty_folders_YYYYMMDD_HHMMSS.txt
  ${SCRIPT_NAME} --apply --from-report=empty_folders_YYYYMMDD_HHMMSS.txt

  # Chain with cleanup script:
  ./organize_backups.sh --apply --clean-only backup && \\
  ${SCRIPT_NAME} --apply backup

SAFETY FEATURES:
  - Default mode is DRY-RUN (no changes made)
  - Minimum depth protection prevents removing root folder
  - Version control folders (.git, .svn, etc.) are always excluded
  - Bottom-up removal ensures deepest folders are processed first
  - Verbose mode shows exactly what will be removed

EOF
}

# Logging functions
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_verbose() {
  if [[ "$VERBOSE" == "yes" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" | tee -a "$LOG_FILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" >> "$LOG_FILE"
  fi
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# Check if directory should be excluded
should_exclude() {
  local dirpath="$1"
  local dirname
  dirname="$(basename "$dirpath")"
  
  for pattern in "${EXCLUDE_DIRS[@]}"; do
    if [[ "$dirname" == "$pattern" ]] || [[ "$dirpath" == *"/$pattern"/* ]] || [[ "$dirpath" == *"/$pattern" ]]; then
      return 0  # true - should exclude
    fi
  done
  
  # Exclude hidden directories unless --include-hidden is set
  if [[ "$INCLUDE_HIDDEN" == "no" ]] && [[ "$dirname" == .* ]]; then
    return 0  # true - should exclude
  fi
  
  return 1  # false - should not exclude
}

# Process empty folders from a report file
process_from_report() {
  local report_file="$1"
  
  if [[ ! -f "$report_file" ]]; then
    log_error "Report file not found: $report_file"
    return 1
  fi
  
  log "Reading empty folders from report: $report_file"
  
  # Read folders from report
  local empty_dirs=()
  while IFS= read -r dir; do
    # Skip empty lines and comments
    [[ -z "$dir" || "$dir" == \#* ]] && continue
    empty_dirs+=("$dir")
  done < "$report_file"
  
  local count=${#empty_dirs[@]}
  
  if [[ $count -eq 0 ]]; then
    log "  ✓ No folders found in report"
    return 0
  fi
  
  log "  Found $count folders in report"
  
  if [[ "$APPLY" != "yes" ]]; then
    log "  [DRY-RUN] Would remove $count folders. Use --apply to actually delete."
    # Show sample
    if [[ $count -le 20 ]]; then
      log "  Folders that would be removed:"
      for dir in "${empty_dirs[@]}"; do
        log "    - $dir"
      done
    else
      log "  Sample of folders (first 20 of $count):"
      for ((i=0; i<20; i++)); do
        log "    - ${empty_dirs[$i]}"
      done
      log "    ... and $((count - 20)) more"
    fi
    return 0
  fi
  
  log "  Removing $count empty folders..."
  local removed=0
  local failed=0
  local idx=0
  
  for dir in "${empty_dirs[@]}"; do
    ((idx++))
    
    # Show progress
    if (( idx % 10 == 0 )) || (( idx == count )); then
      printf "\r  Progress: %d/%d removed" "$removed" "$count"
    fi
    
    if [[ -d "$dir" ]]; then
      if rmdir "$dir" 2>/dev/null; then
        ((removed++))
        log_verbose "    ✓ Removed: $dir"
      else
        ((failed++))
        log_verbose "    ✗ Failed to remove: $dir"
      fi
    else
      ((failed++))
      log_verbose "    ✗ Not found: $dir"
    fi
  done
  
  # Clear progress line
  printf "\r%80s\r" " "
  
  log "  ✓ Removed $removed folders ($failed failed/not found/not empty)"
  return 0
}

# Check if directory is empty (no files, only empty subdirs or no subdirs)
is_truly_empty() {
  local dir="$1"
  
  # Check if there are any files (not directories)
  if find "$dir" -mindepth 1 -type f -print -quit 2>/dev/null | grep -q .; then
    return 1  # Not empty - has files
  fi
  
  # Check if there are any non-empty directories
  if find "$dir" -mindepth 1 -type d 2>/dev/null | while read -r subdir; do
    if ! is_truly_empty "$subdir"; then
      echo "not-empty"
      break
    fi
  done | grep -q "not-empty"; then
    return 1  # Not empty - has non-empty subdirs
  fi
  
  return 0  # Empty
}

# Find and process empty directories
process_empty_folders() {
  local root="$1"
  local folder_name
  folder_name="$(basename "$root")"
  
  if [[ ! -d "$root" ]]; then
    log_error "Not a directory: $root"
    return 1
  fi
  
  log "Scanning for empty folders in: $folder_name"
  log_verbose "Full path: $root"
  
  # Build find command for empty directories
  # Use -depth to process bottom-up (deepest first)
  local empty_dirs=()
  local count=0
  
  log_verbose "Finding empty directories (min-depth: $MIN_DEPTH)..."
  
  # Find all directories, process from deepest to shallowest
  local processed=0
  local last_update=0
  while IFS= read -r dir; do
    ((processed++))
    
    # Show progress every 100 directories or every second
    local current_time
    current_time=$(date +%s)
    if (( processed % 100 == 0 )) || (( current_time > last_update )); then
      printf "\r  Scanning... %d directories checked, %d empty found" "$processed" "$count"
      last_update=$current_time
    fi
    
    # Skip if excluded
    if should_exclude "$dir"; then
      log_verbose "  Skipping excluded: $dir"
      continue
    fi
    
    # Check if directory is truly empty
    if [[ -d "$dir" ]] && [[ ! -L "$dir" ]]; then
      # Count items in directory (excluding . and ..)
      local item_count
      item_count=$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
      
      if [[ "$item_count" -eq 0 ]]; then
        empty_dirs+=("$dir")
        ((count++))
        log_verbose "  Found empty: $dir"
      fi
    fi
  done < <(find "$root" -mindepth "$MIN_DEPTH" -type d -depth 2>/dev/null || true)
  
  # Clear progress line
  if [[ $processed -gt 0 ]]; then
    printf "\r%80s\r" " "
  fi
  
  if [[ $count -eq 0 ]]; then
    log "  ✓ No empty folders found in $folder_name"
    return 0
  fi
  
  log "  Found $count empty folders in $folder_name"
  
  # Show sample (first 20)
  if [[ $count -le 20 ]]; then
    log "  Empty folders:"
    for dir in "${empty_dirs[@]}"; do
      log "    - ${dir#$root/}"
    done
  else
    log "  Sample of empty folders (first 20 of $count):"
    for ((i=0; i<20; i++)); do
      log "    - ${empty_dirs[$i]#$root/}"
    done
    log "    ... and $((count - 20)) more"
  fi
  
  # Save empty folders to report file
  log "  Saving list to report file: $REPORT_FILE"
  for dir in "${empty_dirs[@]}"; do
    echo "$dir" >> "$REPORT_FILE"
  done
  
  if [[ "$APPLY" == "yes" ]]; then
    log "  Removing $count empty folders..."
    local removed=0
    local failed=0
    local idx=0
    
    for dir in "${empty_dirs[@]}"; do
      ((idx++))
      
      # Show progress
      if (( idx % 10 == 0 )) || (( idx == count )); then
        printf "\r  Progress: %d/%d removed" "$removed" "$count"
      fi
      
      if [[ -d "$dir" ]]; then
        if rmdir "$dir" 2>/dev/null; then
          ((removed++))
          log_verbose "    ✓ Removed: ${dir#$root/}"
        else
          ((failed++))
          log_verbose "    ✗ Failed to remove: ${dir#$root/}"
        fi
      fi
    done
    
    # Clear progress line
    printf "\r%80s\r" " "
    
    log "  ✓ Removed $removed folders ($failed failed/not empty)"
    return 0
  else
    log "  [DRY-RUN] Would remove $count empty folders. Use --apply to actually delete."
    return 0
  fi
}

#===============================================================================
# Main Script
#===============================================================================

# Parse command line arguments
FOLDERS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --apply)
      APPLY="yes"
      shift
      ;;
    --min-depth=*)
      MIN_DEPTH="${1#*=}"
      if ! [[ "$MIN_DEPTH" =~ ^[0-9]+$ ]]; then
        log_error "Invalid min-depth value: $MIN_DEPTH (must be a number)"
        exit 1
      fi
      shift
      ;;
    --include-hidden)
      INCLUDE_HIDDEN="yes"
      shift
      ;;
    --from-report=*)
      FROM_REPORT="${1#*=}"
      shift
      ;;
    --verbose)
      VERBOSE="yes"
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    -*)
      log_error "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
    *)
      FOLDERS+=("$1")
      shift
      ;;
  esac
done

# Validate arguments
if [[ -n "$FROM_REPORT" ]]; then
  # Reading from report - no folders needed
  if [[ ! -f "$FROM_REPORT" ]]; then
    log_error "Report file not found: $FROM_REPORT"
    exit 1
  fi
else
  # Scanning folders - validate they exist
  if [[ ${#FOLDERS[@]} -eq 0 ]]; then
    log_error "No folders specified"
    echo ""
    show_help
    exit 1
  fi
  
  # Validate all folders exist
  for folder in "${FOLDERS[@]}"; do
    if [[ ! -d "$folder" ]]; then
      log_error "Folder does not exist: $folder"
      exit 1
    fi
  done
fi

#===============================================================================
# Script Execution
#===============================================================================

log "╔══════════════════════════════════════════════════════════════════════════════╗"
log "║ Empty Folder Remover v${SCRIPT_VERSION}                                              ║"
log "Log file: $LOG_FILE"
log ""
log "╚══════════════════════════════════════════════════════════════════════════════╝"
log ""

# Show configuration
log "Configuration:"
log "  Mode: $(if [[ "$APPLY" == "yes" ]]; then echo "APPLY (will delete)"; else echo "DRY-RUN (preview only)"; fi)"
if [[ -n "$FROM_REPORT" ]]; then
  log "  Reading from report: $FROM_REPORT"
else
  log "  Min depth: $MIN_DEPTH"
  log "  Include hidden: $INCLUDE_HIDDEN"
  log "  Folders to process: ${#FOLDERS[@]}"
fi
log ""

if [[ "$APPLY" == "no" ]]; then
  log "⚠️  Running in DRY-RUN mode. No folders will be deleted."
  log "   Use --apply to actually remove empty folders."
  log ""
fi

# Process folders or read from report
if [[ -n "$FROM_REPORT" ]]; then
  # Process from report file
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  process_from_report "$FROM_REPORT"
  log ""
else
  # Process each folder
  total_found=0
  total_removed=0
  
  for folder in "${FOLDERS[@]}"; do
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    process_empty_folders "$folder"
    
    log ""
  done
fi

# Final summary
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "╔══════════════════════════════════════════════════════════════════════════════╗"
log "║ Processing Complete                                                          ║"
log "╚══════════════════════════════════════════════════════════════════════════════╝"
log ""

if [[ "$APPLY" == "yes" ]]; then
  log "✓ Empty folder removal complete"
  log ""
  log "Next steps:"
  log "  - Review the log above to verify removed folders"
  log "  - Run again to catch any newly empty parent folders"
else
  log "✓ Dry-run complete - no changes made"
  log ""
  if [[ -n "$FROM_REPORT" ]]; then
    log "Next steps:"
    log "  - Review the folders that would be removed above"
    log "  - Run with --apply --from-report=$FROM_REPORT to delete them"
  else
    log "Next steps:"
    log "  - Review the folders that would be removed above"
    log "  - Run with --apply to remove folders immediately"
    log "  - Or use --from-report=$(basename $REPORT_FILE) to delete from saved list later"
    log "  - Add --verbose to see detailed per-folder output"
  fi
fi

log ""
log "Complete log saved to: $LOG_FILE"
log ""
log "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"

exit 0
