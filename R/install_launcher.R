#' Copy the double-clickable launcher to a chosen destination.
#'
#' Copies \code{inst/launcher/tagmodr.command} out of the installed package
#' to \code{dest} and sets the executable bit so double-clicking it in
#' Finder launches the Shiny app. The launcher itself checks that R is
#' installed, installs \pkg{tagmodr}, \pkg{shiny}, and \pkg{DT} if missing,
#' then calls \code{\link{launch_app}}.
#'
#' If \code{dest} is \code{NULL} (the default) and the R session is
#' interactive, a folder-picker prompts the user for the install location.
#' The default answer -- selected by cancelling the Tk dialog or hitting
#' Enter at the \code{readline()} prompt -- is the current working
#' directory (\code{\link{getwd}()}). In non-interactive sessions
#' \code{dest} falls back to \code{getwd()} silently. Pass \code{dest}
#' explicitly to skip the prompt.
#'
#' @param dest Directory to copy the launcher into. \code{NULL} (default)
#'   asks interactively, defaulting to the current working directory; a
#'   character path uses it directly.
#' @param overwrite Logical. Overwrite an existing file at \code{dest}?
#'   Default \code{FALSE}.
#'
#' @return Invisibly returns the full path to the installed launcher.
#' @export
install_launcher <- function(dest = NULL, overwrite = FALSE) {
  if (is.null(dest)) {
    dest <- choose_install_dest()
  }
  if (is.null(dest) || !nzchar(dest)) {
    message("install_launcher: cancelled (no destination selected).")
    return(invisible(NULL))
  }
  dest <- path.expand(dest)
  if (!dir.exists(dest)) {
    stop(sprintf("install_launcher: destination directory does not exist: %s", dest))
  }

  src <- system.file("launcher", "tagmodr.command", package = "tagmodr")
  if (!nzchar(src)) {
    stop("Could not find the launcher inside the installed package. Reinstall tagmodr.")
  }

  out <- file.path(dest, "tagmodr.command")
  if (file.exists(out) && !overwrite) {
    stop(sprintf(
      "install_launcher: %s already exists. Use overwrite = TRUE to replace it.",
      out
    ))
  }

  ok <- file.copy(src, out, overwrite = overwrite)
  if (!isTRUE(ok)) stop(sprintf("install_launcher: file.copy failed for %s", out))

  # Set the executable bit so Finder / macOS Terminal will run it on
  # double-click. On non-Unix systems Sys.chmod is a no-op.
  Sys.chmod(out, mode = as.octmode("755"))

  # Defensive: strip macOS Gatekeeper's quarantine xattr if present. This
  # matters when the launcher was previously downloaded from a browser
  # (mode 644 + com.apple.quarantine) and install_launcher() is being
  # used to overwrite it -- we want the freshly-installed file to be
  # runnable on first double-click.
  if (Sys.info()[["sysname"]] == "Darwin" && nzchar(Sys.which("xattr"))) {
    # Ignore exit status: xattr -d exits nonzero if the attribute isn't
    # present, which is the normal case for a fresh copy.
    suppressWarnings(
      system2("xattr", args = c("-d", "com.apple.quarantine", out),
              stdout = FALSE, stderr = FALSE)
    )
  }

  # Verify the exec bit landed. On some sync tools (iCloud, network
  # shares) chmod may not stick; warn the user with an actionable fix.
  final_mode <- file.info(out)$mode
  if (!is.na(final_mode) && (as.integer(final_mode) %% 512L) < 448L) {
    warning(sprintf(
      "install_launcher: executable bit did not stick on %s (mode is %s). Run in a terminal:\n  chmod +x %s",
      out, format(as.octmode(final_mode)), shQuote(out)
    ))
  }

  message(sprintf("Installed launcher at: %s\nDouble-click it in Finder to start.", out))
  invisible(out)
}

# Interactive folder picker. Default answer = the current working
# directory. Tries Tk first (native-ish on macOS/Linux/Windows via base
# R's tcltk); falls back to readline() otherwise. Cancelling the Tk
# dialog or hitting Enter at the readline prompt accepts the default
# (working dir) rather than aborting -- the user asked "default = wd
# and ask any other place".
choose_install_dest <- function() {
  default <- getwd()

  if (!interactive()) {
    message(sprintf("install_launcher: non-interactive; using working directory %s", default))
    return(default)
  }

  if (requireNamespace("tcltk", quietly = TRUE) &&
      isTRUE(unname(capabilities("tcltk")))) {
    cat(sprintf(
      "Choose install directory (Cancel accepts the current working dir: %s) ...\n",
      default
    ))
    picked <- tryCatch(
      tcltk::tk_choose.dir(
        default = default,
        caption = "Install tagmodr.command  --  Cancel = current working dir"
      ),
      error = function(e) NA_character_
    )
    if (length(picked) == 1L && !is.na(picked) && nzchar(picked)) {
      return(picked)
    }
    # Tk returned "" (Cancel) OR failed to open -- fall through to
    # readline so the user still gets a chance to type a path.
  }

  cat(sprintf("Install to which directory? [Enter = %s]\n", default))
  ans <- readline("Directory: ")
  if (!nzchar(ans)) default else ans
}
