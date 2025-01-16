import numpy as np
import polars as pl

from .log import logger


# Polars provides a .total_days() but not a .total_years(),
# so we use this constant to convert X days to Y years.
DAYS_IN_A_YEAR = 365.25

MIN_N_FOR_GREEN_DATA = 5


def pipeline(*, list_omop_ids, runtime_config):
    logger.info("Running stats pipeline")

    compute_n_people_alive(
        kanta_path=runtime_config.kanta_preprocessed_file,
        kanta_cols=runtime_config.kanta_preprocessed_columns,
        pheno_path=runtime_config.phenotype_file,
        pheno_cols=runtime_config.phenotype_columns,
        kanta_start_date=runtime_config.kanta_start_date,
        output_dir=runtime_config.stats_dir,
    )

    compute_n_people_median_n_measurements(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        output_dir=runtime_config.stats_dir,
    )

    compute_percentage_people_two_or_more_records(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        output_dir=runtime_config.stats_dir,
    )

    compute_median_duration_first_to_last(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        output_dir=runtime_config.stats_dir,
    )

    compute_count_by_sex(
        list_omop_ids=list_omop_ids,
        kanta_path=runtime_config.kanta_preprocessed_file,
        cols_kanta=runtime_config.kanta_preprocessed_columns,
        pheno_path=runtime_config.phenotype_file,
        cols_pheno=runtime_config.phenotype_columns,
        output_dir=runtime_config.stats_dir,
    )

    compute_qc_tables(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        output_dir=runtime_config.stats_dir,
    )

    compute_qc_tables_value_distributions(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        output_dir=runtime_config.stats_dir,
    )

    compute_qc_tables_test_outcome_counts(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        output_dir=runtime_config.stats_dir,
    )

    compute_dist_value_range(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        dist_n_bins=runtime_config.numerical_dist_n_bins,
        output_dir=runtime_config.stats_dir,
    )

    compute_dist_year_birth(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        kanta_cols=runtime_config.kanta_preprocessed_columns,
        kanta_end_date=runtime_config.kanta_end_date,
        pheno_path=runtime_config.phenotype_file,
        pheno_cols=runtime_config.phenotype_columns,
        output_dir=runtime_config.stats_dir,
    )

    compute_dist_duration_first_to_last(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        dist_n_bins=runtime_config.numerical_dist_n_bins,
        output_dir=runtime_config.stats_dir,
    )

    compute_dists_age(
        list_omop_ids=list_omop_ids,
        kanta_path=runtime_config.kanta_preprocessed_file,
        kanta_cols=runtime_config.kanta_preprocessed_columns,
        pheno_path=runtime_config.phenotype_file,
        pheno_cols=runtime_config.phenotype_columns,
        kanta_start_date=runtime_config.kanta_start_date,
        age_min=runtime_config.age_dist_start,
        age_max=runtime_config.age_dist_end,
        bin_width=runtime_config.age_dist_bin_width,
        output_dir=runtime_config.stats_dir,
    )

    compute_dist_lab_values(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        dist_n_bins=runtime_config.numerical_dist_n_bins,
        output_dir=runtime_config.stats_dir,
    )

    compute_dist_n_measurements_over_years(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        kanta_start_date=runtime_config.kanta_start_date,
        kanta_end_date=runtime_config.kanta_end_date,
        output_dir=runtime_config.stats_dir,
    )

    compute_dist_n_records_measurements_per_person(
        list_omop_ids=list_omop_ids,
        data_path=runtime_config.kanta_preprocessed_file,
        cols=runtime_config.kanta_preprocessed_columns,
        output_dir=runtime_config.stats_dir,
    )

    logger.info("Running stats pipeline: Done")


def compute_n_people_alive(
    kanta_path, kanta_cols, pheno_path, pheno_cols, kanta_start_date, output_dir
):
    logger.info("Computing N people alive at some point during the Kanta lab registry")

    lazyf_age_end_follow_up = (
        pl.scan_csv(pheno_path, separator="\t")
        .cast(
            {
                pheno_cols.personid: pl.String,
                pheno_cols.date_of_birth: pl.Date,
                pheno_cols.age_end_follow_up: pl.Float64,
            }
        )
        .with_columns(
            pl.duration(
                days=DAYS_IN_A_YEAR * pl.col(pheno_cols.age_end_follow_up)
            ).alias("DurationToEndFollowUp")
        )
        .with_columns(
            (pl.col(pheno_cols.date_of_birth) + pl.col("DurationToEndFollowUp")).alias(
                "DateEndFollowUp"
            )
        )
    )

    (
        pl.scan_parquet(kanta_path)
        .join(
            lazyf_age_end_follow_up,
            how="inner",
            left_on=kanta_cols.personid,
            right_on=pheno_cols.personid,
        )
        .filter(pl.col("DateEndFollowUp") >= kanta_start_date)
        .select(pl.col(kanta_cols.personid).n_unique().alias("NPeople"))
        .pipe(keep_green, column_n_people="NPeople")
        .collect()
        .write_ndjson(output_dir / "n_people_alive_in_kanta_time.jsonl")
    )

    logger.info(
        "Computing N people alive at some point during the Kanta lab registry: Done"
    )


def compute_n_people_median_n_measurements(
    *, list_omop_ids, data_path, cols, output_dir
):
    logger.info("Computing N people, and Median(N measurements / person)")

    output_path = output_dir / "median_n_measurements.jsonl"

    (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .group_by([cols.omopid, cols.personid])
        .agg(pl.col(cols.personid).count().alias("CountPerPerson"))
        .group_by(cols.omopid)
        .agg(
            pl.col("CountPerPerson").median().alias("MedianNMeasurementsPerPerson"),
            pl.col(cols.personid).n_unique().alias("NPeople"),
        )
        .pipe(keep_green, column_n_people="NPeople")
        .collect()
    ).write_ndjson(output_path)

    logger.info("Computing N people, and Median(N measurements / person): Done")


def compute_percentage_people_two_or_more_records(
    *, list_omop_ids, data_path, cols, output_dir
):
    logger.info("Computing percentage of people with 2 or more records")

    output_path = output_dir / "percent_people_two_or_more_records.jsonl"

    (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .group_by([cols.omopid, cols.personid])
        .agg(pl.col(cols.personid).count().alias("CountPerPerson"))
        .group_by(cols.omopid)
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            (pl.col("CountPerPerson") >= 2).sum().alias("NPeopleWithTwoOrMoreRecords"),
        )
        .with_columns(
            (100 * pl.col("NPeopleWithTwoOrMoreRecords") / pl.col("NPeople")).alias(
                "PercentagePeopleWithTwoOrMoreRecords"
            )
        )
        .select(
            [
                pl.col(cols.omopid),
                pl.col("PercentagePeopleWithTwoOrMoreRecords"),
                pl.col("NPeople"),
            ]
        )
        .pipe(keep_green, column_n_people="NPeople")
        .collect()
    ).write_ndjson(output_path)

    logger.info("Computing percentage of people with 2 or more records: Done")


def compute_median_duration_first_to_last(
    *, list_omop_ids, data_path, cols, output_dir
):
    logger.info("Computing Median(duration from first to last record / person)")

    output_path = output_dir / "median_duration_first_to_last_record.jsonl"

    # Minimum number of records per person, to filter people with only 1 record.
    min_count_per_person = 2

    (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .group_by([cols.omopid, cols.personid])
        .agg(
            pl.col(cols.personid).count().alias("CountPerPerson"),
            (pl.col(cols.datetime).max() - pl.col(cols.datetime).min())
            .dt.total_days()
            .alias("DurationDaysFirstToLast"),
        )
        .filter(pl.col("CountPerPerson") >= min_count_per_person)
        .group_by(cols.omopid)
        .agg(
            (pl.col("DurationDaysFirstToLast").median() / DAYS_IN_A_YEAR).alias(
                "MedianDurationYearsFirstToLast"
            ),
            pl.col(cols.personid).n_unique().alias("NPeople"),
        )
        .pipe(keep_green, column_n_people="NPeople")
        .collect()
    ).write_ndjson(output_path)

    logger.info("Computing Median(duration from first to last record / person): Done")


def compute_count_by_sex(
    *, list_omop_ids, kanta_path, cols_kanta, pheno_path, cols_pheno, output_dir
):
    logger.info("Computing count by sex")

    output_path = output_dir / "count_by_sex.jsonl"

    sex_code_male = "male"
    sex_code_female = "female"

    df_sex = pl.scan_csv(pheno_path, separator="\t").cast(
        {cols_pheno.personid: pl.String, cols_pheno.sex: pl.String}
    )

    (
        pl.scan_parquet(kanta_path)
        .filter(pl.col(cols_kanta.omopid).is_in(list_omop_ids))
        .join(
            df_sex,
            left_on=cols_kanta.personid,
            right_on=cols_pheno.personid,
            how="left",
        )
        .group_by([cols_kanta.omopid, cols_kanta.personid])
        .agg(pl.col(cols_pheno.sex).first().alias("SexCode"))
        .with_columns(
            pl.when(pl.col("SexCode") == sex_code_male)
            .then(pl.lit("male"))
            .when(pl.col("SexCode") == sex_code_female)
            .then(pl.lit("female"))
            .otherwise(pl.lit("unknown"))
            .alias("Sex")
        )
        .group_by(cols_kanta.omopid, "Sex")
        .agg(pl.col("Sex").count().alias("NPeople"))
        .pipe(keep_green, column_n_people="NPeople")
        .collect()
    ).write_ndjson(output_path)

    logger.info("Computing count by sex: Done")


def compute_qc_tables(*, list_omop_ids, data_path, cols, output_dir):
    logger.info("Computing QC tables")

    output_path = output_dir / "qc_tables.jsonl"

    (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .group_by(
            [
                pl.col(cols.omopid),
                pl.col(cols.test_name),
                pl.col(cols.meas_unit),
                pl.col(cols.meas_unit_harmonized),
            ]
        )
        .agg(
            pl.col(cols.omopid).count().alias("NRecords"),
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.col(cols.meas_value_harmonized)
            .is_null()
            .sum()
            .alias("NMissingMeasurementValue"),
        )
        .select(
            pl.col(cols.omopid),
            pl.col(cols.test_name),
            pl.col(cols.meas_unit),
            pl.col(cols.meas_unit_harmonized),
            pl.col("NRecords"),
            pl.col("NPeople"),
            (100 * pl.col("NMissingMeasurementValue") / pl.col("NRecords")).alias(
                "PercentMissingMeasurementValue"
            ),
        )
        .pipe(keep_green, column_n_people="NPeople")
        .collect()
    ).write_ndjson(output_path)

    logger.info("Computing QC tables: Done.")


def compute_qc_tables_value_distributions(
    *, list_omop_ids, data_path, cols, output_dir
):
    logger.info("Computing measurement value distributions for QC tables")

    output_path_stats = (
        output_dir / "qc_tables__distribution_measurement_value__stats.jsonl"
    )
    output_path_bins_definitions = (
        output_dir / "qc_tables__distribution_measurement_value__bins_definitions.jsonl"
    )

    # Parameters for the sub distributions
    n_bins = 20
    left_closed_bins = False

    # NOTE(Vincent 2024-11-01)
    # Each distribution is per {OMOP ID, test name, meas unit}, so we will
    # compute the counts with this `counts_by` key. But we want all of
    # these distributions to share the same binning and x-axis per OMOP ID,
    # so `binning_by` is only OMOP ID.
    # I add the harmonized unit to `binning_by` just to have it in the
    # output as it makes things simpler when plotting, but that doesn't
    # affect the computations since 1 OMOP ID has only 1 harmonized unit.
    counts_by = [cols.omopid, cols.test_name, cols.meas_unit]
    binning_by = [cols.omopid, cols.meas_unit_harmonized]

    dataf = (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .filter(~pl.col(cols.meas_value_harmonized).is_null())
        .with_columns(
            pl.col(cols.meas_unit_harmonized)
            .len()
            .over(counts_by)
            .alias("NRecordsNotNull"),
            pl.col(cols.personid)
            .n_unique()
            .over(counts_by)
            .alias("NPeopleTotalInDist"),
        )
        .pipe(keep_green, column_n_people="NPeopleTotalInDist")
    )

    with_bins, bins_definitions = binning_soft_mad(
        dataf,
        column_values=cols.meas_value_harmonized,
        partition_by=binning_by,
        n_bins=n_bins,
        left_closed=left_closed_bins,
    )

    binned = (
        with_bins.group_by(counts_by + ["BinIndex"])
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    binned.collect().write_ndjson(output_path_stats)
    bins_definitions.collect().write_ndjson(output_path_bins_definitions)

    logger.info("Computing measurement value distributions for QC tables: Done")


def compute_qc_tables_test_outcome_counts(list_omop_ids, data_path, cols, output_dir):
    logger.info("Computing test outcome counts")

    output_path = output_dir / "qc_tables__test_outcome_counts.jsonl"

    (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .group_by(
            pl.col(cols.omopid),
            pl.col(cols.test_name),
            pl.col(cols.meas_unit),
            pl.col(cols.test_outcome),
        )
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("TestOutcomeCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
        .collect()
    ).write_ndjson(output_path)

    logger.info("Computing test outcome counts: Done")


def compute_dist_value_range(
    *, list_omop_ids, data_path, cols, dist_n_bins, output_dir
):
    logger.info("Computing value range distributions")

    output_path_stats = output_dir / "value_range_distributions__stats.jsonl"
    output_path_bins_definitions = (
        output_dir / "value_range_distributions__bins_definitions.jsonl"
    )

    left_closed_bins = False

    # Have at least 2 measurements to compute the lab variability, otherwise we just
    # have a giant spike at 0.
    min_n_measurements = 2

    dataf = (
        pl.scan_parquet(data_path)
        .filter(
            (pl.col(cols.omopid).is_in(list_omop_ids))
            & ~pl.col(cols.meas_value_harmonized).is_null()
        )
        .group_by(
            pl.col(cols.omopid),
            pl.col(cols.personid),
            pl.col(cols.meas_unit_harmonized),
        )
        .agg(
            (
                pl.col(cols.meas_value_harmonized).max()
                - pl.col(cols.meas_value_harmonized).min()
            ).alias("ValueRange"),
            pl.len().alias("NMeasurements"),
        )
        .filter(pl.col("NMeasurements") >= min_n_measurements)
    )

    with_bins, bins_definitions = binning_soft_mad(
        dataf,
        column_values="ValueRange",
        partition_by=[cols.omopid, cols.meas_unit_harmonized],
        n_bins=dist_n_bins,
        left_closed=left_closed_bins,
    )

    binned = (
        with_bins.group_by(
            pl.col(cols.omopid), pl.col(cols.meas_unit_harmonized), pl.col("BinIndex")
        )
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    binned.collect().write_ndjson(output_path_stats)
    bins_definitions.collect().write_ndjson(output_path_bins_definitions)

    logger.info("Computing value range distributions: Done")


def compute_dist_year_birth(
    *,
    list_omop_ids,
    data_path,
    kanta_cols,
    kanta_end_date,
    pheno_path,
    pheno_cols,
    output_dir,
):
    logger.info("Computing year of birth distribution")

    output_path_stats = output_dir / "year_of_birth_distribution__stats.jsonl"
    output_path_bins_definitions = (
        output_dir / "year_of_birth_distribution__bins_definitions.jsonl"
    )

    lazy_dataf_yob = (
        pl.scan_csv(pheno_path, separator="\t")
        .cast({pheno_cols.personid: pl.String, pheno_cols.date_of_birth: pl.Date})
        .select(
            pl.col(pheno_cols.personid),
            pl.col(pheno_cols.date_of_birth).dt.year().alias("YearOfBirth"),
        )
    )

    # Using the same bins for all OMOP IDs, makes it easier to visually compare them.
    year_start = 1900
    year_end = kanta_end_date.year
    bin_size = 2  # in years
    year_breaks = list(range(year_start, year_end + 1, bin_size))
    break_min = year_breaks[0]
    break_max = year_breaks[-1]
    n_bins = len(year_breaks) - 1
    left_closed_bins = True

    dataf = (
        pl.scan_parquet(data_path)
        .filter(pl.col(kanta_cols.omopid).is_in(list_omop_ids))
        .select(pl.col(kanta_cols.omopid), pl.col(kanta_cols.personid))
        .unique()
        .join(
            lazy_dataf_yob,
            how="left",
            left_on=kanta_cols.personid,
            right_on=pheno_cols.personid,
        )
        # Rescale the YearOfBirh to the BinIndex scale
        # NOTE(Vincent 2024-10-14) The binning here assumes *left-closed* bins.
        .pipe(
            binning_n_equi_bins,
            n_bins=n_bins,
            break_min=break_min,
            break_max=break_max,
            col_values="YearOfBirth",
            left_closed=left_closed_bins,
        )
        .group_by(pl.col(kanta_cols.omopid), pl.col("BinIndex"))
        .agg(
            pl.col(kanta_cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    bin_definitions = (
        dataf.select(pl.col(kanta_cols.omopid).unique())
        .pipe(
            with_bins_definitions,
            n_bins=n_bins,
            break_min=break_min,
            break_max=break_max,
            left_closed=left_closed_bins,
        )
        .with_columns(
            pl.when(pl.col("BinX1") == float("-inf"))
            .then(pl.lit("−∞"))
            .otherwise(pl.col("BinX1").cast(pl.UInt32, strict=False).cast(pl.Utf8))
            .alias("BinLabelX1"),
            pl.when(pl.col("BinX2") == float("+inf"))
            .then(pl.lit("+∞"))
            .otherwise(pl.col("BinX2").cast(pl.UInt32, strict=False).cast(pl.Utf8))
            .alias("BinLabelX2"),
        )
        .with_columns(
            # NOTE(Vincent 2024-10-14)  This assumes left-closed bins.
            pl.format("[{}, {})", pl.col("BinLabelX1"), pl.col("BinLabelX2")).alias(
                "BinLabel"
            )
        )
    )

    dataf.collect().write_ndjson(output_path_stats)
    bin_definitions.collect().write_ndjson(output_path_bins_definitions)

    logger.info("Computing year of birth distribution: Done")


def compute_dist_duration_first_to_last(
    *, list_omop_ids, data_path, cols, dist_n_bins, output_dir
):
    logger.info("Computing duration from first to last measurement")

    output_path_stats = output_dir / "duration_first_to_last_distribution__stats.jsonl"
    output_path_bins_definitions = (
        output_dir / "duration_first_to_last_distribution__bins_definitions.jsonl"
    )

    left_closed_bins = False

    # Only include people with 2 or more measurements
    min_records = 2

    dataf = (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .group_by(cols.omopid, cols.personid)
        .agg(
            (
                (
                    (
                        pl.col(cols.datetime).max() - pl.col(cols.datetime).min()
                    ).dt.total_days()
                    / DAYS_IN_A_YEAR
                ).alias("DurationFirstToLast")
            ),
            pl.len().alias("CountRecords"),
        )
        .filter(pl.col("CountRecords") >= min_records)
    )

    with_bins, bins_definitions = binning_soft_mad(
        dataf,
        column_values="DurationFirstToLast",
        partition_by=[cols.omopid],
        n_bins=dist_n_bins,
        left_closed=left_closed_bins,
    )

    binned = (
        with_bins.group_by(pl.col(cols.omopid), pl.col("BinIndex"))
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    binned.collect().write_ndjson(output_path_stats)
    bins_definitions.collect().write_ndjson(output_path_bins_definitions)

    logger.info("Computing duration from first to last measurement: Done")


# TODO(Vincent 2024-10-14)  The binning used in this function should be
# refactored together with the same code used as the dist YOB.
#
# Basically we want 2 ways to do binning:
# 1. Provide N bins, and use the MAD to define the bin range and the breaks
# 2. Provide the breaks, and that's it.
#
# In both cases we want to output:
# a) a dataframe of stats with BinIndex and BinCount columns
# b) a dataframe of bin index -> bin definitions
def compute_dists_age(
    *,
    list_omop_ids,
    kanta_path,
    kanta_cols,
    pheno_path,
    pheno_cols,
    kanta_start_date,
    age_min,
    age_max,
    bin_width,
    output_dir,
):
    logger.info("Computing age distributions (first meas, last meas, registry start)")

    output_path_age_first_meas_stats = (
        output_dir / "age_first_meas_distribution__stats.jsonl"
    )
    output_path_age_last_meas_stats = (
        output_dir / "age_last_meas_distribution__stats.jsonl"
    )
    output_path_age_registry_starts_stats = (
        output_dir / "age_registry_starts_distribution__stats.jsonl"
    )

    output_path_age_bins_definitions = (
        output_dir / "age_distributions__bins_definitions.jsonl"
    )

    lazy_dataf_yob = (
        pl.scan_csv(pheno_path, separator="\t")
        .cast({pheno_cols.personid: pl.String, pheno_cols.date_of_birth: pl.Date})
        .select(
            pl.col(pheno_cols.personid),
            pl.col(pheno_cols.date_of_birth),
        )
    )

    # Using the same binning for all OMOP IDs and all 3 plots.
    breaks = list(range(age_min, age_max + 1, bin_width))
    break_min = breaks[0]
    break_max = breaks[-1]
    left_closed_bins = True
    n_bins = len(breaks) - 1

    dataf = (
        pl.scan_parquet(kanta_path)
        .filter(pl.col(kanta_cols.omopid).is_in(list_omop_ids))
        .with_columns(pl.col(kanta_cols.datetime).dt.date().alias("LabDate"))
        .group_by(kanta_cols.omopid, kanta_cols.personid)
        .agg(
            pl.col("LabDate").min().alias("DateFirstMeasurement"),
            pl.col("LabDate").max().alias("DateLastMeasurement"),
        )
        .join(
            lazy_dataf_yob,
            how="left",
            left_on=kanta_cols.personid,
            right_on=pheno_cols.personid,
        )
        .with_columns(
            (
                (
                    pl.col("DateFirstMeasurement") - pl.col(pheno_cols.date_of_birth)
                ).dt.total_days()
                / DAYS_IN_A_YEAR
            ).alias("AgeAtFirstMeasurement"),
            (
                (
                    pl.col("DateLastMeasurement") - pl.col(pheno_cols.date_of_birth)
                ).dt.total_days()
                / DAYS_IN_A_YEAR
            ).alias("AgeAtLastMeasurement"),
            (
                (kanta_start_date - pl.col(pheno_cols.date_of_birth)).dt.total_days()
                / DAYS_IN_A_YEAR
            ).alias("AgeAtRegistryStart"),
        )
    )

    binned_age_first_measurement = (
        dataf.pipe(
            binning_n_equi_bins,
            n_bins=n_bins,
            break_min=break_min,
            break_max=break_max,
            col_values="AgeAtFirstMeasurement",
            left_closed=left_closed_bins,
        )
        .group_by(pl.col(kanta_cols.omopid), pl.col("BinIndex"))
        .agg(
            pl.col(kanta_cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    binned_age_last_measurement = (
        dataf.pipe(
            binning_n_equi_bins,
            n_bins=n_bins,
            break_min=break_min,
            break_max=break_max,
            col_values="AgeAtLastMeasurement",
            left_closed=left_closed_bins,
        )
        .group_by(pl.col(kanta_cols.omopid), pl.col("BinIndex"))
        .agg(
            pl.col(kanta_cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    binned_age_registry_start = (
        dataf.pipe(
            binning_n_equi_bins,
            n_bins=n_bins,
            break_min=break_min,
            break_max=break_max,
            col_values="AgeAtRegistryStart",
            left_closed=left_closed_bins,
        )
        .group_by(pl.col(kanta_cols.omopid), pl.col("BinIndex"))
        .agg(
            pl.col(kanta_cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    bins_definitions = (
        dataf.select(pl.col(kanta_cols.omopid).unique())
        .pipe(
            with_bins_definitions,
            n_bins=n_bins,
            break_min=break_min,
            break_max=break_max,
            left_closed=left_closed_bins,
        )
        .with_columns(
            pl.when(pl.col("BinX1") == float("-inf"))
            .then(pl.lit("−∞"))
            .otherwise(pl.col("BinX1").cast(pl.Int32, strict=False).cast(pl.Utf8))
            .alias("BinLabelX1"),
            pl.when(pl.col("BinX2") == float("+inf"))
            .then(pl.lit("+∞"))
            .otherwise(pl.col("BinX2").cast(pl.Int32, strict=False).cast(pl.Utf8))
            .alias("BinLabelX2"),
        )
        .with_columns(
            # NOTE(Vincent 2024-10-14)  This assumes left-closed bins.
            pl.format("[{}, {})", pl.col("BinLabelX1"), pl.col("BinLabelX2")).alias(
                "BinLabel"
            )
        )
    )

    binned_age_first_measurement.collect().write_ndjson(
        output_path_age_first_meas_stats
    )
    binned_age_last_measurement.collect().write_ndjson(output_path_age_last_meas_stats)
    binned_age_registry_start.collect().write_ndjson(
        output_path_age_registry_starts_stats
    )

    bins_definitions.collect().write_ndjson(output_path_age_bins_definitions)

    logger.info("Computing age distributions: Done")


def compute_dist_lab_values(*, list_omop_ids, data_path, cols, dist_n_bins, output_dir):
    logger.info("Computing distribution of lab values")

    output_path_discrete_stats = (
        output_dir / "measurement_discrete_value_harmonized_distribution__stats.jsonl"
    )

    output_path_continuous_stats = (
        output_dir / "measurement_continuous_value_harmonized_distribution__stats.jsonl"
    )
    output_path_continuous_bins_definitions = (
        output_dir
        / "measurement_continuous_value_harmonized_distribution__bins_definitions.jsonl"
    )

    left_closed_bins = False

    dataf = (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .filter(~pl.col(cols.meas_value_harmonized).is_null())
    )

    # I will process the lab values differently wether they are discrete or
    # continuous. If they are discrete, then a bin will be single scalar.
    # Otherwise if they are continuous then a bin will be a half-closed range
    # between two values.
    # "titre" indicates discrete measurement values.
    discrete_units = ["titre"]

    # Discrete measurement values
    binned_discrete = (
        dataf.filter(pl.col(cols.meas_unit_harmonized).is_in(discrete_units))
        .group_by(
            pl.col(cols.omopid),
            pl.col(cols.meas_unit_harmonized),
            pl.col(cols.meas_value_harmonized),
        )
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    # Continuous measurement values
    dataf_continuous = dataf.filter(
        ~pl.col(cols.meas_unit_harmonized).is_in(discrete_units)
    )

    with_bins_continuous, bins_definitions_continuous = binning_soft_mad(
        dataf_continuous,
        column_values=cols.meas_value_harmonized,
        partition_by=[cols.omopid, cols.meas_unit_harmonized],
        n_bins=dist_n_bins,
        left_closed=left_closed_bins,
    )

    binned_continuous = (
        with_bins_continuous.group_by(
            pl.col(cols.omopid), pl.col(cols.meas_unit_harmonized), pl.col("BinIndex")
        )
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    binned_discrete.collect().write_ndjson(output_path_discrete_stats)

    binned_continuous.collect().write_ndjson(output_path_continuous_stats)
    bins_definitions_continuous.collect().write_ndjson(
        output_path_continuous_bins_definitions
    )

    logger.info("Computing distribution of lab values: Done")


def compute_dist_n_measurements_over_years(
    *, list_omop_ids, data_path, cols, kanta_start_date, kanta_end_date, output_dir
):
    logger.info("Computing N measurements over time distribution")

    output_path_stats = (
        output_dir / "n_measurements_over_years_distribution__stats.jsonl"
    )
    output_path_bins_definitions = (
        output_dir / "n_measurements_over_years_distribution__bins_definitions.jsonl"
    )

    # Generate Year-Month bins
    left_closed_bins = True
    interval = "1mo"
    (
        pl.LazyFrame(
            {
                "BinX1": pl.date_range(
                    kanta_start_date,
                    kanta_end_date,
                    interval=interval,
                    eager=True,
                )
            }
        )
        .with_columns(pl.col("BinX1").shift(-1).alias("BinX2"))
        .filter(~pl.col("BinX2").is_null())
        .with_columns(pl.col("BinX1").dt.strftime("%Y-%m").alias("BinLabel"))
        .with_columns(
            pl.lit(kanta_start_date).alias("BreakMin"),
            pl.lit(kanta_end_date).alias("BreakMax"),
            pl.lit(left_closed_bins).alias("BinLeftClosed?"),
        )
        .collect()
        .write_ndjson(output_path_bins_definitions)
    )

    (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .with_columns(pl.col(cols.datetime).dt.strftime("%Y-%m").alias("BinLabel"))
        .group_by(pl.col(cols.omopid), pl.col("BinLabel"))
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
        .collect()
        .write_ndjson(output_path_stats)
    )

    logger.info("Computing N measurements over time distribution: Done")


def compute_dist_n_records_measurements_per_person(
    *, list_omop_ids, data_path, cols, output_dir
):
    logger.info("Computing distribution of N records and measurements per person")

    output_path_records_stats = (
        output_dir / "n_records_per_person_distribution__stats.jsonl"
    )
    output_path_measurements_stats = (
        output_dir / "n_measurements_per_person_distribution__stats.jsonl"
    )

    output_path_bins_definitions = (
        output_dir / "n_records_per_person_distribution__bins_definitions.jsonl"
    )

    # Binning parameters, assuming integers
    break_min = 0
    break_max = 200
    bin_width = 2
    left_closed = True

    breaks = list(range(break_min, break_max, bin_width)) + [break_max]
    n_bins = len(breaks) - 1

    bin_x1s = [float("-inf")] + list(map(float, breaks))
    bin_x2s = list(map(float, breaks)) + [float("+inf")]
    bin_indices = range(-1, len(breaks))

    breaks_str = list(map(str, breaks))
    bin_x1s_str = ["−∞"] + breaks_str
    bin_x2s_str = breaks_str + ["+∞"]

    if left_closed:
        bin_label_format = "[{}, {})"
    else:
        bin_label_format = "({}, {}]"

    bin_labels = (
        bin_label_format.format(x1x2[0], x1x2[1])
        for x1x2 in zip(bin_x1s_str, bin_x2s_str)
    )

    bins_definitions = pl.LazyFrame(
        {
            "BinX1": bin_x1s,
            "BinX2": bin_x2s,
            "BinIndex": bin_indices,
            "BinX1Label": bin_x1s_str,
            "BinX2Label": bin_x2s_str,
            "BinLabel": bin_labels,
        }
    )

    binned_records = (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .group_by(pl.col(cols.omopid), pl.col(cols.personid))
        .agg(pl.len().alias("NRecords"))
        .pipe(
            binning_n_equi_bins,
            n_bins=n_bins,
            break_min=break_min,
            break_max=break_max,
            col_values="NRecords",
            left_closed=left_closed,
        )
        .group_by(pl.col(cols.omopid), pl.col("BinIndex"))
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    binned_measurements = (
        pl.scan_parquet(data_path)
        .filter(pl.col(cols.omopid).is_in(list_omop_ids))
        .filter(
            (
                ~pl.col(cols.meas_unit_harmonized).is_null()
                & ~pl.col(cols.meas_value_harmonized).is_null()
            )
            | (~pl.col(cols.test_outcome).is_null())
        )
        .group_by(pl.col(cols.omopid), pl.col(cols.personid))
        .agg(pl.len().alias("NMeasurements"))
        .pipe(
            binning_n_equi_bins,
            n_bins=n_bins,
            break_min=break_min,
            break_max=break_max,
            col_values="NMeasurements",
            left_closed=left_closed,
        )
        .group_by(pl.col(cols.omopid), pl.col("BinIndex"))
        .agg(
            pl.col(cols.personid).n_unique().alias("NPeople"),
            pl.len().alias("BinCount"),
        )
        .pipe(keep_green, column_n_people="NPeople")
    )

    bins_definitions.collect().write_ndjson(output_path_bins_definitions)

    binned_records.collect().write_ndjson(output_path_records_stats)
    binned_measurements.collect().write_ndjson(output_path_measurements_stats)

    logger.info("Computing distribution of N records and measurements per person: Done")


def bins_from_median_abs_dev(
    dataf, col, *, breaks_count, left_closed_bins, clamp_left_to=None
):
    # NOTE(Vincent 2024-09-23) Computing the Median Absolute Deviation statistic (MAD)
    # Since the range of measured values is usually quite large, we don't want to compute
    # the bins on the whole range, but instead on a range that has most of the data and few
    # of data points in the extremity of the tails.
    # Previously, I used to compute the bins on the range [0, quantile(0.99)].
    # Now, I use the  median ± 7 * MAD  stat as it should be less sensitive to extreme values
    # in the distribution tails. I chose 7 as the MAD factor because in some tests I made
    # it covered 98% of the data.
    median = dataf.get_column(col).median()
    mad = median_abs_dev(dataf, col)
    mad_factor = 7

    break_min = median - mad_factor * mad
    if clamp_left_to is not None:
        break_min = max(break_min, clamp_left_to)
    break_max = median + mad_factor * mad

    breaks = np.linspace(start=break_min, stop=break_max, num=breaks_count)
    breaks = np.unique(breaks)

    bins = []
    labels = []
    breaks_for_bins = [float("-inf")] + breaks.tolist() + [float("+inf")]
    for x1, x2 in zip(breaks_for_bins[:-1], breaks_for_bins[1:]):
        if left_closed_bins:
            label = f"[{x1}, {x2})"
        else:
            label = f"({x1}, {x2}]"
        bins.append({"x1": x1, "x2": x2, "label": label})
        labels.append(label)

    return bins, labels, breaks


def median_abs_dev(dataf, col):
    # NOTE(Vincent 2024-09-23)  The MAD stat is currently not available directly
    # from the polars API.
    # Check here for status:
    # https://github.com/pola-rs/polars/issues/10578
    return (
        dataf.with_columns(
            (pl.col(col) - pl.col(col).median()).abs().alias("AbsDevFromMedian")
        )
        .get_column("AbsDevFromMedian")
        .median()
    )


def binning_soft_mad(dataf, *, column_values, partition_by, n_bins, left_closed):
    # NOTE(Vincent 2024-09-23) Computing the Median Absolute Deviation statistic (MAD)
    # Since the range of measured values is usually quite large, we don't want to compute
    # the bins on the whole range, but instead on a range that has most of the data and few
    # of data points in the extremity of the tails.
    # Previously, I used to compute the bins on the range [0, quantile(0.99)].
    # Now, I use the  median ± 7 * MAD  stat as it should be less sensitive to extreme values
    # in the distribution tails. I chose 7 as the MAD factor because in some tests I made
    # it covered 98% of the data.

    # NOTE(Vincent 2024-09-23)  The MAD stat is currently not available directly
    # from the polars API.
    # Check here for status:
    # https://github.com/pola-rs/polars/issues/10578

    # TODO(Vincent 2024-10-09)  Maybe switch to a MAD alternative? Since some
    # people say the MAD stat is aimed at symmetric distributions, which is
    # not always what we deal with.
    # See: https://www.tandfonline.com/doi/epdf/10.1080/01621459.1993.10476408

    mad_factor = 7
    soft_min_step = 0.01

    with_bins = (
        dataf.with_columns(
            pl.col(column_values).median().over(partition_by).alias("Median")
        )
        .with_columns(
            (pl.col(column_values) - pl.col("Median")).abs().alias("AbsoluteDeviations")
        )
        .with_columns(
            pl.col("AbsoluteDeviations").median().over(partition_by).alias("MAD"),
        )
        .with_columns(
            (pl.col("Median") - mad_factor * pl.col("MAD")).alias("BreakMin"),
            (pl.col("Median") + mad_factor * pl.col("MAD")).alias("BreakMax"),
        )
        # Soft resetting min and max breaks when there is very low dispersion
        .with_columns(
            pl.when(pl.col("BreakMin") == pl.col("BreakMax"))
            .then(pl.col("Median") - soft_min_step)
            .otherwise(pl.col("BreakMin"))
            .alias("BreakMin"),
            pl.when(pl.col("BreakMin") == pl.col("BreakMax"))
            .then(pl.col("Median") + soft_min_step)
            .otherwise(pl.col("BreakMax"))
            .alias("BreakMax"),
        )
        # Rescale the value on the binning scale
        .with_columns(
            (
                n_bins
                * (
                    (pl.col(column_values) - pl.col("BreakMin"))
                    / (pl.col("BreakMax") - pl.col("BreakMin"))
                )
            ).alias("ValueOnBinScale")
        )
        # Bin index
        .with_columns(pl.col("ValueOnBinScale").floor().alias("BinIndex"))
        # Handle left/right-closed binning
        .with_columns(
            pl.when(
                (not left_closed) & (pl.col("ValueOnBinScale") == pl.col("BinIndex"))
            )
            .then(pl.col("BinIndex") - 1)
            .otherwise(pl.col("BinIndex"))
            .alias("BinIndex")
        )
        # Handle special cases when value is outside of the binning range
        .with_columns(
            # -- Bin index
            # Set all bins on the *left* side of the first break to have index -1
            pl.when(pl.col("BinIndex") < 0)
            .then(pl.lit(-1))
            # Set all bins on the *right* side of the last break to have max index +1
            .when(pl.col("BinIndex") >= n_bins)
            .then(pl.lit(n_bins))
            .otherwise(pl.col("BinIndex"))
            .cast(pl.Int64)
            .alias("BinIndex"),
        )
    )

    # TODO(Vincent 2024-10-14) Refactor to use `bins_definitions()` func
    # Computing all bin definitions
    dataf_bin_index = pl.LazyFrame({"BinIndex": range(-1, n_bins + 1)})
    bin_definitions = (
        with_bins.group_by(partition_by)
        .agg(pl.col("BreakMin").first(), pl.col("BreakMax").first())
        .join(dataf_bin_index, how="cross")
        .with_columns(
            (
                pl.col("BreakMin")
                + pl.col("BinIndex")
                * (pl.col("BreakMax") - pl.col("BreakMin"))
                / n_bins
            ).alias("BinX1"),
            (
                pl.col("BreakMin")
                + (pl.col("BinIndex") + 1)
                * (pl.col("BreakMax") - pl.col("BreakMin"))
                / n_bins
            ).alias("BinX2"),
        )
        .with_columns(
            pl.when(pl.col("BinIndex") == -1)
            .then(pl.lit(float("-inf")))
            .when(pl.col("BinIndex") == n_bins)
            .then(pl.col("BreakMax"))
            .otherwise(pl.col("BinX1"))
            .alias("BinX1"),
            pl.when(pl.col("BinIndex") == n_bins)
            .then(pl.lit(float("+inf")))
            .when(pl.col("BinIndex") == n_bins - 1)
            .then(pl.col("BreakMax"))
            .otherwise(pl.col("BinX2"))
            .alias("BinX2"),
        )
        .with_columns(
            pl.col("BinX1")
            .round(2)
            .cast(pl.Utf8)
            .str.replace("-inf", "−∞")
            .alias("BinLabelX1"),
            pl.col("BinX2")
            .round(2)
            .cast(pl.Utf8)
            .str.replace("inf", "+∞")
            .alias("BinLabelX2"),
        )
        .with_columns(
            (
                pl.when(left_closed)
                .then(pl.format("[{}, {})", pl.col("BinLabelX1"), pl.col("BinLabelX2")))
                .otherwise(
                    pl.format("({}, {}]", pl.col("BinLabelX1"), pl.col("BinLabelX2"))
                )
            ).alias("BinLabel")
        )
    )

    with_bins = with_bins.select(
        pl.selectors.exclude(
            [
                "Median",
                "AbsoluteDeviations",
                "MAD",
                "BreakMin",
                "BreakMax",
                "ValueOnBinScale",
            ]
        )
    )

    return (with_bins, bin_definitions)


def binning_n_equi_bins(
    dataf,
    *,
    n_bins,
    break_min,
    break_max,
    col_values,
    left_closed,
):
    if not left_closed:
        raise ValueError("This binning function only supports left-closed bins.")

    return (
        dataf.with_columns(
            (n_bins * (pl.col(col_values) - break_min) / (break_max - break_min))
            .floor()
            .alias("BinIndex")
        )
        # Handle special cases when values are outside of the binning range
        .with_columns(
            pl.when(pl.col("BinIndex") < 0)
            .then(pl.lit(-1))
            .when(pl.col("BinIndex") >= n_bins)
            .then(pl.lit(n_bins))
            .otherwise(pl.col("BinIndex"))
            .cast(pl.Int64)
            .alias("BinIndex")
        )
    )


def with_bins_definitions(
    lazyf_unique_omop_ids, *, n_bins, break_min, break_max, left_closed
):
    dataf_bin_index = pl.LazyFrame({"BinIndex": range(-1, n_bins + 1)})

    return (
        lazyf_unique_omop_ids.join(dataf_bin_index, how="cross")
        .with_columns(
            pl.lit(break_min).alias("BreakMin"), pl.lit(break_max).alias("BreakMax")
        )
        .with_columns(
            (
                pl.col("BreakMin")
                + pl.col("BinIndex")
                * (pl.col("BreakMax") - pl.col("BreakMin"))
                / n_bins
            ).alias("BinX1"),
            (
                pl.col("BreakMin")
                + (pl.col("BinIndex") + 1)
                * (pl.col("BreakMax") - pl.col("BreakMin"))
                / n_bins
            ).alias("BinX2"),
        )
        .with_columns(
            pl.when(pl.col("BinIndex") == -1)
            .then(pl.lit(float("-inf")))
            .when(pl.col("BinIndex") == n_bins)
            .then(pl.col("BreakMax"))
            .otherwise(pl.col("BinX1"))
            .alias("BinX1"),
            pl.when(pl.col("BinIndex") == n_bins)
            .then(pl.lit(float("+inf")))
            .when(pl.col("BinIndex") == n_bins - 1)
            .then(pl.col("BreakMax"))
            .otherwise(pl.col("BinX2"))
            .alias("BinX2"),
        )
        .with_columns(pl.lit(left_closed).alias("BinLeftClosed?"))
    )


def keep_green(dataframe, *, column_n_people):
    logger.debug(
        f"... filtering to keep green data, using column={column_n_people} >= {MIN_N_FOR_GREEN_DATA}"
    )

    return dataframe.filter(pl.col(column_n_people) >= MIN_N_FOR_GREEN_DATA)
