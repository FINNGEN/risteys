"""
Compute drug scores related to a given endpoint.

Usage:
    python3 medication_stats_logit.py \
        <ENDPOINT> \                  # FinnGen endpoint for which to compute associated drug scores
        <PATH_FIRST_EVENTS> \         # Path to the first events file from FinnGen
        <PATH_DETAILED_LONGIT> \      # Path to the detailed longitudinal file from FinnGen
        <PATH_ENDPOINT_DEFINITIONS \  # Path to the endpoint definitions file from FinnGen
        <PATH_MINIMUM_INFO> \         # Path to the minimum file from FinnGen
        <OUTPUT_DIRECTORY>            # Path to where to put the output files

Outputs:
- <ENDPOINT>_scores.csv: CSV file with score and standard error for each drug
- <ENDPOINT>_counts.csv: CSV file which breakdowns drugs into their full ATC and counts how the
  number of individuals.
"""

import csv
from pathlib import Path
from sys import argv

import pandas as pd
import numpy as np
from numpy.linalg import LinAlgError
from numpy.linalg import multi_dot as mdot
from statsmodels.formula.api import logit

from log import logger


ATC_LEVEL = len('A10BA')  # Use broad level of ATC classification instead of full ATC codes

# Time windows
YEAR = 1.0
MONTH = 1 / 12
WEEK = 7 / 365.25
PRE_DURATION = 1 * YEAR
PRE_EXCLUSION = 1 * MONTH
POST_DURATION = 5 * WEEK

STUDY_STARTS = 1998  # inclusive, from 1998-01-01 onward
STUDY_ENDS = 2021    # exclusive, up until 2020-12-31
STUDY_DURATION = 20 * YEAR

MIN_CASES = 15

# Prediction parameters
PRED_FEMALE = 0.5
PRED_YOB = 1960
PRED_FG_ENDPOINT_YEAR = 2018


def main(fg_endpoint, first_events, detailed_longit, endpoint_defs, minimum_info, output_dir):
    """Compute a score for the association of a given drug to a FinnGen endpoint"""
    line_buffering = 1

    # File with drug scores
    scores_path = output_dir / (fg_endpoint + ".csv")
    scores_file = open(scores_path, "x", buffering=line_buffering)
    res_writer = csv.writer(scores_file)
    res_writer.writerow([
        "endpoint",
        "drug",
        "score",
        "stderr"
    ])

    # Results of full-ATC drug counts
    counts_path = output_dir / (fg_endpoint + "_counts.csv")
    counts_file = open(counts_path, "x", buffering=line_buffering)
    counts_writer = csv.writer(counts_file)
    counts_writer.writerow([
        "endpoint",
        "drug",
        "full_ATC",
        "count"
    ])

    # Load endpoint and drug data
    df_logit, endpoint_def = load_data(
        fg_endpoint,
        first_events,
        detailed_longit,
        endpoint_defs,
        minimum_info)
    is_sex_specific = endpoint_def.SEX.notna()

    for drug in df_logit.ATC.unique():
        data_comp_logit(df_logit, fg_endpoint, drug, is_sex_specific, res_writer, counts_writer)

    scores_file.close()
    counts_file.close()


def load_data(fg_endpoint, first_events, detailed_longit, endpoint_defs, minimum_info):
    """Load the data for the given endpoint and all the drug events"""
    fg_endpoint_age = fg_endpoint + "_AGE"
    fg_endpoint_year = fg_endpoint + "_YEAR"

    # FIRST-EVENT DATA (for logit model)
    logger.info("Loading endpoint data")
    df_endpoint = pd.read_csv(
        first_events,
        usecols=[
            "FINNGENID",
            fg_endpoint,
            fg_endpoint_age,
            fg_endpoint_year
        ],
        dialect=csv.excel_tab
    )
    # Rename endpoint columns to genereic names for either reference down the line
    df_endpoint = df_endpoint.rename(columns={
        fg_endpoint: "fg_endpoint",
        fg_endpoint_age: "fg_endpoint_age",
        fg_endpoint_year: "fg_endpoint_year"
    })

    # Select only individuals having the endpoint
    df_endpoint = df_endpoint.loc[df_endpoint["fg_endpoint"] == 1, :]
    # Compute approximate year of birth
    df_endpoint["yob"] = df_endpoint["fg_endpoint_year"] - df_endpoint["fg_endpoint_age"]
    # Keep only incident cases (individuals having the endpoint after start of study)
    df_endpoint = df_endpoint[df_endpoint["fg_endpoint_year"] >= STUDY_STARTS]


    # DRUG DATA
    logger.info("Loading drug data")
    df_drug = pd.read_csv(
        detailed_longit,
        usecols=["FINNGENID", "SOURCE", "EVENT_AGE", "APPROX_EVENT_DAY", "CODE1"],
        dialect=csv.excel_tab
    )

    df_drug.APPROX_EVENT_DAY = pd.to_datetime(df_drug.APPROX_EVENT_DAY)  # needed for filtering based on year
    df_drug = df_drug.loc[df_drug.SOURCE == "PURCH", :]  # keep only drug purchase events
    df_drug["ATC"] = df_drug.CODE1.str[:ATC_LEVEL]


    # INFO DATA
    logger.info("Loading info data")
    df_info = pd.read_csv(
        minimum_info,
        usecols=["FINNGENID", "SEX"],
        dialect=csv.excel_tab
    )
    df_info["female"] = df_info.SEX.apply(lambda d: 1.0 if d == "female" else 0.0)
    df_info = df_info.drop(columns=["SEX"])


    # ENDPOINT DEFINITION
    df_endpoint_defs = pd.read_csv(
        endpoint_defs,
        usecols=["NAME", "SEX"]
        dialect=csv.excel_tab)
    endpoint_def = df_endpoint_defs.loc[df_endpoint_defs.NAME == fg_endpoint, :].iloc[0]

    # Merge the data into a single DataFrame
    logger.info("Merging dataframes")
    df_logit = df_info.merge(df_endpoint, on="FINNGENID")
    df_logit = df_logit.merge(df_drug, on="FINNGENID")

    return df_logit, endpoint_def


def data_comp_logit(df, fg_endpoint, drug, is_sex_specific, res_writer, counts_writer):
    logger.info(f"Computing for: {fg_endpoint} / {drug}")
    df_stats, counts = logit_controls_cases(
        df,
        drug,
        STUDY_DURATION,
        PRE_DURATION,
        PRE_EXCLUSION,
        POST_DURATION)

    # Check that we have enough cases
    (ncases, _) = df_stats[df_stats.drug == 1.0].shape
    if ncases < MIN_CASES:
        logger.warning(f"Not enough cases ({ncases} < {MIN_CASES}) for {fg_endpoint} / {drug}")
        return

    # Write the full-ATC drug counts
    for full_atc, count in counts.items():
        counts_writer.writerow([
            fg_endpoint,
            drug,
            full_atc,
            count
        ])

    # Compute the score for the given endpoint / drug
    try:
        score, stderr = comp_score_logit(df_stats, is_sex_specific)
    except LinAlgError as exc:
        logger.warning(f"LinAlgError: {exc}")
    else:
        res_writer.writerow([
            fg_endpoint,
            drug,
            score,
            stderr
        ])


def logit_controls_cases(
        df,
        drug,
        study_duration,
        pre_duration,
        pre_exclusion,
        post_duration,
):
    """Build a table of controls and cases"""
    logger.debug("Munging data into controls and cases")
    df["drug"] = 0.0

    # Remove some data based on study_duration
    study_starts = STUDY_ENDS - study_duration
    keep_data = (
        (df.APPROX_EVENT_DAY.dt.year >= study_starts)
        & (df["fg_endpoint_year"] >= study_starts))
    df = df.loc[keep_data, :]

    # Check events where the drug happens BEFORE the endpoint
    drug_pre_endpoint = (
        (df.ATC == drug)
        # Pre-endpoint time-window
        & (df.EVENT_AGE >= df.fg_endpoint_age - pre_exclusion - pre_duration)
        & (df.EVENT_AGE <= df.fg_endpoint_age - pre_exclusion)
    )

    # Check events where the druge happens AFTER the endpoint
    drug_post_endpoint = (
        (df.ATC == drug)
        # Post-endpoint time-window
        & (df.EVENT_AGE >= df.fg_endpoint_age)
        & (df.EVENT_AGE <= df.fg_endpoint_age + post_duration)
    )

    # Define cases
    cases = (~ drug_pre_endpoint) & drug_post_endpoint
    df_cases = df.loc[cases, :]
    df_cases.loc[:, "drug"] = 1.0

    # The aggregate function doesn't matter: within each group the rows will differ by EVENT_AGE, but this column will be discarded in the model
    df_cases = df_cases.groupby("FINNGENID").min()

    # Count the number of individuals for each full ATC code
    counts = df_cases.loc[df_cases.ATC == drug, :].groupby("CODE1").count().drug

    # Remove unecessary columns
    df_cases = df_cases.drop(columns=[
        "fg_endpoint",
        "fg_endpoint_age",
        "EVENT_AGE",
        "CODE1",
        "ATC"])

    df_controls = df.loc[~ cases, ["FINNGENID", "female", "yob", "fg_endpoint_year", "drug"]]
    df_controls = df_controls.groupby("FINNGENID").min()

    df_stats = pd.concat([df_cases, df_controls], sort=False)

    return df_stats, counts


def comp_score_logit(df, is_sex_specific):
    logger.info("Model computation score")
    # Remove the sex covariate for sex-specific endpoints, otherwise
    # it will fail since there will be no females or no males.
    model = 'drug ~ yob + yob*yob + fg_endpoint_year + fg_endpoint_year*fg_endpoint_year'
    if not is_sex_specific:
        model += ' + female'
    # Compute score using Logistic model, predict using fixed values
    mod = logit(model, df)
    res = mod.fit(disp=False)  # fit() without displaying convergence messages
    predict_data = pd.DataFrame({
        "Intercept": [1.0],
        "female": [PRED_FEMALE],
        "yob": [PRED_YOB],
        "fg_endpoint_year": [PRED_FG_ENDPOINT_YEAR]
    })

    # Compute the standard error of the prediction
    pred = res.predict(predict_data)
    pred_lin = np.log(pred / (1 - pred))  # to scale of the linear predictors
    stderr = np.sqrt(mdot([predict_data, res.cov_params(), predict_data.T]))
    real_stderr = stderr.flatten() * (np.abs(np.exp(pred_lin)) / (1 + np.exp(pred_lin))**2)

    return pred[0], real_stderr[0]


if __name__ == '__main__':
    main(
        fg_endpoint=argv[1],
        first_events=Path(argv[2]),
        detailed_longit=Path(argv[3]),
        endpoint_defs=Path(argv[4]),
        minimum_info=Path(argv[5]),
        output_dir=Path(argv[6])
    )
