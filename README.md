# Squish

[![CI](https://github.com/yesterdayyousaidtmrw/squish/actions/workflows/ci.yml/badge.svg)](https://github.com/yesterdayyousaidtmrw/squish/actions/workflows/ci.yml)

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
  scan  ───► │ Unused for N days?           │──no──► leave it alone
             │ Not running, open, excluded? │
             │ Frees at least one block?    │
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

1. **Scan.** Squish looks through the folders you choose and decides whether each app or file is *dormant*: not modified, opened or launched for a number of days you set. It uses file dates and Spotlight's "last opened" record, and judges code projects as a whole (see [How "unused" is decided](#how-unused-is-decided)). For each dormant file it compresses a 64 KB sample in memory, so it knows how much the file will really shrink and can tell you the saving before anything changes. Running apps and files that one of your programs has open are never touched.
2. **Compress.** Dormant items are compressed in place with APFS compression (via [`afsctool`](https://github.com/RJVB/afsctool)). Each file is checked after it's written, and the space actually freed is measured from disk and printed next to the estimate.
3. **Use as normal.** When anything reads the file, macOS decompresses it on the fly. Code signatures, permissions, dates and Finder tags are kept.

Finder's **Get Info** shows both numbers: the file's real size, and the much smaller size *on disk*.

## Install

You need **macOS 13 or later** and [Homebrew](https://brew.sh).

```bash
brew install yesterdayyousaidtmrw/tap/squish
```

This installs Squish and its compression engine, `afsctool`, and works on both Apple Silicon and Intel Macs. Check that it works:

```bash
squish version
squish help
```

Update later with `brew upgrade squish`.

**From source** (needs Xcode or the Command Line Tools: `xcode-select --install`):

```bash
brew install afsctool
git clone https://github.com/yesterdayyousaidtmrw/squish.git
cd squish
swift build -c release
sudo mkdir -p /usr/local/bin
sudo cp "$(swift build -c release --show-bin-path)/squish" /usr/local/bin/
```

## Quick start

```bash
squish scan          # preview: what would be compressed, and why the rest is skipped
squish compress      # do it (asks before changing anything)
squish status ~/Documents   # how much of a folder is compressed
```

`scan` never compresses or modifies anything. A typical result (the second column is the expected saving on disk):

```
Settings: dormant ≥ 30d (apps 21d, devArtifacts 14d) · categories: apps, devArtifacts, code, text, uncompressedMedia · lzfse
Candidates: 13 apps (1.8 GB), 389 files (21.6 MB); sizes are before compression
Estimated saving: ≈905 MB on disk
  app    796.8 MB   ≈−401 MB     38d idle  apps              /Applications/LibreOffice.app
  app    281.1 MB   ≈−132 MB     25d idle  apps              /Applications/SomeGame.app
  file     2.1 MB  ≈−1.7 MB     34d idle  code              ~/Downloads/saved-page/frame.html
  …
Skipped: recentlyUsed 5281 · excludedType 4759 · incompressible 211 · tooLittleGain 1946 · noMatchingCategory 3320 · running 20 · needsAdmin 7
  7 item(s) are owned by root; run with sudo to include them.
```

The estimate is close, not exact. On a 47 MB `node_modules` folder it predicted 32.1 MB, and compressing freed 29.5 MB.

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

Beyond file types, it skips anything that wouldn't pay off:

- **Doesn't shrink enough:** a sample compressed by less than `minSavingsPercent` (`incompressible` in the scan). This catches compressed data under any name.
- **Too small to matter:** the saving would be under 4 KB (`tooLittleGain`). APFS keeps at least one 4 KB block per compressed file, so files of 4 KB or less never get smaller.
- **In use right now:** another program has the file open, such as a database or a log being written (`openElsewhere`). Squish checks again just before compressing. Without `sudo` it can only see your own programs, which are the ones that open your files. System processes are visible only under `sudo`.

### How "unused" is decided

- **Files:** the latest of when the file was last changed, last read, and last opened according to Spotlight.
- **Apps:** the last launch (from Spotlight) or the last install or update.
- **Code projects count as one unit.** A folder with `.git`, `package.json` or `Package.swift` is a project. If you've edited any of its own files or made a git commit or checkout recently, everything inside it counts as in use, including `node_modules`, `.build` and other dependency folders. Those keep their install date forever, so judged file by file they'd look abandoned in a project you work on every day.
- **Files that keep getting rewritten wait longer.** Squish remembers what it compressed in `state.json`, next to your settings. If a compressed file later turns up uncompressed with new content, something is regenerating it, so its waiting time doubles each time it happens, up to 32 times the usual wait. Files that churn stop being compressed only to be undone again.

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
| `minSavingsPercent` | Leave a file alone unless a sample of it shrinks by at least this much | `10` |
| `minFileBytes` | Ignore files smaller than this | `1` |
| `purgeAfterDays` | `squish purge`: days a project must sit untouched before its rebuildable folders go | `90` |
| `excludedPaths` | Folders and files never to touch | none |
| `excludedExtensions` | File types never to touch | already-compressed formats |

**Which algorithm?** Keep `lzfse` unless you have a reason not to. `zlib` saves a little more space but opens files more slowly, so it suits archives you almost never open.

## Commands

| Command | What it does |
|---|---|
| `squish scan` | Preview only. Lists what would be compressed with the expected saving, and counts why the rest was skipped. Add `--all` to list every item. |
| `squish compress` | Compresses everything `scan` found, then prints the real saving next to the estimate. Asks first; add `--yes` to skip the question. |
| `squish status <path>` | Shows how many files are compressed and the size of the data versus space used on disk. |
| `squish restore <path>` | Decompresses everything under a path. |
| `squish purge` | Lists rebuildable folders of long-unused projects and package manager caches. Add `--yes` to move the folders to the Trash and clear the caches. See [Purge](#purge-free-space-completely). |
| `squish categories` | Lists the categories, whether each is on, and its dormancy window. |
| `squish config` | Shows the settings. `config path` prints the file location; `config init` writes the defaults. |
| `squish schedule install` | Runs `compress --yes` every day at 3:00. |
| `squish version` | Prints the installed version. |

Each run can override the settings without editing the file:

```bash
squish scan --in ~/Projects/old-client     # look at one folder only
squish compress --only apps --days 60      # only apps unused for 60+ days
squish compress --algorithm zlib           # smallest result for this run
```

## Purge: free space completely

Some things don't need compressing at all, because they can be recreated: a project's installed dependencies and build output, and the download caches of package managers. `squish purge` finds those and gets rid of them, which frees all of their space rather than half.

```bash
squish purge                 # dry run: what would go, how big, and how to get it back
squish purge --yes           # do it
squish purge --in ~/Work     # only one folder (package manager caches are left out)
squish purge --days 180      # only projects untouched for 180+ days
```

What it removes:

- **Rebuildable folders of projects untouched for 90 days** (`purgeAfterDays`): `node_modules`, `.build`, `Pods`, `target`, `.venv`, `__pycache__`, and a `DerivedData` folder kept inside a project. Xcode's shared `~/Library/Developer/Xcode/DerivedData` isn't touched. A project counts as touched if you edited any of its own files or made a git commit or checkout.
- **Package manager caches**, cleared with each tool's own command: `brew cleanup --prune=all`, `npm cache clean --force`, `pip3 cache purge`. Only tools you have installed are included. Their downloads come back when you next install something. `brew cleanup` also permanently removes old versions of formulae you have installed; the current versions stay.

How it stays safe:

- **Folders go to the Trash, not straight to deletion.** You can put them back until you empty the Trash, and the space only comes back when you do.
- **The name isn't enough.** A folder is only purged when the tool that made it left its marker: `node_modules` needs a `package.json` beside it, `.build` needs `Package.swift`, `target` needs `Cargo.toml` or `pom.xml`, and so on. Your own folder that happens to be called `target` is never touched.
- **Only inside projects.** A `node_modules` folder with no project around it is left alone.
- **Never in use.** Projects you've worked on recently, folders a program has open, and anything in `excludedPaths` are kept. Squish checks again just before moving anything.

Every item in the list shows how to get it back (for example `npm install` or `swift build`).

## Run it automatically

```bash
squish schedule install            # daily at 3:00
squish schedule install --hour 13  # or pick an hour
squish schedule                    # is it installed?
squish schedule uninstall
```

This adds a standard macOS background job (a LaunchAgent) that runs as you, at low priority. Results are written to `~/Library/Logs/squish.log`. The job remembers the path it runs, so install Squish first (see [Install](#install)) rather than scheduling a copy you built in a project folder. With Homebrew it records the `squish` link in Homebrew's `bin` folder (`/opt/homebrew/bin` on Apple Silicon, `/usr/local/bin` on Intel), which keeps working after `brew upgrade`.

Apps installed by the App Store and some installers belong to the system (root), so a scheduled run skips them. To include them, run once by hand with `sudo squish compress`.

If the log shows "Operation not permitted" for `~/Documents` or `~/Downloads`, macOS privacy protection is blocking the background job. Give the `squish` binary (the path `which squish` prints) **Full Disk Access** in System Settings › Privacy & Security. After a `brew upgrade`, check it's still allowed: macOS may treat the new build as a different program.

## Is it safe?

- **Nothing is deleted or moved.** Files keep their names, locations, dates, permissions, tags and code signatures.
- **Every compressed file is verified** before it replaces the original data.
- **It only touches what has gone unused**, and never an app that's running.
- **Always reversible:** `squish restore <path>` puts files back to normal using Apple's own `afscexpand` tool.
- **You see everything first:** `scan` is a dry run, and `compress` asks before it starts.

## Good to know

- **Will things open slower?** Usually you won't notice. LZFSE decompresses very fast, which is why Apple uses it for its own apps. `zlib` is noticeably slower on big files.
- **What if I edit a compressed file?** It works normally. When an app saves it, the file is usually written back uncompressed. The next Squish run compresses it again once it's dormant, after waiting twice as long as before (see [How "unused" is decided](#how-unused-is-decided)).
- **Copying elsewhere:** files are decompressed when copied to cloud storage, another Mac, or a drive that isn't APFS, so they take their full size there.
- **External drives** must be formatted APFS or Mac OS Extended for compression to work.
- **App updates** replace the app's files, so an updated app is uncompressed until it's dormant again.
- **`restore` decompresses everything** under the path, including files Apple shipped already compressed.

## Uninstall

```bash
squish schedule uninstall                       # stop the daily job
brew uninstall squish                           # remove the tool (from source: sudo rm /usr/local/bin/squish)
rm -r ~/Library/Application\ Support/Squish     # remove the settings and history
```

You don't need to restore files first. They keep working exactly as they are. To get them back to full size anyway, run `squish restore <path>` before uninstalling.

## For developers

```bash
swift test   # 54 tests, including real compression round-trips (needs afsctool)
```

- `Sources/SquishCore`: the engine. Config, scanning, dormancy, compression, purge, scheduling.
- `Sources/squish`: the command-line front end.

CI runs the whole suite on every push and fails if any test is skipped.

**Releasing:**
1. Set the new version in `Sources/SquishCore/Version.swift` and push.
2. Tag it (`git tag v0.2.0 && git push origin v0.2.0`). The release workflow tests, builds a universal binary, and publishes it along with a Homebrew bottle and their SHA-256 files. It refuses a tag that doesn't match `Version.swift`.
3. In `Formula/squish.rb` in [homebrew-tap](https://github.com/yesterdayyousaidtmrw/homebrew-tap), update `url` and `sha256` (from the tarball's `.sha256`), plus the bottle's `root_url` and `all:` sha256 (from the bottle's `.sha256`).
