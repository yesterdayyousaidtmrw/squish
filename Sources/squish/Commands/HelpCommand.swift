enum HelpCommand {
    static func run() {
        print("""
        squish: transparent APFS compression for apps and files you are not using.

        Commands
          scan                     dry run: list what would be compressed and why the rest is skipped
          compress [--yes]         compress candidates in place (asks first unless --yes)
          status <path>…           compressed file count, data size and on-disk size
          restore <path>…          decompress everything under the paths (Apple's afscexpand)
          purge [--yes]            dry run: list rebuildable folders of long-unused projects and
                                   package manager caches; --yes moves the folders to the Trash
                                   and clears the caches (--days N overrides purgeAfterDays)
          categories               list categories, whether each is on, and its dormancy window
          config [show|path|init]  show the settings, print their path, or write the defaults
          schedule [show|install [--hour N]|uninstall]
                                   run `compress --yes` daily via a LaunchAgent (default 03:00)
          version                  print the version

        Overrides for this run (scan, compress, categories, purge)
          --days N                 dormancy window for every category (purge: purgeAfterDays)
          --only a,b               only these categories (see `squish categories`)
          --algorithm lzfse|lzvn|zlib
          --in <folder>            only this folder, for apps and files (purge: leaves caches out)
          --config <file>          use another settings file
          --all                    scan: list every candidate

        Root-owned apps (most App Store apps) need sudo: `sudo squish compress`.
        Compression needs afsctool: `brew install afsctool`.
        """)
    }
}
