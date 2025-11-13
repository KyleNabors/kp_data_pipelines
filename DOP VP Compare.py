import pandas as pd
from datetime import datetime
from typing import Tuple

try:
    import xlsxwriter  # noqa: F401

    EXCEL_ENGINE = "xlsxwriter"
except ModuleNotFoundError:
    EXCEL_ENGINE = "openpyxl"
    try:
        import openpyxl  # noqa: F401
    except ModuleNotFoundError as exc:
        raise ModuleNotFoundError(
            "Install 'xlsxwriter' or 'openpyxl' to enable Excel exports."
        ) from exc

# =========================
# CONFIGURATION
# =========================

# Date range
START_DATE = "2000-01-01"
END_DATE = "2025-12-31"

# Input file paths
DOR_PATH = (
    r"C:\Users\O304312\OneDrive - Kaiser Permanente\Documents\DOR Transactions.xlsx"
)
VP_PATH = r"C:\Users\O304312\Downloads\Transaction.xlsx"

# Column names used in each system
DOR_DATE_COL = "Award Term Start Date"
DOR_ID_COL = "Project ID"
DOR_TITLE_COL = "Project Title"
DOR_AMOUNT_COL = "Total Cash Receipts"
DOR_PROGRAM_COL = "Program Area"

VP_DATE_COL = "Accountable Completed Date"
VP_ID_COL = "Service Line Code"  # This is what should match Project ID
VP_AMOUNT_COL = "Transaction Amount"
VP_STUDY_CODE_COL = "Site Study Code"

# Program areas to exclude **only** when they are DOR-only
EXCLUDE_DOR_ONLY_PROGRAMS = ["KPOCT", "Pedi-Onc"]

# Output files
MERGED_OUT = "recon_merged.csv"
DOR_ONLY_OUT = "dor_only_ids.csv"
VP_ONLY_OUT = "vp_only_ids.csv"

# =========================
# HELPER FUNCTIONS
# =========================


def load_and_clean_dor(path: str, start_date: str, end_date: str) -> pd.DataFrame:
    """Load DOR data, filter by date, and keep key columns."""
    start = pd.to_datetime(start_date)
    end = pd.to_datetime(end_date)

    dor = pd.read_excel(path)

    # Make sure required columns exist
    for col in [
        DOR_DATE_COL,
        DOR_ID_COL,
        DOR_TITLE_COL,
        DOR_AMOUNT_COL,
        DOR_PROGRAM_COL,
    ]:
        if col not in dor.columns:
            dor[col] = pd.NA

    # Date filter
    dor[DOR_DATE_COL] = pd.to_datetime(dor[DOR_DATE_COL], errors="coerce")
    dor = dor[(dor[DOR_DATE_COL] >= start) & (dor[DOR_DATE_COL] <= end)]

    print(f"DOR rows after date filter: {len(dor)}")

    # Keep only the columns we actually need
    dor = dor[[DOR_ID_COL, DOR_TITLE_COL, DOR_AMOUNT_COL, DOR_PROGRAM_COL]].copy()

    # Clean amount
    dor[DOR_AMOUNT_COL] = pd.to_numeric(dor[DOR_AMOUNT_COL], errors="coerce").fillna(0)

    return dor


def load_and_clean_vp(
    path: str, start_date: str, end_date: str
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Load VP data, dedupe, filter by date, and aggregate by ID (while retaining detail)."""
    start = pd.to_datetime(start_date)
    end = pd.to_datetime(end_date)

    vp = pd.read_excel(path)

    # Drop technical index column if present
    if "Unnamed: 0" in vp.columns:
        vp = vp.drop(columns=["Unnamed: 0"])

    before_dups = len(vp)
    vp = vp.drop_duplicates()
    print(f"VP duplicate rows removed: {before_dups - len(vp)}")

    # Ensure columns exist
    for col in [VP_DATE_COL, VP_ID_COL, VP_AMOUNT_COL, VP_STUDY_CODE_COL]:
        if col not in vp.columns:
            vp[col] = pd.NA

    # Date filter
    vp[VP_DATE_COL] = pd.to_datetime(vp[VP_DATE_COL], errors="coerce")
    vp = vp[(vp[VP_DATE_COL] >= start) & (vp[VP_DATE_COL] <= end)]
    print(f"VP rows after date filter: {len(vp)}")

    # Clean amount
    vp[VP_AMOUNT_COL] = pd.to_numeric(vp[VP_AMOUNT_COL], errors="coerce").fillna(0)

    # Drop rows with no ID
    vp = vp.dropna(subset=[VP_ID_COL])
    vp_detail = vp.copy()

    # Aggregate by ID and collect unique Site Study Codes
    vp_grouped = vp.groupby(VP_ID_COL, as_index=False).agg(
        {
            VP_AMOUNT_COL: "sum",
            VP_STUDY_CODE_COL: lambda s: (
                "; ".join(sorted(set(map(str, s.dropna()))))
                if s.notna().any()
                else pd.NA
            ),
        }
    )

    return vp_grouped, vp_detail


def merge_and_reconcile(dor: pd.DataFrame, vp: pd.DataFrame) -> pd.DataFrame:
    """Outer-join DOR and VP and compute reconciliation fields."""
    merged = dor.merge(
        vp,
        how="outer",
        left_on=DOR_ID_COL,
        right_on=VP_ID_COL,
        indicator=True,
        suffixes=("_dor", "_vp"),
    )

    # Standardize amounts and fill missing with 0
    merged[DOR_AMOUNT_COL] = merged[DOR_AMOUNT_COL].fillna(0)
    merged[VP_AMOUNT_COL] = merged[VP_AMOUNT_COL].fillna(0)

    # Difference (DOR minus VP)
    merged["Difference"] = merged[DOR_AMOUNT_COL] - merged[VP_AMOUNT_COL]

    return merged


# =========================
# MAIN LOGIC
# =========================

if __name__ == "__main__":
    print(f"Filtering data from {START_DATE} to {END_DATE}\n")

    # Load and clean each source
    dor = load_and_clean_dor(DOR_PATH, START_DATE, END_DATE)
    vp, vp_detail = load_and_clean_vp(VP_PATH, START_DATE, END_DATE)

    # Merge
    merged = merge_and_reconcile(dor, vp)

    # Masks for match status
    matched_mask = merged["_merge"] == "both"
    dor_only_mask = merged["_merge"] == "left_only"
    vp_only_mask = merged["_merge"] == "right_only"

    # DOR-only but exclude certain Program Areas
    dor_only_effective_mask = dor_only_mask & (
        ~merged[DOR_PROGRAM_COL].isin(EXCLUDE_DOR_ONLY_PROGRAMS)
    )

    # Lists for review
    dor_only_ids = merged.loc[dor_only_effective_mask, DOR_ID_COL].dropna().tolist()
    vp_only_ids = merged.loc[vp_only_mask, VP_ID_COL].dropna().tolist()

    print(
        f"{len(dor_only_ids)} DOR Project IDs not in VP (excluding {EXCLUDE_DOR_ONLY_PROGRAMS}):"
    )
    print(dor_only_ids)

    print(f"\n{len(vp_only_ids)} VP Service Line Codes not in DOR:")
    print(vp_only_ids)

    # Totals and overlap
    total_dor = dor[DOR_AMOUNT_COL].sum()
    total_vp = vp[VP_AMOUNT_COL].sum()

    overlap_dor = merged.loc[matched_mask, DOR_AMOUNT_COL].sum()
    overlap_vp = merged.loc[matched_mask, VP_AMOUNT_COL].sum()

    dor_only_total_effective = merged.loc[dor_only_effective_mask, DOR_AMOUNT_COL].sum()
    vp_only_total = merged.loc[vp_only_mask, VP_AMOUNT_COL].sum()

    print("\n===== SUMMARY =====")
    print(f"Total DOR (within date range): {total_dor:,.2f}")
    print(f"Total VP  (within date range): {total_vp:,.2f}\n")

    print(f"Matched DOR amount (overlap): {overlap_dor:,.2f}")
    print(f"Matched VP  amount (overlap): {overlap_vp:,.2f}")
    print(
        f"Difference on matched records (DOR - VP): {(overlap_dor - overlap_vp):,.2f}\n"
    )

    print(
        f"DOR-only (excl. {EXCLUDE_DOR_ONLY_PROGRAMS}): {dor_only_total_effective:,.2f}"
    )
    print(f"VP-only: {vp_only_total:,.2f}")
    print(
        f"Check: (DOR total - overlap_dor - excluded DOR-only) vs (VP total - overlap_vp - VP-only)"
    )
    print("This can help you see if the reconciliation is balanced under your rules.\n")

    # =========================
    # EXPORTS
    # =========================

    # Full merged reconciliation table
    merged.to_csv(MERGED_OUT, index=False)

    # DOR-only export
    merged.loc[
        dor_only_effective_mask,
        [DOR_ID_COL, DOR_TITLE_COL, DOR_AMOUNT_COL, DOR_PROGRAM_COL],
    ].to_csv(DOR_ONLY_OUT, index=False)

    # VP-only export
    merged.loc[
        vp_only_mask,
        [VP_ID_COL, VP_STUDY_CODE_COL, VP_AMOUNT_COL],
    ].to_csv(VP_ONLY_OUT, index=False)

    print(
        f"Exported '{MERGED_OUT}', '{DOR_ONLY_OUT}', and '{VP_ONLY_OUT}' for detailed review."
    )


import pandas as pd

# -----------------------------
# Build a "matched" studies table
# -----------------------------
matched_mask = merged["_merge"] == "both"
matched = merged.loc[matched_mask].copy()

# Add a difference column (DOR - VP)
matched["Difference"] = matched["Total Cash Receipts"] - matched["Transaction Amount"]

# Keep just the key fields for the report
matched_report = matched[
    [
        "Project ID",
        "Project Title",
        "Program Area",
        "Total Cash Receipts",
        "Transaction Amount",
        "Difference",
    ]
].sort_values("Project ID")

# -----------------------------
# Summary table using existing numbers
# -----------------------------

# Ensure variables used below are defined consistently
# total_dor_effective = matched overlap (from DOR) + DOR-only effective (excluding KPOCT/Pedi-Onc)
total_dor_effective = overlap_dor + dor_only_total_effective

# for compatibility with older variable names used lower in the file
overlap = overlap_dor
dor_only_total = dor_only_total_effective
# total_vp already exists as total_vp

summary_rows = [
    {
        "Metric": "Total DOR (effective rule)",
        "Value": total_dor_effective,
    },
    {
        "Metric": "Total VP",
        "Value": total_vp,
    },
    {
        "Metric": "Overlap (DOR side)",
        "Value": overlap,
    },
    {
        "Metric": "DOR-only (excl. KPOCT/Pedi-Onc)",
        "Value": dor_only_total,
    },
    {
        "Metric": "VP-only",
        "Value": merged.loc[
            merged["_merge"] == "right_only", "Transaction Amount"
        ].sum(),
    },
    {
        "Metric": "VP minus overlap",
        "Value": total_vp - overlap,
    },
]

summary_df = pd.DataFrame(summary_rows)

# -----------------------------
# Prepare DOR and VP detail tables
# -----------------------------
dor_detail = dor.copy()
dor_only_detail = merged.loc[
    dor_only_effective_mask,
    [DOR_ID_COL, DOR_TITLE_COL, DOR_AMOUNT_COL, DOR_PROGRAM_COL],
].copy()

# VP detail tables
vp_detail_report = vp_detail[
    [
        "Service Line Code",
        "Site Study Code",
        "Accountable Completed Date",
        "Transaction Amount",
    ]
].copy()
vp_only_detail = merged.loc[
    merged["_merge"] == "right_only",
    [VP_ID_COL, VP_STUDY_CODE_COL, VP_AMOUNT_COL],
].copy()

# -----------------------------
# Write to Excel with interactivity
# -----------------------------
output_file = "reconciliation_report.xlsx"

with pd.ExcelWriter(output_file, engine=EXCEL_ENGINE) as writer:
    # 1. Summary
    summary_df.to_excel(writer, sheet_name="Summary", index=False)

    # 2. Matched studies (for overview + dropdown)
    matched_report.to_excel(writer, sheet_name="Matched_Studies", index=False)

    # 3. DOR detail
    dor_detail.to_excel(writer, sheet_name="DOR_Detail", index=False)

    # 4. VP detail (all transactions)
    vp_detail_report.to_excel(writer, sheet_name="VP_Detail", index=False)

    # 5. Unmatched summaries
    dor_only_detail.to_excel(writer, sheet_name="DOR_Only", index=False)
    vp_only_detail.to_excel(writer, sheet_name="VP_Only", index=False)

print(f"\nExcel report written to: {output_file}")
