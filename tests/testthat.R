# This file is part of the standard testthat setup.
# It runs all test files in tests/testthat/ when R CMD check is invoked.

library(testthat)
library(rollama)

test_check("rollama")
