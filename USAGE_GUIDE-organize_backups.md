# Backup Organization Script - Usage Guide

## Overview
This script (`organize_backups.sh`) efficiently cleans, deduplicates, and archives backup folders to make them smaller and faster to copy.

## What It Does

### 1. **Removes Junk Directories** 🧹
Automatically finds and removes common bloat from your backups:
- **Python virtual environments**: `venv`, `.venv`, `env`
- **Python cache directories**: `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.tox`
- **Git metadata**: `.git` (excluded from archives)

### 2. **Deduplicates Files** 🔍
Identifies and optionally removes duplicate files across all backup folders:
- **Content-based detection**: Uses `jdupes` to find true duplicates (not just by name)
- **Three modes**:
  - `off`: Skip deduplication
  - `report`: Generate a report of duplicates (no deletion)
  - `interactive`: Interactively choose which duplicates to delete

### 3. **Creates Compressed Archives** 📦
Archives each cleaned folder as a `.tar.gz` file:
- Significantly reduces size
- Makes copying between drives/systems much faster
- Each archive is timestamped for easy identification

## Installation Requirements

### Step 1: Make Script Executable
```bash
chmod +x organize_backups.sh
```

### Step 2: Install jdupes (Required for Deduplication)

#### macOS
```bash
brew install jdupes
```

#### Ubuntu/Debian
```bash
sudo apt-get install jdupes
```

#### Windows WSL
```bash
sudo apt-get install jdupes
```

**Note**: jdupes is only required if you use `--dedupe=report` or `--dedupe=interactive`. For basic cleanup and archiving, it's optional.

## Usage Examples

### Quick Start - Dry Run (Safe, No Changes)
```bash
# Preview what would be cleaned
./organize_backups.sh backup1 backup2 backup3 backup4
```

### Basic Usage - Clean and Archive
```bash
# Remove junk and create archives
./organize_backups.sh --apply --out=./archives backup1 backup2 backup3 backup4
```

### With Duplicate Detection Report
```bash
# Clean, show duplicates (no deletion), then archive
./organize_backups.sh --apply --dedupe=report --out=./archives backup1 backup2 backup3 backup4
```

### Full Cleanup with Interactive Deduplication
```bash
# Clean, interactively remove duplicates, then archive
./organize_backups.sh --apply --dedupe=interactive --out=./archives backup1 backup2 backup3 backup4
```

### Custom Output Directory
```bash
# Save archives to a specific location
./organize_backups.sh --apply --out=/Volumes/ExternalDrive/BackupArchives backup1 backup2 backup3 backup4
```

## Command-Line Options

| Option | Values | Description |
|--------|--------|-------------|
| `--apply` | - | **Required** to actually make changes (delete/archive). Without it, runs in dry-run mode |
| `--dedupe` | `off` (default)<br>`report`<br>`interactive` | Deduplication strategy across all folders |
| `--out` | directory path | Where to save `.tar.gz` archives (default: `./archives`) |

## How It Works - Step by Step

1. **Validation**: Checks all folders exist and required tools are installed
2. **Initial Size Report**: Shows current size of each backup folder
3. **Junk Removal**: 
   - Scans each folder for unwanted directories
   - Lists what was found (up to 50 examples)
   - Deletes them if `--apply` is used
4. **Deduplication** (if enabled):
   - Compares files across ALL backup folders
   - Finds exact duplicates by content (not just filename)
   - Shows report or prompts for deletion
5. **Archiving**:
   - Creates compressed `.tar.gz` for each folder
   - Names format: `foldername_YYYYMMDD_HHMMSS.tar.gz`
   - Shows final archive size
6. **Final Report**: Shows cleaned folder sizes and log location

## Log Files

Every run creates a detailed log:
- **Location**: `./archives/backup_pack_YYYYMMDD_HHMMSS.log`
- **Contents**: 
  - Timestamps for each operation
  - Lists of removed directories
  - Duplicate reports (if enabled)
  - Archive creation details
  - Any errors encountered

## Safety Features

✅ **Dry Run by Default**: Without `--apply`, shows what *would* happen  
✅ **Detailed Logging**: Every operation is logged with timestamps  
✅ **Size Reports**: See before/after sizes  
✅ **Error Handling**: Stops on errors (`set -euo pipefail`)  
✅ **Preview Mode**: Shows up to 50 examples of what will be removed  

## Recommended Workflow

### First Time Use
```bash
# 1. Dry run to see what would be cleaned
./organize_backups.sh backup1 backup2 backup3 backup4

# 2. Review the output

# 3. Run with --apply but just generate duplicate report first
./organize_backups.sh --apply --dedupe=report --out=./archives backup1 backup2 backup3 backup4

# 4. Review the duplicate report in the log file

# 5. If satisfied, do full cleanup with interactive dedupe
./organize_backups.sh --apply --dedupe=interactive --out=./archives backup1 backup2 backup3 backup4
```

### Regular Maintenance
```bash
# For new backups, just clean and archive
./organize_backups.sh --apply --out=./archives new_backup_folder
```

## Expected Space Savings

Based on typical backup scenarios:

| Content Type | Typical Savings |
|--------------|-----------------|
| Python virtual environments | 100-500 MB per venv |
| `__pycache__` directories | 10-50 MB per project |
| `.git` directories | 50-200 MB per repo |
| Duplicate files | 20-60% reduction |
| Compression (.tar.gz) | 40-70% size reduction |

**Example**: A 10 GB backup folder can often be reduced to 1-3 GB after cleaning and archiving!

## Customization

### Add More Directories to Remove

Edit the `REMOVE_DIRS` array in the script (around line 93):

```bash
REMOVE_DIRS=(
  "venv"
  ".venv"
  "env"
  "__pycache__"
  ".pytest_cache"
  ".mypy_cache"
  ".ruff_cache"
  ".tox"
  "node_modules"      # Add Node.js modules
  ".npm"              # Add npm cache
  ".terraform"        # Add Terraform plugin cache
  "target"            # Add Rust/Java build dirs
  "build"             # Add generic build dirs
  "dist"              # Add distribution dirs
  ".gradle"           # Add Gradle cache
  ".mvn"              # Add Maven cache
)
```

**Common additions based on your environment**:
- **Node.js**: `node_modules`, `.npm`, `.yarn`
- **Terraform**: `.terraform`, `.terraform.lock.hcl`
- **Java/Maven**: `target`, `.m2`, `.mvn`
- **Rust/Cargo**: `target`
- **Go**: `vendor`
- **Ruby**: `vendor/bundle`, `.bundle`

### Exclude Additional Patterns from Archives

Edit the `tar_excludes` array in the `archive_folder` function (around line 173):

```bash
tar_excludes+=( "--exclude=.git" )
tar_excludes+=( "--exclude=.DS_Store" )      # macOS metadata
tar_excludes+=( "--exclude=Thumbs.db" )      # Windows metadata
tar_excludes+=( "--exclude=*.log" )          # Log files
```

## Troubleshooting

### "jdupes not found"
```bash
# macOS
brew install jdupes

# Ubuntu/Debian
sudo apt-get install jdupes
```

### "Not a directory" error
Check your folder paths are correct and exist.

### Archives too large
Consider adding more exclusions or running interactive dedupe.

### Script hangs during dedupe
Large backups with millions of files can take time. Use `report` mode first to gauge complexity.

## Tips for Best Results

1. **Start Small**: Test on one backup folder first
2. **Review Logs**: Always check the log file after running
3. **Keep Originals**: Don't delete original backups until you verify archives
4. **Use External Drive**: Save archives to external storage
5. **Regular Cleanup**: Run this before each new backup to prevent bloat accumulation
6. **Version Control**: Use timestamps in folder names (e.g., `backup_2026-01-07`)

## Speed Improvements

**Before**: Copying 4 backup folders (40 GB) = 2-3 hours  
**After**: Copying 4 archives (5-10 GB) = 15-30 minutes  

Plus faster file system operations since you're copying 4 files instead of millions!

---

## Quick Reference Card

```bash
# Dry run (preview only)
./organize_backups.sh folder1 folder2

# Clean and archive
./organize_backups.sh --apply folder1 folder2

# Full cleanup with dedupe report
./organize_backups.sh --apply --dedupe=report folder1 folder2

# Interactive dedupe
./organize_backups.sh --apply --dedupe=interactive folder1 folder2
```

**Remember**: Always use `--apply` for actual changes!
