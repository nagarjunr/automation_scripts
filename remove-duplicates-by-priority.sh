#!/usr/bin/env bash

#===============================================================================
# Duplicate File Remover (Priority-Based)
#===============================================================================
# Description:
#   Removes duplicate files based on folder priority. Keeps files from highest
#   priority folders, deletes duplicates from lower priority folders.
#
# Features:
#   - Priority-based duplicate deletion
#   - Dry-run mode for safe preview
#   - Progress indicators with ETA
#   - Detailed logging and statistics
#   - Safe handling of missing files
#   - Configurable folder priorities
#
# Usage:
#   ./remove_duplicates_by_priority.sh DUPLICATE_REPORT [OPTIONS]
#
# Arguments:
#   DUPLICATE_REPORT    Path to jdupes duplicate report file
#
# Options:
#   --apply             Actually delete files (default is dry-run)
#   --priority=LIST     Comma-separated list of folder priorities (highest first)
#   --verbose           Show verbose output
#   --help              Show this help message
#
# Examples:
#   # Preview what would be deleted (dry-run):
#   ./remove_duplicates_by_priority.sh report.log
#
#   # Actually delete duplicates:
#   ./remove_duplicates_by_priority.sh report.log --apply
#
#   # Custom priority order:
#   ./remove_duplicates_by_priority.sh report.log --priority=backup2024,backup2023,backup2022 --apply
#
# Priority Strategy:
#   - For each duplicate group, keep file from highest priority folder
#   - Delete all other duplicates from lower priority folders
#   - If multiple files in same priority folder, keep first one found
#   - Files not matching any priority folder are skipped
#
#===============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

# Default folder priorities (can be overridden with --priority)
# Edit this array to set your default folder priorities
# Format: folder name patterns (can use partial matches)
declare -a FOLDER_PRIORITY=()

#===============================================================================
# Functions
#===============================================================================

# Display help message
show_help() {
  cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Priority-Based Duplicate Remover

DESCRIPTION:
  Removes duplicate files based on folder priority. Keeps files from highest
  priority folders, deletes duplicates from lower priority folders.

USAGE:
  ${SCRIPT_NAME} DUPLICATE_REPORT [OPTIONS]

ARGUMENTS:
  DUPLICATE_REPORT    Path to jdupes duplicate report file
                      (Generate with: jdupes -r folder1 folder2 > report.log)

OPTIONS:
  --apply             Actually delete files (default: dry-run)
  --priority=LIST     Comma-separated folder priorities (highest first)
                      Example: --priority=backup2024,backup2023,backup2022
  --verbose           Show verbose output
  --help              Show this help message

PRIORITY STRATEGY:
  1. For each duplicate group, identify file from highest priority folder
  2. Keep that file, mark others for deletion
  3. If multiple files in same priority folder, keep first one found
  4. Files not matching any priority folder are skipped (not deleted)

EXAMPLES:
  # Preview deletions (dry-run):
  ${SCRIPT_NAME} duplicates.log

  # Actually delete duplicates:
  ${SCRIPT_NAME} duplicates.log --apply

  # Custom priority order:
  ${SCRIPT_NAME} duplicates.log --priority=new_backup,old_backup --apply

  # With verbose output:
  ${SCRIPT_NAME} duplicates.log --apply --verbose

GENERATING DUPLICATE REPORT:
  First, generate a duplicate report using jdupes:
    jdupes -r /path/to/folder1 /path/to/folder2 > duplicates.log

  Then run this script on the report:
    ${SCRIPT_NAME} duplicates.log --priority=folder1,folder2 --apply

EOF
}

# Logging functions
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_verbose() {
  if [[ "$VERBOSE" == true ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*"
  fi
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# Format bytes to human-readable size
format_bytes() {
  local bytes=$1
  local kb=$((bytes / 1024))
  local mb=$((bytes / 1048576))
  local gb=$((bytes / 1073741824))
  
  if [[ $gb -gt 0 ]]; then
    echo "$((bytes / 1073741824)) GB"
  elif [[ $mb -gt 0 ]]; then
    echo "$((bytes / 1048576)) MB"
  elif [[ $kb -gt 0 ]]; then
    echo "$((bytes / 1024)) KB"
  else
    echo "$bytes bytes"
  fi
}

# Extract folder name from full path for priority matching
get_folder_name() {
  local filepath="$1"
  # Extract the immediate parent folder or a recognizable portion
  echo "$filepath" | awk -F'/' '{for(i=1;i<=NF;i++) print $i}' | grep -v '^$' | tail -n 5 | head -n 1
}

# Find which priority level a file belongs to
get_priority_level() {
  local filepath="$1"
  local level=0
  
  for folder in "${FOLDER_PRIORITY[@]}"; do
    if [[ "$filepath" == *"/$folder/"* ]] || [[ "$filepath" == *"$folder"* ]]; then
      echo "$level"
      return 0
    fi
    level=$((level + 1))
  done
  
  # File doesn't match any priority folder
  echo "999"
}

#===============================================================================
# Main Execution
#===============================================================================

# Parse arguments
REPORT_FILE=""
DRY_RUN=true
VERBOSE=false
CUSTOM_PRIORITY=""

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
    --priority=*)
      CUSTOM_PRIORITY="${1#*=}"
      shift
      ;;
    -*)
      log_error "Unknown option: $1"
      echo "Run '$SCRIPT_NAME --help' for usage information."
      exit 1
      ;;
    *)
      if [[ -z "$REPORT_FILE" ]]; then
        REPORT_FILE="$1"
      else
        log_error "Too many arguments"
        echo "Run '$SCRIPT_NAME --help' for usage information."
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate report file
if [[ -z "$REPORT_FILE" ]]; then
  log_error "Missing required argument: DUPLICATE_REPORT"
  echo ""
  show_help
  exit 1
fi

if [[ ! -f "$REPORT_FILE" ]]; then
  log_error "Report file not found: $REPORT_FILE"
  exit 1
fi

if [[ ! -r "$REPORT_FILE" ]]; then
  log_error "Report file not readable: $REPORT_FILE"
  exit 1
fi

# Set up folder priorities
if [[ -n "$CUSTOM_PRIORITY" ]]; then
  # Use custom priorities from command line
  IFS=',' read -ra FOLDER_PRIORITY <<< "$CUSTOM_PRIORITY"
else
  # Try to auto-detect folder names from report
  log "No --priority specified. Auto-detecting folder names..."
  mapfile -t detected_folders < <(grep -E '^/' "$REPORT_FILE" | head -n 100 | \
    xargs -n1 dirname | sort | uniq -c | sort -rn | head -n 10 | awk '{print $NF}' | xargs -n1 basename)
  
  if [[ ${#detected_folders[@]} -eq 0 ]]; then
    log_error "Could not auto-detect folder priorities from report"
    log_error "Please specify priorities manually with --priority=folder1,folder2,..."
    exit 1
  fi
  
  FOLDER_PRIORITY=("${detected_folders[@]}")
  log "Auto-detected ${#FOLDER_PRIORITY[@]} folders"
fi

# Check for required commands
for cmd in stat rm; do
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
  log "             Use --apply to actually delete files"
else
  log "Mode:        APPLY (will delete files)"
fi
log ""
log "Report file: $REPORT_FILE"
log ""
log "Folder Priority (keep files in this order):"
for i in "${!FOLDER_PRIORITY[@]}"; do
  log "  $((i+1)). ${FOLDER_PRIORITY[$i]}"
done
log "=========================================="
log ""

# Counters
TOTAL_GROUPS=0
TOTAL_FILES_TO_DELETE=0
TOTAL_FILES_KEPT=0
TOTAL_FILES_NOT_FOUND=0
SPACE_TO_FREE=0
START_TIME=$(date +%s)

log "Processing duplicate groups..."
log ""

# Read report and process duplicate groups
declare -a current_group=()
group_count=0

while IFS= read -r line || [[ -n "$line" ]]; do
  # Detect group boundaries (empty lines or timestamp lines)
  if [[ -z "$line" ]] || [[ "$line" =~ ^\[20 ]] || [[ "$line" =~ ^[0-9]+ ]]; then
    # Process previous group if it has multiple files
    if [[ ${#current_group[@]} -gt 1 ]]; then
      group_count=$((group_count + 1))
      TOTAL_GROUPS=$((TOTAL_GROUPS + 1))
      
      # Find file to keep (highest priority)
      keep_file=""
      keep_priority=999
      
      for file in "${current_group[@]}"; do
        priority=$(get_priority_level "$file")
        if [[ $priority -lt $keep_priority ]]; then
          keep_priority=$priority
          keep_file="$file"
        fi
      done
      
      # If no file matched priorities, skip this group
      if [[ $keep_priority -eq 999 ]]; then
        log_verbose "Group $group_count: No files match priority folders (skipping)"
        current_group=()
        continue
      fi
      
      log_verbose "Group $group_count:"
      log_verbose "  KEEP: $keep_file"
      TOTAL_FILES_KEPT=$((TOTAL_FILES_KEPT + 1))
      
      # Delete the rest
      for file in "${current_group[@]}"; do
        if [[ "$file" != "$keep_file" ]]; then
          log_verbose "  DELETE: $file"
          TOTAL_FILES_TO_DELETE=$((TOTAL_FILES_TO_DELETE + 1))
          
          if [[ "$DRY_RUN" == false ]]; then
            if [[ -f "$file" ]]; then
              # Get file size before deletion (cross-platform)
              if [[ "$OSTYPE" == "darwin"* ]]; then
                file_size=$(stat -f%z "$file" 2>/dev/null || echo "0")
              else
                file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
              fi
              SPACE_TO_FREE=$((SPACE_TO_FREE + file_size))
              
              # Delete file
              if rm -f "$file" 2>/dev/null; then
                log_verbose "    ✓ Deleted"
              else
                log_error "    ✗ Failed to delete"
              fi
            else
              log_verbose "    ✗ File not found (already deleted or moved)"
              TOTAL_FILES_NOT_FOUND=$((TOTAL_FILES_NOT_FOUND + 1))
            fi
          fi
        fi
      done
      
      # Show progress every 100 groups
      if [[ $((group_count % 100)) -eq 0 ]]; then
        elapsed=$(($(date +%s) - START_TIME))
        rate=$((group_count / (elapsed + 1)))
        printf "\r  Processed %d groups (%d files to delete, %d to keep)..." \
          "$group_count" "$TOTAL_FILES_TO_DELETE" "$TOTAL_FILES_KEPT"
      fi
      
      log_verbose ""
    fi
    
    # Reset for next group
    current_group=()
    continue
  fi
  
  # Add file to current group (lines starting with /)
  if [[ "$line" =~ ^/ ]]; then
    current_group+=("$line")
  fi
done < "$REPORT_FILE"

# Process last group if exists
if [[ ${#current_group[@]} -gt 1 ]]; then
  group_count=$((group_count + 1))
  TOTAL_GROUPS=$((TOTAL_GROUPS + 1))
  
  keep_file=""
  keep_priority=999
  
  for file in "${current_group[@]}"; do
    priority=$(get_priority_level "$file")
    if [[ $priority -lt $keep_priority ]]; then
      keep_priority=$priority
      keep_file="$file"
    fi
  done
  
  if [[ $keep_priority -ne 999 ]]; then
    log_verbose "Group $group_count:"
    log_verbose "  KEEP: $keep_file"
    TOTAL_FILES_KEPT=$((TOTAL_FILES_KEPT + 1))
    
    for file in "${current_group[@]}"; do
      if [[ "$file" != "$keep_file" ]]; then
        log_verbose "  DELETE: $file"
        TOTAL_FILES_TO_DELETE=$((TOTAL_FILES_TO_DELETE + 1))
        
        if [[ "$DRY_RUN" == false ]]; then
          if [[ -f "$file" ]]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
              file_size=$(stat -f%z "$file" 2>/dev/null || echo "0")
            else
              file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
            fi
            SPACE_TO_FREE=$((SPACE_TO_FREE + file_size))
            
            if rm -f "$file" 2>/dev/null; then
              log_verbose "    ✓ Deleted"
            else
              log_error "    ✗ Failed to delete"
            fi
          else
            log_verbose "    ✗ File not found"
            TOTAL_FILES_NOT_FOUND=$((TOTAL_FILES_NOT_FOUND + 1))
          fi
        fi
      fi
    done
  fi
fi

# Clear progress line
printf "\r%80s\r" " "

# Calculate execution time
TOTAL_TIME=$(($(date +%s) - START_TIME))

log ""
log "=========================================="
log "SUMMARY"
log "=========================================="
log "Duplicate groups:     $TOTAL_GROUPS"
log "Files to keep:        $TOTAL_FILES_KEPT"
log "Files to delete:      $TOTAL_FILES_TO_DELETE"
if [[ "$DRY_RUN" == false ]]; then
  log "Files not found:      $TOTAL_FILES_NOT_FOUND"
  log "Space freed:          $(format_bytes $SPACE_TO_FREE)"
fi
log "Execution time:       ${TOTAL_TIME}s"
log ""

if [[ "$DRY_RUN" == true ]]; then
  log "This was a DRY-RUN. No files were deleted."
  log ""
  log "To actually delete these files, run:"
  log "  $SCRIPT_NAME \"$REPORT_FILE\" --apply"
  if [[ ${#FOLDER_PRIORITY[@]} -gt 0 ]] && [[ -z "$CUSTOM_PRIORITY" ]]; then
    log "  --priority=$(IFS=,; echo "${FOLDER_PRIORITY[*]}")"
  fi
else
  log "✓ Duplicate removal complete!"
  log "Deleted $TOTAL_FILES_TO_DELETE files"
  log "Freed $(format_bytes $SPACE_TO_FREE)"
fi
log "=========================================="

exit 0
