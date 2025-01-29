# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "fastexcel==0.12.1",
#     "polars==1.21.0",
#     "xlsxwriter==3.2.2"
# ]
# ///


# Combine Kanta lab reference ranges into an Excel spreadsheet ready for curation.
#
# Source of reference ranges:
# - FinnGen Kanta lab red data
# - HUS lab sheet
# - FinnGen Kanta lab imputed test outcomes
#
#
# Usage:
#   uv run --no-project kanta_lab_ref_ranges_table_combine <OPTIONS>
#
#   options:
#     -h, --help            show this help message and exit
#     --input-fg-kanta-lab INPUT_FG_KANTA_LAB
#                           Path to the FinnGen Kanta lab values dataset (.parquet, FinnGen red data).
#     --input-hus-labsheet INPUT_HUS_LABSHEET
#                           Path to the HUS lab sheet (.xlsx, from https://huslab.fi/ohjekirja/).
#     --input-fg-omop-mapping INPUT_FG_OMOP_MAPPING
#                           Path to the FinnGen Kanta lab OMOP mapping (.csv, from
#                           https://github.com/FINNGEN/kanta_lab_harmonisation_public/blob/main/MAPPING_TABLES/LABfi_ALL.usagi.csv)
#     --input-fg-imputed INPUT_FG_IMPUTED
#                           Path to the test outcome imputation table (.csv, from Pietro's imputation)
#     --output OUTPUT       Output path (.xlsx).

import argparse
from pathlib import Path

import polars as pl
import xlsxwriter


def main() -> None:
    args = cli_init()

    dataf_fg_kanta_lab = (
        read_fg_kanta_lab(args.input_fg_kanta_lab)
        .rename(lambda col_name: f"FG_KANTA_DATA:{col_name}")
        .rename({"FG_KANTA_DATA:OMOP_CONCEPT_ID": "OMOPConceptId"})
        .with_columns(pl.lit("FG_KANTA_DATA").alias("Source"))
        .filter(pl.col("FG_KANTA_DATA:NPeople") >= 5)
    )

    dataf_omop_mapping = read_omop_mapping(args.input_fg_omop_mapping)

    dataf_hus = (
        read_hus_excel(args.input_hus_labsheet)
        .pipe(clean_hus_name_abbreviations)
        .pipe(extract_hus_reference_ranges)
        .rename(lambda col_name: f"HUS:{col_name}")
        .with_columns(pl.lit("HUS").alias("Source"))
        .join(dataf_omop_mapping, left_on="HUS:Abbreviation", right_on="Abbreviation")
        .drop("HUS:Abbreviation")
        .unique(maintain_order=True)
    )

    dataf_fg_imputed = (
        read_fg_imputed(args.input_fg_imputed)
        .rename(lambda col_name: f"FG_KANTA_IMPUTED:{col_name}")
        .rename({"FG_KANTA_IMPUTED:ID": "OMOPConceptId"})
        .with_columns(pl.lit("FG_KANTA_IMPUTED").alias("Source"))
    )

    dataf_out = (
        pl.concat([dataf_fg_kanta_lab, dataf_fg_imputed, dataf_hus], how="diagonal")
        .sort(
            "OMOPConceptId",
            "Source",
            "FG_KANTA_DATA:NPeople",
            descending=[False, False, True],
            maintain_order=True
        )
        .select(
            (pl.col("OMOPConceptId").rank("dense").cast(pl.Int64) % 2).alias("BG"),
            pl.col("OMOPConceptId"),
            pl.col("Source"),
            pl.selectors.exclude("OMOPConceptId", "Source"),
        )
    )

    write_excel(dataf_out, args.output)


def cli_init():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--input-fg-kanta-lab",
        type=Path,
        required=True,
        help="Path to the FinnGen Kanta lab values dataset (.parquet, FinnGen red data).",
    )

    parser.add_argument(
        "--input-hus-labsheet",
        type=Path,
        required=True,
        help="Path to the HUS lab sheet (.xlsx, from https://huslab.fi/ohjekirja/).",
    )

    parser.add_argument(
        "--input-fg-omop-mapping",
        type=Path,
        required=True,
        help="Path to the FinnGen Kanta lab OMOP mapping (.csv, from https://github.com/FINNGEN/kanta_lab_harmonisation_public/blob/main/MAPPING_TABLES/LABfi_ALL.usagi.csv)",
    )

    parser.add_argument(
        "--input-fg-imputed",
        type=Path,
        required=True,
        help="Path to the test outcome imputation table (.csv, from Pietro's imputation)",
    )

    parser.add_argument(
        "--output", type=Path, required=True, help="Output path (.xlsx)."
    )

    args = parser.parse_args()
    return args


def read_fg_kanta_lab(filepath: Path):
    return (
        pl.scan_parquet(filepath)
        .filter(pl.col("OMOP_CONCEPT_ID").is_not_null())
        .group_by("OMOP_CONCEPT_ID", "REFERENCE_RANGE_GROUP")
        .agg(pl.col("FINNGENID").n_unique().alias("NPeople"), pl.len().alias("NRows"))
        .collect()
    )


def read_hus_excel(filepath: Path):
    return (
        pl.read_excel(filepath)
        .select(
            pl.col("Lyhenne").alias("Abbreviation"),
            pl.col("Viitearvot").alias("ReferenceRanges"),
        )
        .filter(
            pl.col("ReferenceRanges").str.starts_with("[")
            & pl.col("ReferenceRanges").str.ends_with("]")
        )
        .filter(pl.col("ReferenceRanges") != "[]")
    )


def clean_hus_name_abbreviations(dataf):
    # Based on cleaning made for OMOP mapping in:
    # https://github.com/FINNGEN/kanta_lab_preprocessing/blob/ad359b1e8c99874a3ce272c43666b98158c58ed1/finngen_qc/magic_config.py#L149-L155
    # https://github.com/FINNGEN/kanta_lab_preprocessing/blob/ad359b1e8c99874a3ce272c43666b98158c58ed1/finngen_qc/filters/filter_minimal.py#L89
    return dataf.with_columns(
        pl.col("Abbreviation")
        .str.replace_many(
            {
                " ": "",
                "_": "",
                "\u2013": "",
                "*": "",
                "#": "",
                "%": "",
            }
        )
        .str.to_lowercase()
    )


def extract_hus_reference_ranges(dataf):
    return (
        dataf.with_columns(pl.col("ReferenceRanges").str.json_decode())
        .explode("ReferenceRanges")
        .with_columns(
            pl.col("ReferenceRanges").struct.field("name"),
            pl.col("ReferenceRanges").struct.field("age"),
            pl.col("ReferenceRanges").struct.field("gender"),
            pl.col("ReferenceRanges")
            .struct.field("defaultMethodRange")
            .struct.field("value"),
            pl.col("ReferenceRanges")
            .struct.field("defaultMethodRange")
            .struct.field("method"),
        )
        .drop("ReferenceRanges")
    )


def read_omop_mapping(filepath):
    return (
        pl.read_csv(filepath, infer_schema_length=0)
        .select(
            pl.col("ADD_INFO:testNameAbbreviation").alias("Abbreviation"),
            pl.col("conceptId").alias("OMOPConceptId"),
        )
        .filter(pl.col("OMOPConceptId") != "0")
    )


def read_fg_imputed(filepath: Path):
    return pl.read_csv(filepath, infer_schema_length=0, null_values=["NA"])


def write_excel(dataf, output_path):
    workbook = xlsxwriter.Workbook(output_path)
    bg_blue = workbook.add_format({"bg_color": "#d0deed"})

    format_range = f"A1:N{dataf.height + 1}"
    worksheet = workbook.add_worksheet()
    worksheet.conditional_format(
        format_range, {"type": "formula", "criteria": "=$A1=1", "format": bg_blue}
    )

    dataf.write_excel(
        workbook=workbook,
        worksheet=worksheet,
        header_format={"bold": True},
        sheet_zoom=125,
        autofit=True,
        hidden_columns=["BG", "OMOPConceptId"],
        formulas={
            "Risteys / OMOP ID": {
                "formula": '=HYPERLINK(CONCAT("https://risteys.finngen.fi/lab-tests/", [@OMOPConceptId]), [@OMOPConceptId])',
                "insert_before": "OMOPConceptId",
            }
        },
    )

    workbook.close()


if __name__ == "__main__":
    main()
