# tagmodr launcher (macOS)

Double-click `tagmodr.command` in Finder to start the Shiny app. On first
run it will install `tagmodr`, `shiny`, and `DT` from CRAN / GitHub if
they are not already present, then open the app in your default browser.

## Requirements

- **R** — install from https://cran.r-project.org if you don't already
  have it. The launcher looks for `Rscript` in the following locations,
  in order:
  1. Whatever `Rscript` is on your PATH.
  2. `/opt/homebrew/bin/Rscript` (Apple Silicon Homebrew).
  3. `/usr/local/bin/Rscript` (Intel Homebrew / hand-installed).
  4. `/Library/Frameworks/R.framework/Resources/bin/Rscript` (CRAN).

If none is found, an alert box explains the fix.

## Installing the launcher on your Desktop

Once `tagmodr` is installed, run in R:

```r
tagmodr::install_launcher()
```

That copies the launcher to `~/Desktop/tagmodr.command` and marks it as
executable. Pass `dest = "..."` to place it elsewhere.

## First-launch security prompt

The first time you double-click `tagmodr.command`, macOS may refuse to
run it because it was downloaded from the internet. Either:

- Right-click the file, choose **Open**, then confirm the dialog once; or
- Run once from Terminal: `sh ~/Desktop/tagmodr.command`.

Subsequent double-clicks work directly.

## "you do not have appropriate access privileges" error

This is macOS's error when the file lacks the executable bit. It happens
if the file was downloaded via a browser (mode 644) rather than placed by
`tagmodr::install_launcher()` (mode 755). Fix in one line:

```bash
chmod +x ~/Desktop/tagmodr.command && xattr -d com.apple.quarantine ~/Desktop/tagmodr.command
```

Or re-run `tagmodr::install_launcher(overwrite = TRUE)` in R; from v0.2.1
onwards this also strips the quarantine attribute.

## Windows / Linux

There is no bundled launcher for Windows or Linux. On those systems, run:

```r
tagmodr::launch_app()
```
