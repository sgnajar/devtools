#' Build and check a package, cleaning up automatically on success.
#'
#' `check` automatically builds and checks a source package, using all
#' known best practices. `check_built` checks an already built package.
#'
#' Passing `R CMD check` is essential if you want to submit your package
#' to CRAN: you must not have any ERRORs or WARNINGs, and you want to ensure
#' that there are as few NOTEs as possible.  If you are not submitting to CRAN,
#' at least ensure that there are no ERRORs or WARNINGs: these typically
#' represent serious problems.
#'
#' `check` automatically builds a package before calling `check_built`
#' as this is the recommended way to check packages.  Note that this process
#' runs in an independent realisation of R, so nothing in your current
#' workspace will affect the process.
#'
#' @section Environment variables:
#'
#' Devtools does its best to set up an environment that combines best practices
#' with how check works on CRAN. This includes:
#'
#' \itemize{
#'
#'  \item The standard environment variables set by devtools:
#'    [r_env_vars()]. Of particular note for package tests is the
#'    `NOT_CRAN` env var which lets you know that your tests are not
#'    running on CRAN, and hence can take a reasonable amount of time.
#'
#'  \item Debugging flags for the compiler, set by
#'    \code{\link{compiler_flags}(FALSE)}.
#'
#'  \item If `aspell` is found `_R_CHECK_CRAN_INCOMING_USE_ASPELL_`
#'   is set to `TRUE`. If no spell checker is installed, a warning is
#'   issued.)
#'
#'  \item env vars set by arguments `incoming`, `remote` and
#'    `force_suggests`
#' }
#'
#' @return An object containing errors, warnings, and notes.
#' @param pkg package description, can be path or package name.  See
#'   [as.package()] for more information
#' @param document If `NA` and the package uses roxygen2, will
#'   rerun [document()] prior to checking. Use `TRUE`
#'   and `FALSE` to override this default.
#' @param build_args Additional arguments passed to `R CMD build`
#' @param check_dir the directory in which the package is checked
#'   compatibility. `args = "--output=/foo/bar"` can be used to change the
#'   check directory.
#' @param ... Additional arguments passed on to [pkgbuild::build()].
#' @param cleanup Deprecated.
#' @seealso [release()] if you want to send the checked package to
#'   CRAN.
#' @export
check <- function(pkg = ".",
                  document = NA,
                  build_args = NULL,
                  ...,
                  manual = FALSE,
                  cran = TRUE,
                  remote = FALSE,
                  incoming = remote,
                  force_suggests = FALSE,
                  run_dont_test = FALSE,
                  args = "--timings",
                  env_vars = NULL,
                  quiet = FALSE,
                  check_dir = tempdir(),
                  cleanup = TRUE,
                  error_on = c("never", "error", "warning", "note")) {
  pkg <- as.package(pkg)
  withr::local_options(list(warn = 1))

  save_all()

  if (!missing(cleanup)) {
    warning("`cleanup` is deprecated", call. = FALSE)
  }

  if (missing(error_on) && !interactive()) {
    error_on <- "warning"
  }
  error_on <- match.arg(error_on)

  # document only if package uses roxygen, i.e. has RoxygenNote field
  if (identical(document, NA)) {
    document <- !is.null(pkg$roxygennote)
  }
  if (document) {
    document(pkg)
  }

  if (!quiet) {
    cat_rule(
      left = "Building",
      right = pkg$package,
      col = "cyan"
    )
    show_env_vars(pkgbuild::compiler_flags(FALSE))
  }

  withr::with_envvar(pkgbuild::compiler_flags(FALSE), action = "prefix", {
    built_path <- pkgbuild::build(
      pkg$path,
      tempdir(),
      args = build_args,
      quiet = quiet,
      manual = manual,
      ...
    )
    on.exit(unlink(built_path), add = TRUE)
  })

  check_built(
    built_path,
    cran = cran,
    remote = remote,
    incoming = incoming,
    force_suggests = force_suggests,
    run_dont_test = run_dont_test,
    manual = manual,
    args = args,
    env_vars = env_vars,
    quiet = quiet,
    check_dir = check_dir,
    error_on = error_on
  )
}

#' @export
#' @rdname check
#' @param path Path to built package.
#' @param cran if `TRUE` (the default), check using the same settings as
#'   CRAN uses.
#' @param remote Sets `_R_CHECK_CRAN_INCOMING_REMOTE_` env var.
#'   If `TRUE`, performs a number of CRAN incoming checks that require
#'   remote access.
#' @param incoming Sets `_R_CHECK_CRAN_INCOMING_` env var.
#'   If `TRUE`, performs a number of CRAN incoming checks.
#' @param force_suggests Sets `_R_CHECK_FORCE_SUGGESTS_`. If
#'   `FALSE` (the default), check will proceed even if all suggested
#'   packages aren't found.
#' @param run_dont_test Sets `--run-donttest` so that tests surrounded in
#'   \code{\\dontest\{\}} are also tested. This is important for CRAN
#'   submission.
#' @param manual If `FALSE`, don't build and check manual
#'   (`--no-manual`).
#' @param args Additional arguments passed to `R CMD check`
#' @param env_vars Environment variables set during `R CMD check`
#' @param quiet if `TRUE` suppresses output from this function.
#' @inheritParams rcmdcheck::rcmdcheck
check_built <- function(path = NULL, cran = TRUE,
                        remote = FALSE, incoming = remote, force_suggests = FALSE,
                        run_dont_test = FALSE, manual = FALSE, args = "--timings",
                        env_vars = NULL, check_dir = tempdir(), quiet = FALSE,
                        error_on = c("never", "error", "warning", "note")) {
  if (missing(error_on) && !interactive()) {
    error_on <- "warning"
  }
  error_on <- match.arg(error_on)

  pkgname <- gsub("_.*?$", "", basename(path))

  if (cran) {
    args <- c("--as-cran", args)
  }
  if (run_dont_test) {
    args <- c("--run-donttest", args)
  }

  if (manual && !pkgbuild::has_latex()) {
    message(
      "pdflatex not found! Not building PDF manual or vignettes.\n",
      "If you are planning to release this package, please run a check with ",
      "manual and vignettes beforehand."
    )
    manual <- FALSE
  }

  if (!manual) {
    args <- c(args, "--no-manual")
  }

  env_vars <- check_env_vars(cran, remote, incoming, force_suggests, env_vars)
  if (!quiet) {
    cat_rule(
      left = "Checking",
      right = pkgname,
      col = "cyan"
    )
    show_env_vars(env_vars, trailing = FALSE)
  }

  withr::with_envvar(env_vars, action = "prefix", {
    rcmdcheck::rcmdcheck(path,
      quiet = quiet, args = args,
      check_dir = check_dir, error_on = error_on
    )
  })
}

check_env_vars <- function(cran = FALSE, remote = FALSE, incoming = remote,
                           force_suggests = TRUE, env_vars = character()) {
  c(
    aspell_env_var(),
    # Switch off expensive check for package version
    # https://github.com/r-lib/devtools/issues/1271
    if (getRversion() >= "3.4.0" && as.numeric(R.version[["svn rev"]]) >= 70944) {
      c("_R_CHECK_CRAN_INCOMING_REMOTE_" = as.character(remote))
    },
    "_R_CHECK_CRAN_INCOMING_" = as.character(incoming),
    "_R_CHECK_FORCE_SUGGESTS_" = as.character(force_suggests),
    env_vars
  )
}

aspell_env_var <- function() {
  tryCatch({
    utils::aspell(NULL)
    c("_R_CHECK_CRAN_INCOMING_USE_ASPELL_" = "TRUE")
  }, error = function(e) character())
}

show_env_vars <- function(env_vars, trailing = TRUE) {
  cat_line("Setting env vars:", col = "darkgrey")
  cat_bullet(paste0(format(names(env_vars)), ": ", unname(env_vars)), col = "darkgrey")
  if (trailing) {
    cat_rule(col = "cyan")
  }
}
