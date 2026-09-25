# =====================================================================
# 02_build_returns.R
# ---------------------------------------------------------------------
# Purpose:
#   Stitch the seven Datastream return batches (each a worksheet of
#   paired RI/MV columns for 100 firms) into two clean panels keyed by
#   ISIN: one of total-return indices (RI) and one of market values (MV).
#
# How the mapping works:
#   The Datastream pull returned firms in the SAME order as the master
#   ISIN list (01_membership.R). Within each batch sheet:
#     column 1  = dates
#     columns 2,3 = firm 1  (RI, MV)
#     columns 4,5 = firm 2  (RI, MV) ... and so on.
#   Batch b therefore corresponds to master ISINs ((b-1)*100 + 1) ... .
#   We map columns back to ISINs by this position. Column headers carry
#   company names, not ISINs, which is why position is the reliable key.
#
# Input (in DATA_DIR):
#   returns_batches.xlsx     -- 7 sheets named Batch1 ... Batch7
#   master_isin_list.csv     -- from 01_membership.R
# Output (in DATA_DIR):
#   returns_RI_wide.csv      -- date + 680 firm RI columns
#   returns_MV_wide.csv      -- date + 680 firm MV columns
# =====================================================================

# ---- CONFIG ----------------------------------------------------------
DATA_DIR <- "data"
RETURNS_FILE <- "returns_batches.xlsx"     # <-- EDIT to your raw filename
BATCH_SIZE <- 100                          # firms per batch (last batch may be fewer)
N_BATCHES <- 7
# ---------------------------------------------------------------------

library(readxl)

master <- read.csv(file.path(DATA_DIR, "master_isin_list.csv"),
                   stringsAsFactors = FALSE)$isin

ret_path <- file.path(DATA_DIR, RETURNS_FILE)

ri_list <- list()   # will hold one data.frame (date + firms) per batch
mv_list <- list()
all_dates <- NULL

for (b in 1:N_BATCHES) {
  sheet <- paste0("Batch", b)
  df <- read_excel(ret_path, sheet = sheet)
  df <- as.data.frame(df)

  # First column is the date; keep it once.
  dates <- as.Date(df[[1]])
  if (is.null(all_dates)) all_dates <- dates

  n_cols <- ncol(df)
  n_firms <- (n_cols - 1) / 2          # remaining columns come in RI/MV pairs

  ri_b <- data.frame(date = dates)
  mv_b <- data.frame(date = dates)

  for (k in 1:n_firms) {
    ri_col <- 2 * k        # columns 2,4,6,... are RI
    mv_col <- 2 * k + 1    # columns 3,5,7,... are MV
    isin <- master[(b - 1) * BATCH_SIZE + k]   # position -> ISIN
    ri_b[[isin]] <- as.numeric(df[[ri_col]])
    mv_b[[isin]] <- as.numeric(df[[mv_col]])
  }
  ri_list[[b]] <- ri_b
  mv_list[[b]] <- mv_b
  cat(sprintf("Batch %d: %d firms read\n", b, n_firms))
}

# Combine batches side by side (they share the same date column) ---------
RI <- ri_list[[1]]
MV <- mv_list[[1]]
for (b in 2:N_BATCHES) {
  RI <- cbind(RI, ri_list[[b]][, -1, drop = FALSE])  # drop duplicate date col
  MV <- cbind(MV, mv_list[[b]][, -1, drop = FALSE])
}

# ---- Validation: fail loudly if anything is off -----------------------
n_firm_cols <- ncol(RI) - 1
stopifnot(n_firm_cols == length(master))            # all 680 mapped
stopifnot(!any(duplicated(colnames(RI)[-1])))       # no duplicate ISINs
cat(sprintf("\nCombined RI panel: %d dates x %d firms\n", nrow(RI), n_firm_cols))
cat(sprintf("Date range: %s to %s\n",
            min(RI$date, na.rm = TRUE), max(RI$date, na.rm = TRUE)))
cat("Sanity check — first three firm ISINs (should be AT/BE, alphabetically first):\n  ",
    paste(colnames(RI)[2:4], collapse = ", "), "\n")

write.csv(RI, file.path(DATA_DIR, "returns_RI_wide.csv"), row.names = FALSE)
write.csv(MV, file.path(DATA_DIR, "returns_MV_wide.csv"), row.names = FALSE)
cat("\nDone. Wrote returns_RI_wide.csv and returns_MV_wide.csv to:\n  ", DATA_DIR, "\n", sep = "")
