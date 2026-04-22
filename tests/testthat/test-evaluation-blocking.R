test_that('compute_confusion_counts treats blocking misses as non-predicted', {
  counts <- compute_confusion_counts(
    label_probs = c(0.9, 0.9, 0.2),
    actual_positive = c(TRUE, TRUE, FALSE),
    found_by_blocking = c(TRUE, FALSE, TRUE),
    threshold = 0.5
  )

  expect_equal(counts$tp, 1)
  expect_equal(counts$fp, 0)
  expect_equal(counts$fn, 1)
  expect_equal(counts$tn, 1)
  expect_equal(counts$fn_blocking_miss, 1)
})

test_that('compute_confusion_counts treats NA blocking flags as misses', {
  counts <- compute_confusion_counts(
    label_probs = c(0.9, 0.9),
    actual_positive = c(TRUE, FALSE),
    found_by_blocking = c(TRUE, NA),
    threshold = 0.5
  )

  expect_equal(counts$tp, 1)
  expect_equal(counts$fp, 0)
  expect_equal(counts$fn, 0)
  expect_equal(counts$tn, 1)
  expect_equal(counts$fn_blocking_miss, 0)
})
