# =====================================================================
# 03_event_study.R   --- STAGE 1: the event study
# ---------------------------------------------------------------------
# Purpose:
#   For each firm and each event, estimate the market model over a
#   pre-event window, compute daily abnormal returns (AR), and cumulate
#   them over event windows to obtain cumulative abnormal returns (CAR).
#   Produces:
#     (a) firm_level_CARs.csv  -- the DEPENDENT VARIABLE for Stage 2
#     (b) aggregate_caar.csv   -- market-wide CAAR + cross-sectional t
#     (c) caar_paths_long.csv  -- CAAR over [-10,+10] for the figures
#
# Method (MacKinlay 1997):
#   Market model:  R_it = a_i + b_i * R_mt + e_it
#   Estimated by OLS over trading days [-250, -30] relative to the event.
#   Abnormal return:  AR_it = R_it - (a_i + b_i * R_mt)
#   Cumulative AR over [t1,t2]:  CAR_i = sum of AR_it over the window.
#   Aggregate test: cross-sectional t = mean(CAR) / (sd(CAR)/sqrt(N)).
#
# Benchmark: STOXX Europe 600 total-return index (market model, primary
#   specification; see methodology Section 5.4 for why the market model
#   rather than Fama-French is primary here).
#
# Inputs (in DATA_DIR):
#   returns_RI_wide.csv      -- from 02_build_returns.R
#   constituents_history.csv -- from 01_membership.R (membership + metadata)
#   index.xlsx               -- STOXX 600 total-return index (sheet "index")
# =====================================================================

# ---- CONFIG ----------------------------------------------------------
DATA_DIR <- "C:/Users/victo/Downloads/thesis/data"
INDEX_FILE <- "index.xlsx"         # <-- file holding the STOXX 600 RI series
INDEX_SHEET <- "index"             # <-- worksheet name
EST_START <- -250                  # estimation window start (trading days)
EST_END   <- -30                   # estimation window end
MIN_OBS   <- 100                   # minimum estimation observations required
# ---------------------------------------------------------------------

library(readxl)

# ---- Load returns panel ----------------------------------------------
RI <- read.csv(file.path(DATA_DIR, "returns_RI_wide.csv"),
               check.names = FALSE, stringsAsFactors = FALSE)
dates <- as.Date(RI$date)
RImat <- as.matrix(RI[, -1])                 # rows = dates, cols = firms (ISIN)
storage.mode(RImat) <- "numeric"
isins <- colnames(RImat)

# Daily simple returns: R_t = RI_t / RI_{t-1} - 1
retmat <- rbind(rep(NA, ncol(RImat)),
                RImat[-1, ] / RImat[-nrow(RImat), ] - 1)

# ---- Load market index and align to the same dates -------------------
idx <- as.data.frame(read_excel(file.path(DATA_DIR, INDEX_FILE), sheet = INDEX_SHEET))
idx_dates <- as.Date(idx[[1]])
idx_vals  <- as.numeric(idx[[2]])
# market return aligned to our trading-day calendar
mret_full <- c(NA, idx_vals[-1] / idx_vals[-length(idx_vals)] - 1)
mret <- mret_full[match(dates, idx_dates)]   # align by date

# ---- Membership + firm metadata --------------------------------------
hist <- read.csv(file.path(DATA_DIR, "constituents_history.csv"),
                 stringsAsFactors = FALSE)
hist$from <- as.Date(hist$from); hist$thru <- as.Date(hist$thru)
meta <- hist[!duplicated(hist$isin), c("isin", "conm", "fic")]
rownames(meta) <- meta$isin

members_on <- function(d) {
  d <- as.Date(d)
  unique(hist$isin[hist$from <= d & (is.na(hist$thru) | hist$thru >= d)])
}

# ---- Events and windows ----------------------------------------------
events <- c(E1 = "2023-12-11", E4 = "2025-08-04",
            E3 = "2026-03-13", E2 = "2026-05-07")

windows <- list("CAR_m1p1" = c(-1, 1),   # primary event window [-1,+1]
                "CAR_0p1"  = c( 0, 1),   # post-event [0,+1]
                "CAR_m2p2" = c(-2, 2),   # wider [-2,+2]
                "CAR_leak" = c(-5,-1))   # pre-event leakage [-5,-1]

# index of the first trading day on/after the event date
t0_of <- function(ev) which(dates >= as.Date(ev))[1]

firm_rows  <- list()   # accumulates firm-level CAR records
agg_rows   <- list()   # accumulates aggregate CAAR records
path_rows  <- list()   # accumulates CAAR path records for plotting

for (ev in names(events)) {
  edate <- events[ev]
  t0  <- t0_of(edate)
  rel <- seq_along(dates) - t0
  est_idx <- which(rel >= EST_START & rel <= EST_END)

  mem  <- members_on(edate)
  cols <- which(isins %in% mem)

  AR <- matrix(NA, nrow = nrow(retmat), ncol = length(cols))
  keep <- logical(length(cols))

  for (jj in seq_along(cols)) {
    j <- cols[jj]
    y <- retmat[, j]; x <- mret
    ok <- est_idx[!is.na(y[est_idx]) & !is.na(x[est_idx])]
    if (length(ok) < MIN_OBS) next
    if (sd(y[ok]) == 0) next
    fit <- lm(y[ok] ~ x[ok])                 # market model on estimation window
    a <- coef(fit)[1]; b <- coef(fit)[2]
    AR[, jj] <- y - (a + b * x)              # abnormal return, all dates
    keep[jj] <- TRUE
  }
  AR   <- AR[, keep, drop = FALSE]
  kcol <- cols[keep]
  kisin <- isins[kcol]

  # ---- firm-level CARs (the Stage 2 dependent variable) --------------
  for (jj in seq_along(kisin)) {
    rec <- list(isin = kisin[jj], event = ev, event_date = edate,
                firm = meta[kisin[jj], "conm"], country = meta[kisin[jj], "fic"])
    for (wn in names(windows)) {
      w <- windows[[wn]]
      rec[[wn]] <- sum(AR[rel >= w[1] & rel <= w[2], jj], na.rm = TRUE)
    }
    firm_rows[[length(firm_rows) + 1]] <- as.data.frame(rec, stringsAsFactors = FALSE)
  }

  # ---- aggregate CAAR + cross-sectional t per window -----------------
  for (wn in names(windows)) {
    w <- windows[[wn]]
    car <- colSums(AR[rel >= w[1] & rel <= w[2], , drop = FALSE], na.rm = TRUE)
    car <- car[is.finite(car)]
    caar <- mean(car); tstat <- caar / (sd(car) / sqrt(length(car)))
    pval <- 2 * pt(-abs(tstat), df = length(car) - 1)
    agg_rows[[length(agg_rows) + 1]] <- data.frame(
      event = ev, window = wn, CAAR_pct = caar * 100,
      t = tstat, p = pval, N = length(car),
      pct_positive = mean(car > 0) * 100, stringsAsFactors = FALSE)
  }

  # ---- CAAR path over [-10,+10] for the figure -----------------------
  pm <- which(rel >= -10 & rel <= 10)
  daily_mean_ar <- rowMeans(AR[pm, , drop = FALSE], na.rm = TRUE)
  caar_path <- cumsum(daily_mean_ar) * 100
  path_rows[[length(path_rows) + 1]] <- data.frame(
    event = ev, rel_day = rel[pm], caar = caar_path, stringsAsFactors = FALSE)
}

firm_panel <- do.call(rbind, firm_rows)
agg_table  <- do.call(rbind, agg_rows)
caar_paths <- do.call(rbind, path_rows)

write.csv(firm_panel, file.path(DATA_DIR, "firm_level_CARs.csv"), row.names = FALSE)
write.csv(agg_table,  file.path(DATA_DIR, "aggregate_caar.csv"),  row.names = FALSE)
write.csv(caar_paths, file.path(DATA_DIR, "caar_paths_long.csv"), row.names = FALSE)

cat("STAGE 1 complete.\n")
cat(sprintf("  firm_level_CARs.csv : %d firm-event rows\n", nrow(firm_panel)))
cat("  aggregate_caar.csv  : market-wide CAAR by event/window\n\n")
print(round(agg_table[, c("CAAR_pct","t","p","N")], 3))
