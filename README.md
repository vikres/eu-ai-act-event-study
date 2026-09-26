# eu-ai-act-event-study

Code for my Bocconi undergraduate thesis, *AI exposure and equity market reactions to the EU Artificial Intelligence Act: evidence from European listed firms* (2026).

Stage 1 is an event study of STOXX Europe 600 constituents around four EU AI Act milestones: the trilogue agreement (December 2023), the start of general-purpose AI obligations (August 2025), the Council position on simplification (March 2026) and the simplification agreement (May 2026). Stage 2 scores each firm's AI exposure from the text of its annual report and tests whether the market's reaction scales with it.

| Script | What it does |
|---|---|
| `scripts/01_membership.R` | Rebuilds point-in-time index membership on each event date from the Compustat Global constituent history, so firms that later left the index stay in the sample (680 distinct firms, 581 to 589 per event after screens) |
| `scripts/02_build_returns.R` | Stitches the Datastream download batches into total-return (RI) and market-value (MV) panels keyed by ISIN |
| `scripts/03_event_study.R` | Estimates a market model per firm and event over trading days −250 to −30, then computes abnormal returns, CARs and summary statistics per event |
| `scripts/04_figures.R` | Plots CAAR paths over [−10, +10] for each event (`figures/fig_caar_paths.png`) |
| `scripts/download_annualreports_fy2022_resumable.py` | Collects FY2022 annual-report PDFs from annualreports.com, resuming where it stopped and skipping slow requests instead of failing |
| `scripts/ai_exposure_scorer.py` | Scores each firm's AI exposure from its annual-report text with four frozen dictionaries (salience, specificity, developer orientation, governance), so the same PDFs always give the same scores |
| `figures/fig1_caar_paths.R` | Final Figure 1: CAAR paths around each event |
| `figures/fig2_dose_response.R` | Figure 2: signed CARs against AI-exposure bins, showing no smooth gradient |
| `figures/fig3_incidence_ladder.R` | Figure 3: treated-minus-control CARs for each exposure definition, showing the reaction follows legal categories rather than continuous exposure |

## Data

Not included, because the sources are licensed or copyrighted: index constituents come from Compustat Global via WRDS, returns from LSEG Datastream and annual reports from the companies themselves. The R scripts read their inputs from `data/`, and the scorer reads the PDF folder set at the top of the file.
