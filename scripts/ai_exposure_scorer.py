#!/usr/bin/env python3
# =====================================================================
# ai_exposure_scorer.py
# ---------------------------------------------------------------------
# STAGE 2 (primary scorer): firm-level AI-exposure scores from the text
# of annual-report PDFs, using a FROZEN dictionary. Deterministic and
# fully reproducible: same PDFs in -> same scores out. This is the
# defensible, primary measure (the LLM-assisted pass is a separate,
# secondary robustness check).
#
# What it does:
#   1. Reads every PDF in a folder.
#   2. Extracts the text.
#   3. Applies four frozen dictionaries (salience, specificity,
#      developer orientation, governance) and counts matches.
#   4. Normalises each to hits per 1,000 words.
#   5. Writes one row per report to exposure_scores_raw.csv.
#
# You run this; it produces a small CSV; you send me the CSV (not the
# PDFs). The dictionary below is the frozen protocol — printed here so
# it can go straight into your methodology appendix.
#
# Provenance note: the AI helped write this code; you run it and own the
# pipeline. The measure is fixed in this file before any scoring.
# =====================================================================

# ---- SETUP -----------------------------------------------------------
# Install once in your terminal:
#     pip install pymupdf pandas
#
# Put your PDFs in one folder, name them by firm (e.g. SAP_2022.pdf).
# Set the folder path below, then run:
#     python ai_exposure_scorer.py
# ---------------------------------------------------------------------

import os
import re
import sys
import pandas as pd

try:
    import fitz  # PyMuPDF
except ImportError:
    sys.exit("PyMuPDF not installed. Run:  pip install pymupdf pandas")

# ---- CONFIG: set this to your PDF folder -----------------------------
PDF_DIR = r"C:/Users/victo/Downloads/thesis/reports"   # <-- EDIT THIS
OUT_CSV = "exposure_scores_raw.csv"
# ---------------------------------------------------------------------


# =====================================================================
# FROZEN DICTIONARY  (do not edit after scoring begins)
# Each entry is a regular expression, matched case-insensitively unless
# noted. \b = word boundary; (?:s)? allows an optional plural.
# =====================================================================

# --- Component 1: SALIENCE (how much AI is discussed) ----------------
SALIENCE = [
    r"\bartificial intelligence\b",
    r"\bmachine learning\b",
    r"\bdeep learning\b",
    r"\bneural network(?:s)?\b",
    r"\bnatural language processing\b",
    r"\blarge language model(?:s)?\b",
    r"\bgenerative ai\b",
    r"\bfoundation model(?:s)?\b",
    r"\bcomputer vision\b",
    r"\bpredictive analytics\b",
    r"\btransformer model(?:s)?\b",
    r"\breinforcement learning\b",
    r"\bNLP\b",
    r"\bLLM(?:s)?\b",
    r"\balgorithmic\b",
]
# The bare token "AI" is handled separately (case-sensitive uppercase)
# to avoid false positives from unrelated words.
AI_TOKEN = r"\bAI\b"

# --- Component 2: SPECIFICITY (does the firm DO AI vs name it) --------
SPECIFICITY_CONCRETE = [
    r"\bAI platform(?:s)?\b",
    r"\bAI system(?:s)?\b",
    r"\bAI(?:-| )powered\b",
    r"\bAI(?:-| )driven\b",
    r"\bAI solution(?:s)?\b",
    r"\bAI application(?:s)?\b",
    r"\bAI tool(?:s)?\b",
    r"\bAI capabilit(?:y|ies)\b",
    r"\bAI model(?:s)?\b",
    r"\bmachine learning model(?:s)?\b",
    r"\bAI use(?:-| )case(?:s)?\b",
    r"\bAI investment(?:s)?\b",
    r"\binvested in AI\b",
    r"\bproprietary (?:AI|model)\b",
    r"\bdeployed? (?:AI|machine learning)\b",
]
SPECIFICITY_ANTI = [
    r"\bexploring (?:the use of )?AI\b",
    r"\bpotential of AI\b",
    r"\bfuture of AI\b",
    r"\bconsidering AI\b",
    r"\bopportunities in AI\b",
    r"\bmay (?:use|adopt) AI\b",
]

# --- Component 3: DEVELOPER ORIENTATION (provider vs deployer) --------
DEVELOPER_LANG = [
    r"\btrain(?:ing|ed)? (?:a |our )?model(?:s)?\b",
    r"\b(?:build|develop)(?:ing|ed)? (?:our own )?AI\b",
    r"\bfine(?:-| )tun(?:e|ing|ed)\b",
    r"\bproprietary model(?:s)?\b",
    r"\bour AI platform\b",
    r"\bfoundation model(?:s)?\b",
    r"\bAI research\b",
    r"\bmodel architecture\b",
]
DEPLOYER_LANG = [
    r"\bdeploy(?:ing|ed)? AI\b",
    r"\bintegrat(?:e|ing|ed) AI\b",
    r"\bthird(?:-| )party AI\b",
    r"\bAI(?:-| )powered\b",
    r"\badopt(?:ing|ed)? AI\b",
    r"\bleverag(?:e|ing) AI\b",
    r"\buse of AI\b",
    r"\bAI tool(?:s)?\b",
    r"\bAI solution(?:s)?\b",
]

# --- Component 4: GOVERNANCE / RISK ENGAGEMENT -----------------------
GOVERNANCE = [
    r"\bAI governance\b",
    r"\bAI risk(?:s)?\b",
    r"\bresponsible AI\b",
    r"\bethical AI\b",
    r"\bAI ethics\b",
    r"\bAI oversight\b",
    r"\bAI policy\b",
    r"\bAI principles\b",
    r"\balgorithmic accountability\b",
    r"\bAI regulation\b",
    r"\bAI Act\b",
    r"\bAI compliance\b",
    r"\btrustworthy AI\b",
]


# =====================================================================
# Counting helpers
# =====================================================================
def count_patterns(text, patterns, flags=re.IGNORECASE):
    """Total number of matches across a list of regex patterns."""
    total = 0
    for p in patterns:
        total += len(re.findall(p, text, flags))
    return total


def score_text(text):
    """Return the four component counts (raw) for one document's text."""
    n_words = max(len(text.split()), 1)  # avoid divide-by-zero

    salience = count_patterns(text, SALIENCE)
    salience += len(re.findall(AI_TOKEN, text))  # case-sensitive "AI"

    spec_concrete = count_patterns(text, SPECIFICITY_CONCRETE)
    spec_anti = count_patterns(text, SPECIFICITY_ANTI)
    specificity = spec_concrete - spec_anti       # net concreteness

    dev_hits = count_patterns(text, DEVELOPER_LANG)
    dep_hits = count_patterns(text, DEPLOYER_LANG)
    developer_net = dev_hits - dep_hits           # >0 builder, <0 deployer

    governance = count_patterns(text, GOVERNANCE)

    # Normalise each to hits per 1,000 words so long and short reports
    # are comparable.
    per1000 = 1000.0 / n_words
    return {
        "n_words": n_words,
        "salience_per1k":   salience * per1000,
        "specificity_per1k": specificity * per1000,
        "developer_net_per1k": developer_net * per1000,
        "governance_per1k": governance * per1000,
        # raw counts kept for transparency / auditing
        "salience_raw": salience,
        "spec_concrete_raw": spec_concrete,
        "spec_anti_raw": spec_anti,
        "developer_dev_raw": dev_hits,
        "developer_dep_raw": dep_hits,
        "governance_raw": governance,
    }


def extract_text(path):
    """Extract all text from a PDF using PyMuPDF."""
    doc = fitz.open(path)
    pages = [page.get_text() for page in doc]
    n_pages = doc.page_count
    doc.close()
    return "\n".join(pages), n_pages


# =====================================================================
# Main
# =====================================================================
def main():
    if not os.path.isdir(PDF_DIR):
        sys.exit(f"Folder not found: {PDF_DIR}\nEdit PDF_DIR at the top of the script.")

    pdfs = sorted(f for f in os.listdir(PDF_DIR) if f.lower().endswith(".pdf"))
    if not pdfs:
        sys.exit(f"No PDFs found in {PDF_DIR}")

    rows = []
    for fn in pdfs:
        path = os.path.join(PDF_DIR, fn)
        try:
            text, n_pages = extract_text(path)
        except Exception as e:
            print(f"  [!] could not read {fn}: {e}")
            continue

        rec = {"filename": fn,
               "firm": os.path.splitext(fn)[0],  # firm from filename
               "n_pages": n_pages}
        rec.update(score_text(text))

        # Flag likely extraction failure: a 100+ page report that yields
        # very little text is probably scanned/image-based.
        rec["extraction_flag"] = (
            "LOW_TEXT" if (n_pages >= 50 and rec["n_words"] < 8000) else "ok"
        )
        rows.append(rec)
        print(f"  scored {fn:<32} pages={n_pages:>4}  words={rec['n_words']:>7}  "
              f"salience/1k={rec['salience_per1k']:.3f}  {rec['extraction_flag']}")

    df = pd.DataFrame(rows)
    df.to_csv(OUT_CSV, index=False)
    print(f"\nWrote {len(df)} rows to {OUT_CSV}")
    flagged = df[df.extraction_flag == "LOW_TEXT"]
    if len(flagged):
        print(f"\n[!] {len(flagged)} report(s) extracted poorly (likely scanned). "
              f"Re-source these or tell me:\n   " +
              ", ".join(flagged.filename.tolist()))


if __name__ == "__main__":
    main()
