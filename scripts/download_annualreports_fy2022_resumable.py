#!/usr/bin/env python3
"""
Resumable / timeout-safe AnnualReports.com collector for FY2022 annual reports.

This version is deliberately conservative:
- defaults to FY2022 only;
- skips firms already marked as pilot-scored unless --include-existing is used;
- never crashes on a timeout; it logs the failure and moves to the next firm;
- writes output incrementally, so Ctrl+C does not destroy previous progress;
- uses short timeouts by default, because AnnualReports can be slow or unreachable.

Install once:
    python -m pip install --upgrade requests urllib3 charset-normalizer beautifulsoup4

Small test:
    python download_annualreports_fy2022_resumable.py --targets annualreports_candidate_list.csv --years 2022 --limit 20 --timeout 8

Bigger test:
    python download_annualreports_fy2022_resumable.py --targets annualreports_candidate_list.csv --years 2022 --limit 120 --timeout 8
"""

import argparse
import csv
import hashlib
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

import requests
try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None

BASE_URL = "https://www.annualreports.com"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
}

LEGAL_SUFFIXES = set("""
PLC P L C AG SE SA SAS NV BV AB ASA AS A/S OYJ OY SPA SRL GMBH KG KGA LTD LIMITED INC CORP CORPORATION
HOLDING HOLDINGS HLDGS GROUP OR THE CO COMPANY COMPAGNIE SOCIETE AKTIEBOLAGET INTERNATIONAL INTL
""".split())

FILINGS_FIELDS = [
    "isin", "firm_name", "country", "fiscal_year", "event_tag", "publication_date", "language", "source",
    "source_url", "annualreports_page_url", "filename", "file_sha256", "narrative_wordcount", "notes"
]
LOG_FIELDS = ["row_number", "company_name", "status", "page_url", "notes"]


def clean_filename(s):
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", str(s or ""))
    return s.strip("_")[:160]


def slugify(name, keep_suffix=True):
    s = str(name or "").lower()
    replacements = {
        "&": " and ", "+": " and ", "æ": "ae", "ø": "o", "å": "a", "ä": "a", "ö": "o",
        "ü": "u", "é": "e", "è": "e", "ê": "e", "á": "a", "à": "a", "ó": "o", "ò": "o",
        "í": "i", "ï": "i", "ç": "c", "ß": "ss"
    }
    for a, b in replacements.items():
        s = s.replace(a, b)
    toks = re.split(r"[^a-z0-9]+", s)
    toks = [t for t in toks if t]
    if not keep_suffix:
        toks = [t for t in toks if t.upper() not in LEGAL_SUFFIXES]
    return "-".join(toks)


def candidate_slugs(row, max_slugs=4):
    vals = [
        row.get("annualreports_slug_guess_1", ""),
        row.get("annualreports_slug_guess_2", ""),
        row.get("annualreports_slug_guess_3", ""),
    ]
    name = row.get("company_name") or row.get("annualreports_search_name") or ""
    vals += [slugify(name, True), slugify(name, False)]
    simple = re.sub(r"\b(the|group|holdings?|international)\b", "", name, flags=re.I)
    vals.append(slugify(simple, False))

    seen = []
    for v in vals:
        v = str(v or "").strip("-/ ")
        if v and v not in seen:
            seen.append(v)
    return seen[:max_slugs]


def make_session():
    s = requests.Session()
    s.headers.update(HEADERS)
    return s


def fetch(session, url, timeout, sleep):
    time.sleep(sleep)
    return session.get(url, timeout=timeout, allow_redirects=True)


def is_company_page(html):
    if "AnnualReports.com" not in html:
        return False
    if "Annual Report" not in html and "annual report" not in html:
        return False
    return True


def extract_links_for_years(html, page_url, years):
    found = {str(y): [] for y in years}
    if BeautifulSoup:
        soup = BeautifulSoup(html, "html.parser")
        for a in soup.find_all("a", href=True):
            href = a.get("href", "")
            abs_url = urljoin(page_url, href)
            try:
                parent_text = a.parent.get_text(" ", strip=True)
            except Exception:
                parent_text = a.get_text(" ", strip=True)
            link_text = a.get_text(" ", strip=True)
            context = f"{parent_text} {link_text} {href}"
            for y in years:
                ys = str(y)
                annual_report_context = ("Annual Report" in context or "annual report" in context)
                direct_pdf_context = ("AnnualReportArchive" in href or href.lower().endswith(".pdf"))
                if ys in context and (annual_report_context or direct_pdf_context):
                    if abs_url not in found[ys]:
                        found[ys].append(abs_url)
    else:
        for y in years:
            ys = str(y)
            for m in re.finditer(rf".{{0,600}}{ys}\s+Annual Report.{{0,600}}", html, re.I | re.S):
                block = m.group(0)
                for href in re.findall(r'href=["\']([^"\']+)["\']', block):
                    abs_url = urljoin(page_url, href)
                    if abs_url not in found[ys]:
                        found[ys].append(abs_url)
    return found


def resolve_pdf_url(session, url, timeout, sleep):
    """Return (pdf_url, content_bytes or None, note)."""
    try:
        r = fetch(session, url, timeout=timeout, sleep=sleep)
    except requests.exceptions.RequestException as e:
        return url, None, f"fetch_error:{type(e).__name__}:{e}"
    except Exception as e:
        return url, None, f"fetch_error:{type(e).__name__}:{e}"

    ctype = r.headers.get("content-type", "").lower()
    if "application/pdf" in ctype or r.url.lower().endswith(".pdf") or r.content[:4] == b"%PDF":
        return r.url, r.content, "pdf"

    text = r.text
    patterns = [
        r'href=["\']([^"\']*HostedData/AnnualReportArchive/[^"\']+\.pdf)["\']',
        r'(https?://[^"\']+\.pdf)'
    ]
    for pat in patterns:
        m = re.search(pat, text, re.I)
        if not m:
            continue
        pdf = urljoin(r.url, m.group(1))
        try:
            rr = fetch(session, pdf, timeout=timeout, sleep=sleep)
            if rr.content[:4] == b"%PDF" or "application/pdf" in rr.headers.get("content-type", "").lower():
                return rr.url, rr.content, "pdf_resolved_from_html"
        except requests.exceptions.RequestException as e:
            return pdf, None, f"pdf_fetch_error:{type(e).__name__}:{e}"
        except Exception as e:
            return pdf, None, f"pdf_fetch_error:{type(e).__name__}:{e}"
    return r.url, None, "not_pdf"


def write_header_if_needed(path, fieldnames, append):
    path = Path(path)
    need_header = True
    if append and path.exists() and path.stat().st_size > 0:
        need_header = False
    f = path.open("a" if append else "w", newline="", encoding="utf-8")
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    if need_header:
        writer.writeheader()
        f.flush()
    return f, writer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--targets", default="annualreports_candidate_list.csv")
    ap.add_argument("--years", nargs="+", default=["2022"], help="Default: 2022 only")
    ap.add_argument("--outdir", default="annualreports_pdfs")
    ap.add_argument("--limit", type=int, default=20, help="Default 20 for safe testing. Use 0 for no limit.")
    ap.add_argument("--start", type=int, default=1, help="1-based row number in the CSV to start from")
    ap.add_argument("--timeout", type=float, default=8.0, help="Seconds before skipping a slow request")
    ap.add_argument("--sleep", type=float, default=0.5, help="Pause between requests")
    ap.add_argument("--max-slugs", type=int, default=3, help="Maximum guessed company-page slugs to try per firm")
    ap.add_argument("--include-existing", action="store_true", help="Try rows already marked as pilot-scored")
    ap.add_argument("--append", action="store_true", help="Append to existing output CSVs instead of overwriting")
    args = ap.parse_args()

    years = [str(y) for y in args.years]
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    with open(args.targets, newline="", encoding="utf-8-sig") as f:
        all_rows = list(csv.DictReader(f))

    start_index = max(args.start - 1, 0)
    rows = all_rows[start_index:]
    if args.limit and args.limit > 0:
        rows = rows[:args.limit]

    print(f"Rows to process: {len(rows)} | start={args.start} | years={','.join(years)} | timeout={args.timeout}s")
    print("Output files: filings_index_annualreports.csv, annualreports_download_log.csv")

    filings_f, filings_writer = write_header_if_needed("filings_index_annualreports.csv", FILINGS_FIELDS, args.append)
    log_f, log_writer = write_header_if_needed("annualreports_download_log.csv", LOG_FIELDS, args.append)

    session = make_session()
    downloaded = 0

    try:
        for offset, row in enumerate(rows, 0):
            row_number = start_index + offset + 1
            company = row.get("company_name", "")
            isin = row.get("isin", "")
            print(f"[{offset + 1}/{len(rows)} | CSV row {row_number}] {company}")

            if (row.get("already_in_pilot_index") == "Y") and not args.include_existing:
                log_writer.writerow({
                    "row_number": row_number,
                    "company_name": company,
                    "status": "skipped_existing_pilot",
                    "page_url": "",
                    "notes": "use --include-existing to download anyway"
                })
                log_f.flush()
                continue

            page_url = ""
            html = ""
            status = "page_not_found"
            page_notes = []

            for slug in candidate_slugs(row, max_slugs=args.max_slugs):
                url = f"{BASE_URL}/Company/{slug}"
                try:
                    r = fetch(session, url, timeout=args.timeout, sleep=args.sleep)
                    if r.status_code == 200 and is_company_page(r.text):
                        page_url = r.url
                        html = r.text
                        status = "page_found"
                        break
                    page_notes.append(f"{slug}:status_{r.status_code}")
                except requests.exceptions.RequestException as e:
                    status = f"page_error_{type(e).__name__}"
                    page_notes.append(f"{slug}:{type(e).__name__}")
                except Exception as e:
                    status = f"page_error_{type(e).__name__}"
                    page_notes.append(f"{slug}:{type(e).__name__}")

            if not page_url:
                log_writer.writerow({
                    "row_number": row_number,
                    "company_name": company,
                    "status": status,
                    "page_url": "",
                    "notes": "; ".join(page_notes[:8])
                })
                log_f.flush()
                continue

            year_links = extract_links_for_years(html, page_url, years)
            any_download = False

            for y in years:
                links = year_links.get(y, [])
                if not links:
                    log_writer.writerow({
                        "row_number": row_number,
                        "company_name": company,
                        "status": f"missing_year_{y}",
                        "page_url": page_url,
                        "notes": "Company page found but no annual-report link for year"
                    })
                    log_f.flush()
                    continue

                final_url, content, note = resolve_pdf_url(session, links[0], timeout=args.timeout, sleep=args.sleep)
                if content:
                    fname = f"{clean_filename(isin or company)}_FY{y}_{clean_filename(company)}.pdf"
                    path = outdir / fname
                    path.write_bytes(content)
                    sha = hashlib.sha256(content).hexdigest()
                    event_tag = "FY2022_for_E1_2023_12_11" if y == "2022" else f"FY{y}_optional_later_vintage"
                    filings_writer.writerow({
                        "isin": isin,
                        "firm_name": company,
                        "country": row.get("country", ""),
                        "fiscal_year": y,
                        "event_tag": event_tag,
                        "publication_date": "",
                        "language": "English_or_check",
                        "source": "AnnualReports.com",
                        "source_url": final_url,
                        "annualreports_page_url": page_url,
                        "filename": str(path),
                        "file_sha256": sha,
                        "narrative_wordcount": "",
                        "notes": note
                    })
                    filings_f.flush()
                    log_writer.writerow({
                        "row_number": row_number,
                        "company_name": company,
                        "status": f"downloaded_{y}",
                        "page_url": page_url,
                        "notes": final_url
                    })
                    log_f.flush()
                    any_download = True
                    downloaded += 1
                    print(f"  downloaded FY{y}")
                else:
                    log_writer.writerow({
                        "row_number": row_number,
                        "company_name": company,
                        "status": f"link_not_pdf_{y}",
                        "page_url": page_url,
                        "notes": f"{links[0]} | {note}"
                    })
                    log_f.flush()

            if not any_download:
                log_writer.writerow({
                    "row_number": row_number,
                    "company_name": company,
                    "status": "page_found_no_downloads",
                    "page_url": page_url,
                    "notes": "Manual check may still find PDFs"
                })
                log_f.flush()

    except KeyboardInterrupt:
        print("\nStopped by user. Partial CSV outputs were already written.")
    finally:
        filings_f.close()
        log_f.close()

    print(f"Done or stopped. Downloaded {downloaded} PDF(s) into {outdir}/")
    print("Send annualreports_download_log.csv and filings_index_annualreports.csv for inspection.")


if __name__ == "__main__":
    main()
