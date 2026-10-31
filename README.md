# Automation Scripts

A collection of bash scripts for backup management, file deduplication, and system automation tasks.

## 📋 Overview

This repository contains production-ready automation scripts designed to streamline backup management, reduce redundant data, and improve efficiency in system administration tasks.

## 🛠️ Available Scripts

### 1. Backup Organization (`organize-backups.sh`)

Efficiently clean, deduplicate, and archive backup folders to make them smaller and faster to copy.

**Key Features:**

- Removes 24+ types of junk files (Python venvs, node_modules, build artifacts, IDE files)
- Content-based file deduplication with jdupes
- Creates compressed `.tar.gz` archives
- Dry-run mode by default (safe preview before making changes)
- Verbose mode for detailed progress tracking
- Cross-platform (macOS/Linux)
- Human-readable size reports

**Quick Start:**

```bash
# Preview what will be cleaned (dry-run)
./organize-backups.sh backup1 backup2

# Clean junk files only
./organize-backups.sh --apply --clean-only backup1 backup2

# Clean, deduplicate, and create archives
./organize-backups.sh --apply --dedupe=report --out=./archives backup1 backup2

# Verbose mode with progress indicators
./organize-backups.sh --verbose --apply --clean-only backup1

# Get help on all options
./organize-backups.sh --help
```

---

### 2. Folder Merging (`merge-folders.sh`)

Merge source folder into destination folder, copying only unique files while preserving all existing destination files.

**Key Features:**

- Safe merging (destination files are never overwritten)
- Automatic exclusion of common system files (.git, .DS_Store, Thumbs.db)
- Preview mode shows exactly what will be copied
- Progress indicators for large operations
- Cross-platform file size detection
- Preserves file permissions and timestamps

**Quick Start:**

```bash
# Preview merge (dry-run)
./merge-folders.sh /path/to/source /path/to/destination

# Execute merge
./merge-folders.sh /path/to/source /path/to/destination --apply

# Verbose mode
./merge-folders.sh /path/to/source /path/to/destination --apply --verbose
```

---

### 3. Duplicate File Removal (`remove-duplicates-by-priority.sh`)

Delete duplicate files based on folder priority, keeping files from highest-priority folders.

**Key Features:**

- Priority-based duplicate removal (keep files from preferred folders)
- Auto-detects folder priorities from jdupes report
- Custom priority specification with --priority flag
- Verbose mode shows detailed group-by-group decisions
- Progress tracking for large operations
- Safe default (dry-run mode)
- Handles missing files gracefully

**Quick Start:**

```bash
# Generate duplicate report
jdupes -r "$(pwd)/folder1" "$(pwd)/folder2" > duplicates.log

# Preview deletion (auto-detect priority)
./remove-duplicates-by-priority.sh duplicates.log

# Execute with custom priority (folder1 > folder2 > folder3)
./remove-duplicates-by-priority.sh duplicates.log --priority=folder1,folder2,folder3 --apply

# Verbose mode to see detailed decisions
./remove-duplicates-by-priority.sh duplicates.log --priority=folder1,folder2,folder3 --verbose
```

---

### 4. Empty Folder Removal (`remove-empty-folders.sh`)

Remove empty directories left behind after junk cleanup or duplicate file deletion.

**Key Features:**

- Bottom-up recursive removal (processes deepest folders first)
- Excludes version control directories (.git, .svn, etc.)
- Minimum depth protection prevents accidental root removal
- Hidden folder control (excluded by default, use --include-hidden)
- Real-time progress indicators during scan and removal
- Detailed logging with timestamps
- Verbose mode shows every folder processed
- Safe default (dry-run mode)
- Can be chained with other cleanup scripts

**Quick Start:**

```bash
# Preview what will be removed (dry-run)
./remove-empty-folders.sh /path/to/backup

# Actually remove empty folders
./remove-empty-folders.sh --apply /path/to/backup

# Remove from multiple locations
./remove-empty-folders.sh --apply backup1 backup2 backup3

# Only remove deeply nested empty folders (depth 2+)
./remove-empty-folders.sh --apply --min-depth=2 /path/to/backup

# Chain with cleanup script (recommended workflow)
./organize-backups.sh --apply --clean-only backup1 && \
./remove-empty-folders.sh --apply backup1
```

---

## 🚀 Getting Started

### Prerequisites

**For bash scripts:**

- bash (zsh compatible)
- Standard Unix tools: `find`, `du`, `tar`, `stat`
- `jdupes` (for deduplication features)
  - macOS: `brew install jdupes`
  - Linux: `apt install jdupes` or `yum install jdupes`

### Installation

1. Clone this repository:

```bash
git clone <repository-url>
cd automation_scripts
```

2. Make shell scripts executable:

```bash
chmod +x *.sh
```

3. Install jdupes (for deduplication):

```bash
# macOS
brew install jdupes

# Linux (Debian/Ubuntu)
sudo apt install jdupes

# Linux (RHEL/CentOS)
sudo yum install jdupes
```

## ✨ Version 2.1.0 Features (Latest)

**NEW: Two-Step Scan-Then-Apply Workflow**

- All scripts now support scanning first, then applying changes from saved reports
- **Report files** automatically saved to `archives/` directory
- **No re-scanning** needed - instant execution from saved reports
- Review and edit reports before applying changes

Scripts with this feature:

- `remove-empty-folders.sh` - Save/read empty folder lists with `--from-report`
- `organize-backups.sh` - Junk directories saved to report files
- `merge-folders.sh` - File copy lists saved to report files

**Example Workflow:**

```bash
# Step 1: Scan and save report
./remove-empty-folders.sh /path/to/backup
# Creates: archives/empty_folders_YYYYMMDD_HHMMSS.txt

# Step 2: Review report file, then apply
./remove-empty-folders.sh --apply --from-report=archives/empty_folders_*.txt
```

## ✨ Version 2.0.0 Features

All scripts have been enhanced with:

- **Comprehensive Help Documentation** - Use `--help` flag on any script
- **Enhanced Logging** - Timestamped logs with log levels (INFO, ERROR, VERBOSE)
- **Progress Indicators** - Real-time feedback for long-running operations
- **Cross-Platform Support** - Works on macOS and Linux
- **Verbose Mode** - Detailed output with `--verbose` flag
- **Production Ready** - Robust error handling and input validation
- **Generic & Reusable** - No vendor-specific code, ready for any use case

## 📚 Documentation

Each script includes comprehensive built-in help:

```bash
./organize-backups.sh --help
./merge-folders.sh --help
./remove-duplicates-by-priority.sh --help
./remove-empty-folders.sh --help
```

The `--help` flag provides:

- Complete usage examples
- All available options
- Detailed explanations of behavior
- Common use cases

## 🤝 Contributing

Contributions are welcome! When adding a new script:

1. Follow the existing code structure and naming conventions
2. Include comprehensive header documentation
3. Add `--help` flag with detailed usage examples
4. Implement dry-run mode by default for safety
5. Add progress indicators for long-running operations
6. Update this README with script description
7. Test thoroughly on both macOS and Linux (if applicable)

## 📝 License

MIT License - Feel free to use, modify, and distribute these scripts.

## ⚠️ Safety First

All scripts include multiple safety features:

- **Dry-run mode by default** - Preview changes before applying
- **Detailed logging** - Track what was changed and why
- **Error handling** - Graceful failure with helpful messages
- **Input validation** - Verify parameters before execution
- **Progress indicators** - Know what's happening during execution
- **Clear documentation** - Comprehensive `--help` and usage guides

**Best Practices:**

1. Always run with `--help` first to understand options
2. Use dry-run mode (default) to preview changes
3. Review the output before using `--apply`
4. Keep backups of important data
5. Test on a small dataset first

## 🔧 Troubleshooting

**jdupes not found:**

```bash
# macOS
brew install jdupes

# Linux
sudo apt install jdupes  # or yum install jdupes
```

**Permission denied:**

```bash
chmod +x *.sh
```

**Script-specific issues:**

- Use `--verbose` flag for detailed output
- Check the `--help` documentation for each script
- Run in dry-run mode first to preview changes

---

**Version:** 2.0.0  
**Last Updated:** January 8, 2026
