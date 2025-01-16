# TODO(Vincent 2024-04-29)
# Add memory and CPU history usage in output.
# Maybe there is a common format for this? Maybe Perfetto.
# Would be nice to have some trace associated with it, to understand which tasks
# are long or memory heavy.


import argparse
from pathlib import Path

import polars as pl

from . import config
from . import stats
from .log import logger


def main():
    # Parse CLI arguments
    args = init_cli()

    logger.info("Hello! Let's compute. =)")

    # Loading, checking, and applying configuration
    parsed_config = config.parse_config(args.config)
    config.validate_io_config(parsed_config)
    runtime_config = config.apply(parsed_config, args.config)

    # Get all OMOP IDs
    all_omop_ids = (
        pl.scan_parquet(runtime_config.kanta_preprocessed_file)
        .select(
            pl.col(runtime_config.kanta_preprocessed_columns.omopid)
            .unique()
            .fill_null("NA")
        )
        .collect()
    )

    all_omop_ids.write_ndjson(runtime_config.stats_dir / "all_omop_ids.jsonl")

    list_omop_ids = all_omop_ids.get_column(
        runtime_config.kanta_preprocessed_columns.omopid
    )

    # Running stats pipeline
    logger.info(f"Computing stats for {len(list_omop_ids)} OMOP Concept IDs")
    stats.pipeline(list_omop_ids=list_omop_ids, runtime_config=runtime_config)
    logger.info(f"Computing stats for {len(list_omop_ids)} OMOP Concept IDs: Done")

    logger.info("Compute done.")


def init_cli():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--config", help="path to configuration file (TOML)", required=True, type=Path
    )

    args = parser.parse_args()

    return args


def find_omop_ids_from_directory(path_directory):
    omop_id_split_paths = path_directory.glob("*.parquet")
    omop_id_split_paths = list(omop_id_split_paths)

    logger.info(f"Found {len(omop_id_split_paths)} split files in {path_directory}")

    return omop_id_split_paths


def get_omop_id_from_path(omop_id_split_file):
    return omop_id_split_file.stem


if __name__ == "__main__":
    main()
