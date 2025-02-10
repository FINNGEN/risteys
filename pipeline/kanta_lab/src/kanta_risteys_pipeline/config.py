import datetime
import logging
import pprint
import shutil
import tempfile
import tomllib
from dataclasses import dataclass
from pathlib import Path

import polars as pl

from .log import ColoredFormatter
from .log import logger


ERROR_FILE_NOT_FOUND = 10
ERROR_FILE_MISSING_COLUMNS = 20


@dataclass(frozen=True)
class ColumnsKantaPreprocessed:
    """Provides dot-access to column names for the Kanta preprocessed input file."""

    personid: str
    omopid: str
    datetime: str
    test_name: str
    meas_unit: str
    meas_unit_harmonized: str
    meas_value_harmonized: str
    test_outcome: str
    reference_range: str


@dataclass(frozen=True)
class ColumnsPhenotype:
    """Provides dot-access to column names for the Phenotype input file."""

    personid: str
    sex: str
    date_of_birth: str
    age_end_follow_up: str


@dataclass(frozen=True)
class RuntimeConfig:
    phenotype_file: Path
    phenotype_columns: ColumnsPhenotype

    kanta_preprocessed_file: Path
    kanta_preprocessed_columns: ColumnsKantaPreprocessed

    run_dir: Path
    stats_dir: Path

    kanta_start_date: pl.Date
    kanta_end_date: pl.Date
    age_dist_start: int
    age_dist_end: int
    age_dist_bin_width: int
    numerical_dist_n_bins: int


def parse_config(config_file):
    with Path(config_file).open("rb") as ff:
        config = tomllib.load(ff)

    config_formatted = pprint.pformat(config)
    logger.debug(f"Configuration used for this run:\n{config_formatted}")

    return config


def validate_io_config(config):
    """Quick checks of input and output set in the configuration"""

    phenotype_file = Path(config["input"]["phenotype"]["file_path"])
    phenotype_columns = config["input"]["phenotype"]["columns"].values()

    kanta_preprocessed_file = Path(config["input"]["kanta_preprocessed"]["file_path"])
    kanta_preprocessed_columns = config["input"]["kanta_preprocessed"][
        "columns"
    ].values()

    base_run_directory = Path(config["output"]["base_run_directory"])

    if not does_file_exist(phenotype_file):
        logger.error(
            f"I am looking for the phenotype file here but cannot find it: {phenotype_file.absolute()}"
        )
        exit(ERROR_FILE_NOT_FOUND)

    if not does_file_has_columns(
        pl.scan_csv(phenotype_file, separator="\t"), phenotype_columns
    ):
        columns = "\n\t".join(phenotype_columns)
        logger.error(
            f"I am looking at the phenotype file {phenotype_file} but could not find some of these columns:\n\t{columns}\n"
        )
        exit(ERROR_FILE_MISSING_COLUMNS)

    if not does_file_exist(kanta_preprocessed_file):
        logger.error(
            f"I am looking for the Kanta preprocessed file here but cannot find it: {kanta_preprocessed_file.absolute()}"
        )
        exit(ERROR_FILE_NOT_FOUND)

    if not does_file_has_columns(
        pl.scan_parquet(kanta_preprocessed_file), kanta_preprocessed_columns
    ):
        columns = "\n\t".join(kanta_preprocessed_columns)
        logger.error(
            f"I am looking at the Kanta preprocessed file {kanta_preprocessed_file} but could not find some of these columns:\n\t{columns}\n"
        )
        exit(ERROR_FILE_MISSING_COLUMNS)

    if not is_directory_writable(base_run_directory):
        logger.error(
            f"I must be able to write to the base run directory here but it is not writable: {base_run_directory.absolute()}"
        )
        exit(ERROR_FILE_NOT_FOUND)

    logger.info("Validate config: Done.")


def does_file_exist(path):
    try:
        path.open()
    except OSError as ee:
        logger.error(ee)
        return False
    else:
        return True


def is_directory_writable(directory):
    try:
        temp = tempfile.NamedTemporaryFile(dir=directory)
    except OSError as ee:
        logger.error(ee)
        return False
    else:
        # Clean up the temporary file. Calling .close() on it will delete it.
        temp.close()
        return True


def does_file_has_columns(dataf, has_columns):
    try:
        dataf.select(has_columns).head(0).collect()
    except pl.exceptions.PolarsError as ee:
        logger.error(ee)
        return False
    else:
        return True


def apply(parsed_config: dict, config_file: Path) -> RuntimeConfig:
    kanta_preprocessed_columns = ColumnsKantaPreprocessed(
        personid=parsed_config["input"]["kanta_preprocessed"]["columns"]["personid"],
        omopid=parsed_config["input"]["kanta_preprocessed"]["columns"]["omopid"],
        datetime=parsed_config["input"]["kanta_preprocessed"]["columns"]["datetime"],
        test_name=parsed_config["input"]["kanta_preprocessed"]["columns"]["test_name"],
        meas_unit=parsed_config["input"]["kanta_preprocessed"]["columns"]["meas_unit"],
        meas_unit_harmonized=parsed_config["input"]["kanta_preprocessed"]["columns"][
            "meas_unit_harmonized"
        ],
        meas_value_harmonized=parsed_config["input"]["kanta_preprocessed"]["columns"][
            "meas_value_harmonized"
        ],
        test_outcome=parsed_config["input"]["kanta_preprocessed"]["columns"][
            "test_outcome"
        ],
        reference_range=parsed_config["input"]["kanta_preprocessed"]["columns"][
            "reference_range"
        ],
    )

    phenotype_columns = ColumnsPhenotype(
        personid=parsed_config["input"]["phenotype"]["columns"]["personid"],
        sex=parsed_config["input"]["phenotype"]["columns"]["sex"],
        date_of_birth=parsed_config["input"]["phenotype"]["columns"]["date_of_birth"],
        age_end_follow_up=parsed_config["input"]["phenotype"]["columns"][
            "age_end_follow_up"
        ],
    )

    # Make directory for current run
    datetime_now = datetime.datetime.now(tz=datetime.timezone.utc).isoformat()

    name = f"run_{datetime_now}"
    run_dir = Path(parsed_config["output"]["base_run_directory"]) / name
    run_dir.mkdir()
    logger.info(f"Using the following run directory:\t{run_dir.absolute()}")

    # Setup an additional logger to a file in the run directory
    log_file = run_dir / "log.txt"
    file_handler = logging.FileHandler(log_file)
    file_handler.setLevel("DEBUG")
    file_handler.setFormatter(ColoredFormatter())
    logger.addHandler(file_handler)

    # Copy over the configuration file
    shutil.copyfile(config_file, run_dir / "config.toml")

    # Make the necessary sub-directories
    stats_dir = run_dir / "stats"
    stats_dir.mkdir()

    runtime_config = RuntimeConfig(
        phenotype_file=Path(parsed_config["input"]["phenotype"]["file_path"]),
        phenotype_columns=phenotype_columns,
        kanta_preprocessed_file=Path(
            parsed_config["input"]["kanta_preprocessed"]["file_path"]
        ),
        kanta_preprocessed_columns=kanta_preprocessed_columns,
        run_dir=run_dir,
        stats_dir=stats_dir,
        kanta_start_date=parsed_config["pipeline"]["stats"][
            "kanta_registry_span_dates"
        ][0],
        kanta_end_date=parsed_config["pipeline"]["stats"]["kanta_registry_span_dates"][
            1
        ],
        age_dist_start=parsed_config["pipeline"]["stats"]["age_dist_x_axis"][0],
        age_dist_end=parsed_config["pipeline"]["stats"]["age_dist_x_axis"][1],
        age_dist_bin_width=parsed_config["pipeline"]["stats"]["age_dist_bin_width"],
        numerical_dist_n_bins=parsed_config["pipeline"]["stats"][
            "numerical_dist_n_bins"
        ],
    )

    return runtime_config
