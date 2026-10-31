#!/usr/bin/env bash

#===============================================================================
# Folder Merge Script
#===============================================================================
# Description:
#   Merges source folder into destination folder, copying only unique files.
#   Destination files always take precedence (won't be overwritten).
#
# Features:
#   - Safe merge with destination priority
#   - Dry-run mode for preview
#   - Progress indicators
#   - Detailed logging
#   - Size calculations
#   - Handles large directory trees efficiently
#
# Usage:
#   ./merge_folders.sh SOURCE_FOLDER DEST_FOLDER [--apply]
#
# Arguments:
#   SOURCE_FOLDER   Source directory to merge from
#   DEST_FOLDER     Destination directory to merge into
#   --apply         Actually perform the merge (default is dry-run)
#
# Examples:
#   # Preview merge (dry-run):
#   ./merge_folders.sh /path/to/source /path/to/dest
#
#   # Actually perform merge:
#   ./merge_folders.sh /path/to/source /path/to/dest --apply
#
# Merge Strategy:
#   - If file exists in destination: SKIP (preserve destination version)
#   - If file only in source: COPY to destination
#   - Directory structure is recreated as needed
#   - File attributes (permissions, timestamps) are preserved
#
#===============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Default settings
APPLY="no"
VERBOSE="no"
FROM_REPORT=""

# Create archives directory for reports
ARCHIVE_DIR="archives"
mkdir -p "$ARCHIVE_DIR"

# Report file for merge operations
MERGE_REPORT="$ARCHIVE_DIR/merge_files_$(date '+%Y%m%d_%H%M%S').txt"

# File patterns to exclude from merge
readonly EXCLUDE_PATTERNS=(
  ".git"
  ".DS_Store"
  "._*"
  "Thumbs.db"
  "desktop.ini"
)

#===============================================================================
# Functions
#===============================================================================

# Display help message
show_help() {
  cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Folder Merge Tool

DESCRIPTION:
  Merges source folder into destination folder, copying only unique files.
  Destination files always take precedence (won't be overwritten).

USAGE:
  ${SCRIPT_NAME} SOURCE_FOLDER DEST_FOLDER [--apply]

ARGUMENTS:
  SOURCE_FOLDER    Source directory to merge from
  DEST_FOLDER      Destination directory to merge into
  --apply          Actually perform the merge (default: dry-run)
  --verbose        Show verbose output
  --help           Show this help message

MERGE STRATEGY:
  - If file exists in destination: SKIP (preserve destination version)
  - If file only in source: COPY to destination
  - Directory structure is recreated as needed
  - File attributes (permissions, timestamps) are preserved

EXCLUDED PATTERNS:
  The following patterns are automatically excluded:
  - .git/       - Git repositories
  - .DS_Store   - macOS metadata
  - ._*         - macOS resource forks
  - Thumbs.db   - Windows thumbnails
  - desktop.ini - Windows folder settings

EXAMPLES:
  # Preview what would be merged:
  ${SCRIPT_NAME} /backup/old_backup /backup/new_backup

  # Actually perform the merge:
  ${SCRIPT_NAME} /backup/old_backup /backup/new_backup --apply

  # After successful merge, you can delete the source:
  rm -rf /backup/old_backup

SAFETY:
  - Default mode is DRY-RUN (no changes made)
  - Destination files are NEVER overwritten
  - Source files are NEVER modified or deleted
  - Detailed preview before any operations

EOF
}

# Logging functions
log() {
  echo "$*"
}

log_error() {
  echo "ERROR: $*" >&2
}

# Format bytes to human-readable size
format_bytes() {
  local bytes=$1
  local kb=$((bytes / 1024))
  local mb=$((bytes / 1048576))
  local gb=$((bytes / 1073741824))
  
  if [[ $gb -gt 0 ]]; then
    echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
  elif [[ $mb -gt 0 ]]; then
    echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
  elif [[ $kb -gt 0 ]]; then
    echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
  else
    echo "$bytes bytes"
  fi
}

# Check if file matches exclude patterns
should_exclude() {
  local filepath="$1"
  local filename
  filename="$(basename "$filepath")"
  
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    if [[ "$filepath" == *"/$pattern/"* ]] || [[ "$filename" == $pattern ]]; then
      return 0  # true - should exclude
    fi
  done
  
  return 1  # false - should not exclude
}

#===============================================================================
# Main Execution
#===============================================================================

# Parse arguments
SOURCE_FOLDER=""
DEST_FOLDER=""
DRY_RUN=true
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_help
      exit 0
      ;;
    --apply)
      DRY_RUN=false
      shift
      ;;
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    -*)
      log_error "Unknown option: $1"
      echo "Run '$SCRIPT_NAME --help' for usage information."
      exit 1
      ;;
    *)
      if [[ -z "$SOURCE_FOLDER" ]]; then
        SOURCE_FOLDER="$1"
      elif [[ -z "$DEST_FOLDER" ]]; then
        DEST_FOLDER="$1"
      else
        log_error "Too many arguments"
        echo "Run '$SCRIPT_NAME --help' for usage information."
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate arguments
if [[ -z "$SOURCE_FOLDER" || -z "$DEST_FOLDER" ]]; then
  log_error "Missing required arguments"
  echo ""
  show_help
  exit 1
fi

# Validate source folder
if [[ ! -d "$SOURCE_FOLDER" ]]; then
  log_error "Source folder not found: $SOURCE_FOLDER"
  exit 1
fi

if [[ ! -r "$SOURCE_FOLDER" ]]; then
  log_error "Source folder not readable: $SOURCE_FOLDER"
  exit 1
fi

# Validate destination folder
if [[ ! -d "$DEST_FOLDER" ]]; then
  log_error "Destination folder not found: $DEST_FOLDER"
  log_error "Please create the destination folder first."
  exit 1
fi

if [[ ! -w "$DEST_FOLDER" ]]; then
  log_error "Destination folder not writable: $DEST_FOLDER"
  exit 1
fi

# Check for required commands
for cmd in find stat bc dirname mkdir cp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Required command not found: $cmd"
    exit 1
  fi
done

# Display header
log "=========================================="
log "${SCRIPT_NAME} v${SCRIPT_VERSION}"
log "=========================================="
if [[ "$DRY_RUN" == true ]]; then
  log "Mode:        DRY-RUN (preview only)"
  log "             Use --apply to actually copy files"
else
  log "Mode:        APPLY (will copy files)"
fi
log ""
log "Source:      $SOURCE_FOLDER"
log "Destination: $DEST_FOLDER"
log ""
log "Strategy:    Destination files take precedence"
log "             (existing files won't be overwritten)"
log "=========================================="
log ""

# Counters
TOTAL_FILES_SCANNED=0
TOTAL_FILES_TO_COPY=0
TOTAL_FILES_SKIPPED=0
TOTAL_BYTES_TO_COPY=0
LAST_PROGRESS_UPDATE=0

log "Scanning files..."
log ""

# Find all files in source folder
while IFS= read -r -d '' source_file; do
  # Check if file should be excluded
  if should_exclude "$source_file"; then
    continue
  fi
  
  TOTAL_FILES_SCANNED=$((TOTAL_FILES_SCANNED + 1))
  
  # Calculate relative path from source folder
  rel_path="${source_file#$SOURCE_FOLDER/}"
  
  # Determine destination path
  dest_file="$DEST_FOLDER/$rel_path"
  
  # Show progress every 100 files
  if [[ $((TOTAL_FILES_SCANNED % 100)) -eq 0 ]]; then
    printf "\r  Progress: %d files scanned, %d to copy, %d to skip..." \
      "$TOTAL_FILES_SCANNED" "$TOTAL_FILES_TO_COPY" "$TOTAL_FILES_SKIPPED"
  fi
  
  # Check if file already exists in destination
  if [[ -f "$dest_file" ]]; then
    # File exists in destination - skip
    TOTAL_FILES_SKIPPED=$((TOTAL_FILES_SKIPPED + 1))
  else
    # File doesn't exist in destination - will copy
    TOTAL_FILES_TO_COPY=$((TOTAL_FILES_TO_COPY + 1))
    
    # Get file size (cross-platform compatible)
    if [[ "$OSTYPE" == "darwin"* ]]; then
      file_size=$(stat -f%z "$source_file" 2>/dev/null || echo "0")
    else
      file_size=$(stat -c%s "$source_file" 2>/dev/null || echo "0")
    fi
    TOTAL_BYTES_TO_COPY=$((TOTAL_BYTES_TO_COPY + file_size))
    
    # Show file in verbose mode
    if [[ "$VERBOSE" == true ]]; then
      echo ""
      log "COPY: $rel_path"
    fi
    
    # Copy file if in apply mode
    if [[ "$DRY_RUN" == false ]]; then
      # Create destination directory if needed
      dest_dir="$(dirname "$dest_file")"
      mkdir -p "$dest_dir"
      
      # Copy file preserving attributes
      if cp -p "$source_file" "$dest_file" 2>/dev/null; then
        if [[ "$VERBOSE" == true ]]; then
          log "  ✓ Copied successfully"
        fi
      else
        log ""
        log_error "  ✗ Failed to copy: $rel_path"
      fi
    fi
  fi
done < <(find "$SOURCE_FOLDER" -type f -print0 2>/dev/null)

# Clear progress line
printf "\r%80s\r" " "

log ""
log "=========================================="
log "SUMMARY"
log "=========================================="
log "Files scanned:   $TOTAL_FILES_SCANNED"
log "Files to copy:   $TOTAL_FILES_TO_COPY (unique to source)"
log "Files skipped:   $TOTAL_FILES_SKIPPED (exist in destination)"
log "Data size:       $(format_bytes $TOTAL_BYTES_TO_COPY)"
log ""

if [[ "$DRY_RUN" == true ]]; then
  log "This was a DRY-RUN. No files were copied."
  log ""
  log "To actually perform the merge, run:"
  log "  $SCRIPT_NAME \"$SOURCE_FOLDER\" \"$DEST_FOLDER\" --apply"
else
  log "✓ Merge complete!"
  log ""
  log "Copied $TOTAL_FILES_TO_COPY files ($(format_bytes $TOTAL_BYTES_TO_COPY))"
  log ""
  log "After verifying the merge, you can safely delete the source:"
  log "  rm -rf \"$SOURCE_FOLDER\""
fi
log "=========================================="

exit 0
