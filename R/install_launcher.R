#' Copy the double-clickable launcher to a chosen destination.
#'
#' Copies \code{inst/launcher/tagmodr.command} out of the installed package
#' to \code{dest} and sets the executable bit so double-clicking it in
#' Finder launches the Shiny app. The launcher itself checks that R is
#' installed, installs \pkg{tagmodr}, \pkg{shiny}, and \pkg{DT} if missing,
#' then calls \code{\link{launch_app}}.
#'
#' @param dest Directory to copy the launcher into. Default: user's
#'   Desktop.
#' @param overwrite Logical. Overwrite an existing file at \code{dest}?
#'   Default \code{FALSE}.
#'
#' @return Invisibly returns the full path to the installed launcher.
#' @export
install_launcher <- function(dest = "~/Desktop", overwrite = FALSE) {
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
