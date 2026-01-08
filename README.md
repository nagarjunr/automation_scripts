# Automation Scripts

A collection of bash and Python scripts for day-to-day productivity improvements and system automation tasks.

## 📋 Overview

This repository contains various automation scripts (bash, Python, and more) designed to streamline common workflows, reduce manual effort, and improve efficiency in daily development and system management tasks.

## 🛠️ Available Scripts

### 1. Backup Organization (`organize_backups.sh`)

Efficiently clean, deduplicate, and archive backup folders to make them smaller and faster to copy.

**Key Features:**
- Removes Python virtual environments and cache directories
- Content-based file deduplication across multiple backup folders
- Creates compressed `.tar.gz` archives
- Dry-run mode by default (safe preview before making changes)
- Detailed logging and before/after size reports

**Quick Start:**
```bash
# Dry run (preview only)
./organize_backups.sh backup1 backup2 backup3 backup4

# Clean and archive
./organize_backups.sh --apply --out=./archives backup1 backup2 backup3 backup4
```

📖 **Full Documentation:** [USAGE_GUIDE-organize_backups.md](USAGE_GUIDE-organize_backups.md)

---

## 🚀 Getting Started

### Prerequisites

**For bash scripts:**
- bash (zsh compatible)
- Standard Unix tools: `find`, `du`, `tar`

**For Python scripts:**
- Python 3.7+ (check individual script requirements)
- pip for installing dependencies

Some scripts may have additional requirements listed in their individual usage guides.

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

3. Install Python dependencies (if using Python scripts):
```bash
pip install -r requirements.txt  # if requirements file exists
# or check individual script usage guides for dependencies
```

4. Review the usage guide for the script you want to use

## 📚 Documentation Structure

Each script has its own detailed usage guide:
- `USAGE_GUIDE-<script-name>.md` - Comprehensive documentation for each script

## 🤝 Contributing

Feel free to add your own automation scripts to this repository. When adding a new script:

1. Create the script with a descriptive name
2. Add a corresponding `USAGE_GUIDE-<script-name>.md` file
3. Update this README with a brief description and link to the usage guide
4. Include examples and prerequisites

## 📝 License

These scripts are provided as-is for personal and professional use.

## ⚠️ Safety First

Most scripts include:
- Dry-run mode by default (preview before making changes)
- Detailed logging
- Error handling and validation
- Clear documentation of what will be modified

Always review a script's usage guide and run in dry-run mode first before applying changes.

---

**Last Updated:** January 2026
