test_that(".wise_cpu_count honours WISEAPP_THREADS and otherwise uses availableCores", {
  withr::with_envvar(c(WISEAPP_THREADS = "3"), expect_identical(.wise_cpu_count(), 3L))
  withr::with_envvar(c(WISEAPP_THREADS = ""), {
    n <- .wise_cpu_count()
    expect_true(is.integer(n) && n >= 1L)
    expect_identical(n, as.integer(parallelly::availableCores(omit = 1L)[[1L]]))
  })
})

test_that("weather CPU count prefers its own override, then the shared helper", {
  withr::with_envvar(c(WISEAPP_WEATHER_CPU_COUNT = "2", WISEAPP_THREADS = "5"),
    expect_identical(.wx_available_cpu_count(), 2))
  withr::with_envvar(c(WISEAPP_WEATHER_CPU_COUNT = "", WISEAPP_THREADS = "5"),
    expect_identical(.wx_available_cpu_count(), 5L))
})
