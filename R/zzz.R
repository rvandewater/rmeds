.onLoad <- function(libname, pkgname) {
  if (!isTRUE(getOption("rmeds.declare_python", TRUE))) {
    return(invisible())
  }
  # py_require() only adds packages once Python is running; if another
  # package already started an incompatible Python, say so instead of failing.
  tryCatch(
    declarePythonRequirements(),
    error = function(e) {
      warning(
        "rmeds could not declare its Python requirements: ", conditionMessage(e),
        "\nSet options(rmeds.python = <path>) to use a separate environment.",
        call. = FALSE
      )
    }
  )
  invisible()
}
