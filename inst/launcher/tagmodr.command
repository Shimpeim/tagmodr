#!/usr/bin/env bash
#
# tagmodr launcher (macOS).
#
# Double-clicking this file in Finder starts the tagmodr Shiny app. On
# first run it installs tagmodr, shiny, and DT if any are missing. Any
# error is shown in a macOS alert so the user sees it even when the
# terminal window closes.

set -u

cd "$(dirname "$0")" || exit 1

# Show an error via osascript so the user sees it even if the terminal
# is auto-closed after the script exits.
die() {
  local msg="$1"
  echo "ERROR: $msg" >&2
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display alert \"tagmodr launcher\" message \"$msg\" as critical" >/dev/null 2>&1 || true
  fi
  exit 1
}

# ---- Locate Rscript --------------------------------------------------
RSCRIPT=""
for cand in \
    "$(command -v Rscript 2>/dev/null)" \
    /opt/homebrew/bin/Rscript \
    /usr/local/bin/Rscript \
    /Library/Frameworks/R.framework/Resources/bin/Rscript; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    RSCRIPT="$cand"
    break
  fi
done

if [ -z "$RSCRIPT" ]; then
  die "R was not found. Install R from https://cran.r-project.org, then double-click this file again."
fi

# ---- Install missing packages, then launch ---------------------------
# --no-init-file skips ~/.Rprofile (avoids user-site interactive weirdness)
# but still reads ~/.Renviron -- the file that typically puts the user
# library on .libPaths(). Using --vanilla here would drop the user lib
# and cause a stale system-lib copy of tagmodr to shadow whatever was
# installed interactively.
"$RSCRIPT" --no-init-file -e '
  repo <- "https://cloud.r-project.org"
  ensure_cran <- function(pkg) {
    if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, repos = repo)
  }
  ensure_cran("remotes")
  ensure_cran("shiny")
  ensure_cran("DT")
  # Always ask remotes for tagmodr -- with force = FALSE (default) it
  # checks the remote git SHA against the installed copy and skips the
  # reinstall if we are already on the latest. That means every launch
  # picks up new releases without the user having to remember to
  # remotes::install_github() themselves.
  remotes::install_github("Shimpeim/tagmodr", upgrade = "never", quiet = TRUE)
  tagmodr::launch_app(launch.browser = TRUE)
' || die "The Shiny app exited with an error. Run the launcher from a Terminal to see the full log."
