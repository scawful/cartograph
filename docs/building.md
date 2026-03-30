# Building Cartograph

## Prerequisites

- Python 3.12+
- macOS 14+ (for SwiftUI app)
- Xcode 15+ (for SwiftUI app)
- XcodeGen (`brew install xcodegen`)
- CMake 3.20+ (for ImGui companion)
- GLFW (`brew install glfw`)

## Python CLI

```bash
# Create virtual environment and install
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"

# Verify
.venv/bin/carto --help

# Run tests
.venv/bin/pytest tests/ -v

# Lint
.venv/bin/ruff check src/ tests/

# Format
.venv/bin/ruff format src/ tests/
```

Or use the Makefile:
```bash
make install   # creates venv + installs
make test      # pytest
make lint      # ruff check
make format    # ruff format
```

## SwiftUI App

```bash
cd gui/swift

# Generate Xcode project from project.yml
xcodegen generate

# Build from command line
xcodebuild -project Cartograph.xcodeproj -scheme Cartograph -configuration Debug build

# Or open in Xcode
open Cartograph.xcodeproj
```

Dependencies (resolved automatically by Xcode/SPM):
- [GRDB.swift](https://github.com/groue/GRDB.swift) 7.0+ — SQLite wrapper

## ImGui Companion

```bash
cd gui/imgui

# Configure and build
cmake -B build -S .
cmake --build build

# Run
./build/carto-canvas /path/to/project/.context/cartograph.sqlite3
```

Dependencies (fetched automatically by CMake):
- [ImGui](https://github.com/ocornut/imgui) docking branch — UI framework
- GLFW — windowing (system, via Homebrew)
- OpenGL — rendering (system)
- SQLite3 — database (system, built into macOS)

## Typical Workflow

```bash
# 1. Index a project
carto ingest ~/src/my-project

# 2. Generate a reading path
carto path generate --strategy complexity-ascending -p ~/src/my-project

# 3. Open the SwiftUI app and load the database
#    File > Open Project Index > ~/src/my-project/.context/cartograph.sqlite3

# 4. Or walk from the CLI
carto path walk -p ~/src/my-project

# 5. Or explore with the ImGui tool
./gui/imgui/build/carto-canvas ~/src/my-project/.context/cartograph.sqlite3
```
