# =====================================================================
# 01_membership.R
# ---------------------------------------------------------------------
# Purpose:
#   Build point-in-time STOXX Europe 600 membership for each event date
#   from the raw WRDS/Compustat Global "Index Constituents" download,
#   and write out (a) the full membership history and (b) the master
#   list of ISINs in the exact order used to pull the return data.
#
# Why point-in-time:
#   Index membership changes over time. Using today's membership for a
#   2023 event would drop firms that have since left the index and bias
#   the sample toward survivors. We therefore reconstruct who was a
#   member ON each event date using the join ("from") and leave ("thru")
#   dates that WRDS provides for every constituent.
#
# Input  (raw, as downloaded from WRDS):
#   constituents.xlsx  -- columns include: from, thru, gvkey, isin, conm, fic
# Output (written to DATA_DIR):
#   constituents_history.csv   -- cleaned membership history
#   master_isin_list.csv       -- 680 ISINs, ordered (drives 02_build_returns.R)
# =====================================================================

# ---- CONFIG: set this to the folder holding your data files ----------
DATA_DIR <- "data"
CONSTITUENTS_FILE <- "constituents.xlsx" # <-- EDIT to your raw WRDS filename
# ---------------------------------------------------------------------

# Packages (install once with install.packages(c("readxl","dplyr")))
library(readxl)
library(dplyr)

# Read the raw WRDS constituents file -----------------------------------
con_path <- file.path(DATA_DIR, CONSTITUENTS_FILE)
hist <- read_excel(con_path)

# The WRDS column headers are verbose; rename to short, stable names.
# Adjust the right-hand side matching ONLY if your column titles differ.
hist <- hist %>%
  rename(
    from = `(from) Effective From Date`,
    thru = `(thru) Effective Thru Date`,
    gvkey = `(gvkey) Global Company Key - Index Constituent History`,
    conm  = `(conm_cst) Company Name`,
    sedol = `(sedol) SEDOL`,
    isin  = `(isin) International Security Identification Number`,
    fic   = `(fic) Current ISO Country Code - Incorporation`
  )

# Parse dates. A blank "thru" means the firm is still a member.
hist <- hist %>%
  mutate(
    from = as.Date(from),
    thru = as.Date(thru)   # NA where still active
  ) %>%
  filter(!is.na(isin))     # drop the few legacy rows with no ISIN

# Save cleaned history (used by the event study for firm metadata too)
write.csv(hist, file.path(DATA_DIR, "constituents_history.csv"), row.names = FALSE)

# Point-in-time membership function -------------------------------------
# A firm is a member on date d if it joined on/before d and either has
# not left, or left on/after d.
members_on <- function(d) {
  d <- as.Date(d)
  m <- hist %>%
    filter(from <= d & (is.na(thru) | thru >= d))
  unique(m$isin)
}

# The four event dates (first trading day on/after the calendar event)
events <- c(
  E1 = "2023-12-11",  # trilogue agreement (tightening, primary)
  E4 = "2025-08-04",  # GPAI obligations apply (developer-focused)
  E3 = "2026-03-13",  # Council position (easing validation)
  E2 = "2026-05-07"   # simplification agreement (easing, primary)
)

# Report membership counts per event (a useful sanity check)
cat("Point-in-time membership counts:\n")
for (nm in names(events)) {
  cat(sprintf("  %s (%s): %d firms\n", nm, events[nm], length(members_on(events[nm]))))
}

# Master universe = union of membership across all four events ----------
master <- unique(unlist(lapply(events, members_on)))

# IMPORTANT — ordering:
# The daily return data was pulled from Datastream in batches built from
# this master list sorted in C-locale (byte) order. We reproduce that
# exact order with method = "radix" so that 02_build_returns.R can map
# return columns back to ISINs by position. Do not change this sort.
master <- sort(master, method = "radix")

cat(sprintf("\nMaster universe (union): %d ISINs\n", length(master)))
write.csv(data.frame(isin = master),
          file.path(DATA_DIR, "master_isin_list.csv"), row.names = FALSE)

cat("\nDone. Wrote constituents_history.csv and master_isin_list.csv to:\n  ",
    DATA_DIR, "\n", sep = "")
