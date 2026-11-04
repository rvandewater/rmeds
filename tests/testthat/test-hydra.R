test_that("hydraOverrides formats R values for Hydra", {
  expect_equal(
    hydraOverrides(a = "x/y.z", b = TRUE, c = FALSE, d = 1e6, e = NULL, "++f" = c("p", "q")),
    c("a=x/y.z", "b=true", "c=false", "d=1000000", "++f=[p,q]")
  )
})

test_that("hydraOverrides quotes values Hydra would misparse", {
  expect_equal(hydraOverrides(p = "/a b/c,d"), "p='/a b/c,d'")
  expect_equal(hydraOverrides(p = "it's"), "p='it\\'s'")
  expect_equal(hydraOverrides(p = "C:/data/omop"), "p=C:/data/omop")
})

test_that("hydraOverrides needs names", {
  expect_equal(hydraOverrides(), character())
  expect_error(hydraOverrides("x"), "named")
})

test_that("runPythonTool rejects unknown tools", {
  expect_error(runPythonTool("pip"), "must be one of")
})
