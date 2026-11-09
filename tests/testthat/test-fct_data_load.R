test_that(".read_csv_raw types columns as readr::read_csv did", {
  csv <- paste0(
    "code,year,x,flag,d,name,all_na\n",
    "001,2020,1.5,TRUE,2020-01-02,\"a, b\",NA\n",
    "002,2021,,FALSE,2021-03-04, c ,\n"
  )
  out <- .read_csv_raw(charToRaw(csv))

  expect_s3_class(out, "tbl_df")
  expect_identical(out$code, c("001", "002"))
  expect_identical(out$year, c(2020, 2021))
  expect_identical(out$x, c(1.5, NA))
  expect_identical(out$flag, c(TRUE, FALSE))
  expect_identical(out$d, as.Date(c("2020-01-02", "2021-03-04")))
  expect_identical(out$name, c("a, b", "c"))
  expect_identical(out$all_na, c(NA, NA))
})
