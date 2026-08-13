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
"$RSCRIPT" --vanilla -e '
  repo <- "https://cloud.r-project.org"
  ensure <- function(pkg, github = NULL) {
    if (requireNamespace(pkg, quietly = TRUE)) return(invisible())
    if (is.null(github)) {
      install.packages(pkg, repos = repo)
    } else {
      if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes", repos = repo)
      remotes::install_github(github, upgrade = "never")
    }
  }
  ensure("shiny")
  ensure("DT")
  ensure("tagmodr", github = "Shimpeim/tagmodr")
  tagmodr::launch_app(launch.browser = TRUE)
' || die "The Shiny app exited with an error. Run the launcher from a Terminal to see the full log."
