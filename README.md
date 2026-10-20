# Squish

**Get disk space back from apps and files you aren't using, without deleting anything.**

Squish finds apps and files on your Mac that you haven't touched in a while and compresses them in place, using the same built-in compression Apple uses for its own apps. Nothing moves, nothing gets renamed, and nothing needs unzipping. Everything opens exactly as before, it just takes less room on disk.

```
node_modules folder     55 MB  →  26.6 MB on disk     (same files, same contents)
```

---

## Why

Most Macs are full of things that are rarely opened but still take up full space: apps you used once, old projects, logs, `node_modules` folders, exported data. Deleting them is risky and archiving them into a `.zip` makes them awkward to use.

macOS has a better option built in: **transparent compression**. A compressed file looks and works like a normal file to every app, but takes far less space. Apple turns it on for its own apps, but not for yours. Squish turns it on for the things you've stopped using.

## How it works

```
             ┌──────────────────────────────┐
  scan  ───► │ Not opened for N days?       │──no──► leave it alone
             │ Not running? Not excluded?   │
             └──────────────┬───────────────┘
                            │ yes
                            ▼
             ┌──────────────────────────────┐
compress ──► │ Compress in place (LZFSE)    │  file data is stored compressed;
             │ Check the result             │  macOS decompresses it on read,
             └──────────────┬───────────────┘  so apps never notice
                            ▼
                 same file, less disk space
```

1. **Scan.** Squish looks through the folders you choose and decides whether each app or file is *dormant*: not modified, opened or launched for a number of days you set. It uses file dates and Spotlight's "last opened" record. Apps that are running are never touched.
2. **Compress.** Dormant items are compressed in place with APFS compression (via [`afsctool`](https://github.com/RJVB/afsctool)). Each file is checked after it's written, and files that wouldn't shrink by at least 10% are left as they are.
3. **Use as normal.** When anything reads the file, macOS decompresses it on the fly. Code signatures, permissions, dates and Finder tags are kept.

Finder's **Get Info** shows both numbers: the file's real size, and the much smaller size *on disk*.

## Install

You need **macOS 13 or later** and **Xcode or the Command Line Tools** (`xcode-select --install`).

```bash
# 1. The compression engine
brew install afsctool

# 2. Get and build Squish
git clone https://github.com/yesterdayyousaidtmrw/squish.git
cd squish
swift build -c release

# 3. Put it on your PATH
sudo mkdir -p /usr/local/bin
sudo cp .build/release/squish /usr/local/bin/
```

Check that it works:

```bash
squish help
```

## Quick start

```bash
squish scan          # preview: what would be compressed, and why the rest is skipped
squish compress      # do it (asks before changing anything)
squish status ~/Documents   # how much of a folder is compressed
```

`scan` never changes anything. A typical result:

```
Settings: dormant ≥ 30d (apps 21d, devArtifacts 14d) · categories: apps, devArtifacts, code, text, uncompressedMedia · lzfse
Candidates: 13 apps (1.8 GB), 389 files (21.6 MB); sizes are before compression
  app    796.8 MB    38d idle  apps              /Applications/LibreOffice.app
  app    281.1 MB    25d idle  apps              /Applications/SomeGame.app
  file     2.1 MB    34d idle  code              ~/Downloads/saved-page/frame.html
  …
Skipped: recentlyUsed 5281 · excludedType 4759 · noMatchingCategory 3320 · running 20 · needsAdmin 7
  7 item(s) are owned by root; run with sudo to include them.
```

## What gets compressed

You choose by **category**. See them any time with `squish categories`.

| Category | What's in it | Unused for | On by default |
|---|---|---|---|
| `apps` | App bundles in your Applications folders | 21 days | ✓ |
| `devArtifacts` | Everything inside `node_modules`, `DerivedData`, `.build`, `Pods`, `target`, `__pycache__`, `.venv` | 14 days | ✓ |
| `code` | Source code and config files (`.swift`, `.js`, `.ts`, `.py`, `.json`, `.yaml`, …) | 30 days | ✓ |
| `text` | Plain text, logs, CSV, Markdown, subtitles | 30 days | ✓ |
| `uncompressedMedia` | TIFF, BMP, WAV, AIFF, PSD, SVG, EPS | 30 days | ✓ |
| `other` | Any other file | 30 days | |

Squish always skips files that are **already compressed** by their format, because compressing them again saves nothing: photos (JPEG, PNG, HEIC), video, music, `.zip`/`.dmg` archives, Office documents and fonts. It also skips `.git` folders, packages like Photos libraries, hard-linked files and anything you exclude.

## Settings

Settings live in one file:

```
~/Library/Application Support/Squish/config.json
```

Create it with the defaults, then edit it in any text editor:

```bash
squish config init   # write the defaults
squish config        # show the current settings
```

You only need to include what you change. Anything left out uses the default. A list or map you do include replaces its default completely: setting `excludedExtensions`, for example, drops every built-in entry you don't repeat.

```json
{
  "fileLocations": ["~/Documents", "~/Downloads", "~/Projects"],
  "dormantDays": 30,
  "dormantDaysByCategory": { "apps": 21, "devArtifacts": 14 },
  "algorithm": "lzfse",
  "excludedPaths": ["~/Documents/Work in progress"]
}
```

| Setting | What it does | Default |
|---|---|---|
| `appLocations` | Where to look for apps (one subfolder deep, so `Utilities` is included) | `/Applications`, `~/Applications` |
| `fileLocations` | Folders to scan for files (all subfolders) | `~/Documents`, `~/Downloads`, `~/Developer` |
| `categories` | Which categories are on | all but `other` |
| `dormantDays` | Days an item must sit unused before it's compressed | `30` |
| `dormantDaysByCategory` | Per-category days that override `dormantDays` | apps `21`, devArtifacts `14` |
| `algorithm` | `lzfse` (balanced, Apple's choice), `lzvn` (fastest to open), `zlib` (smallest) | `lzfse` |
| `zlibLevel` | 1–9, only for `zlib` | `9` |
| `minSavingsPercent` | Leave a file alone unless it shrinks by at least this much | `10` |
| `minFileBytes` | Ignore files smaller than this | `1` |
| `excludedPaths` | Folders and files never to touch | none |
| `excludedExtensions` | File types never to touch | already-compressed formats |

**Which algorithm?** Keep `lzfse` unless you have a reason not to. `zlib` saves a little more space but opens files more slowly, so it suits archives you almost never open.

## Commands

| Command | What it does |
|---|---|
| `squish scan` | Preview only. Lists what would be compressed and counts why the rest was skipped. Add `--all` to list every item. |
| `squish compress` | Compresses everything `scan` found. Asks first; add `--yes` to skip the question. |
| `squish status <path>` | Shows how many files are compressed and the size of the data versus space used on disk. |
| `squish restore <path>` | Decompresses everything under a path. |
| `squish categories` | Lists the categories, whether each is on, and its dormancy window. |
| `squish config` | Shows the settings. `config path` prints the file location; `config init` writes the defaults. |
| `squish schedule install` | Runs `compress --yes` every day at 3:00. |

Each run can override the settings without editing the file:

```bash
squish scan --in ~/Projects/old-client     # look at one folder only
squish compress --only apps --days 60      # only apps unused for 60+ days
squish compress --algorithm zlib           # smallest result for this run
```

## Run it automatically

```bash
squish schedule install            # daily at 3:00
squish schedule install --hour 13  # or pick an hour
squish schedule                    # is it installed?
squish schedule uninstall
```

This adds a standard macOS background job (a LaunchAgent) that runs as you, at low priority. Results are written to `~/Library/Logs/squish.log`. Install Squish to a fixed location first (as in [Install](#install)), because the job remembers the exact path.

Apps installed by the App Store and some installers belong to the system (root), so a scheduled run skips them. To include them, run once by hand with `sudo squish compress`.

If the log shows "Operation not permitted" for `~/Documents` or `~/Downloads`, macOS privacy protection is blocking the background job. Give `/usr/local/bin/squish` **Full Disk Access** in System Settings › Privacy & Security.

## Is it safe?

- **Nothing is deleted or moved.** Files keep their names, locations, dates, permissions, tags and code signatures.
- **Every compressed file is verified** before it replaces the original data.
- **It only touches what has gone unused**, and never an app that's running.
- **Always reversible:** `squish restore <path>` puts files back to normal using Apple's own `afscexpand` tool.
- **You see everything first:** `scan` is a dry run, and `compress` asks before it starts.

## Good to know

- **Will things open slower?** Usually you won't notice. LZFSE decompresses very fast, which is why Apple uses it for its own apps. `zlib` is noticeably slower on big files.
- **What if I edit a compressed file?** It works normally. When an app saves it, the file is usually written back uncompressed, and the next Squish run compresses it again once it's dormant.
- **Copying elsewhere:** files are decompressed when copied to cloud storage, another Mac, or a drive that isn't APFS, so they take their full size there.
- **External drives** must be formatted APFS or Mac OS Extended for compression to work.
- **App updates** replace the app's files, so an updated app is uncompressed until it's dormant again.
- **`restore` decompresses everything** under the path, including files Apple shipped already compressed.

## Uninstall

```bash
squish schedule uninstall                       # stop the daily job
sudo rm /usr/local/bin/squish                   # remove the tool
rm -r ~/Library/Application\ Support/Squish     # remove the settings
```

You don't need to restore files first. They keep working exactly as they are. To get them back to full size anyway, run `squish restore <path>` before uninstalling.

## For developers

```bash
swift test   # 21 tests, including real compression round-trips (needs afsctool)
```

- `Sources/SquishCore`: the engine. Config, scanning, dormancy, compression, scheduling.
- `Sources/squish`: the command-line front end.
