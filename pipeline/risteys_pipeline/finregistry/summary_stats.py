"""
Functions for the following summary statistics:
- key figures (number of individuals, unadjusted prevalence, mean age at first event)
- distributions: age at first event, year at first event
- cumulative incidence
"""

import numpy as np
import pandas as pd
from risteys_pipeline.log import logger
from risteys_pipeline.config import MIN_SUBJECTS_PERSONAL_DATA
from risteys_pipeline.finregistry.survival_analysis import (
    build_cph_dataset,
    survival_analysis,
)


def compute_key_figures(first_events, minimal_phenotype):
    """
    Compute the following key figures for each endpoint:
        - number of individuals
        - unadjusted prevalence (%)
        - mean age at first event (years)

    The numbers are calculated for males, females, and all.

    Args:
        first_events (DataFrame): first events dataframe
        minimal_phenotype(DataFrame): minimal phenotype dataframe

    Returns:
        kf (DataFrame): key figures dataframe with the following columns:
        endpoint, 
        nindivs_female, nindivs_male, nindivs_all, 
        mean_age_female, mean_age_male, mean_age_all,
        prevalence_female, prevalence_male, prevalence_all
    """
    logger.info("Computing key figures")

    # Calculate the total number of individuals
    # Note: individuals for sex="unknown" is based on first events
    n_total = {
        "female": sum(minimal_phenotype["female"] == True),
        "male": sum(minimal_phenotype["female"] == False),
        "unknown": len(
            first_events.loc[first_events["sex"] == "unknown", "finregistryid"].unique()
        ),
    }

    # Calculate key figures by endpoint and sex
    kf = (
        first_events.groupby(["endpoint", "sex"])
        .agg({"finregistryid": "count", "age": "mean"})
        .rename(columns={"finregistryid": "nindivs_", "age": "mean_age_"})
        .fillna({"nindivs_": 0})
        .reset_index()
    )
    kf["prevalence_"] = kf["nindivs_"] / kf["sex"].replace(n_total)
    kf["n_endpoint"] = kf.groupby("endpoint")["nindivs_"].transform("sum")
    kf["w"] = kf["nindivs_"] / kf["n_endpoint"]

    # Calculate key figures by endpoint for all individuals
    kf_all = (
        kf.groupby("endpoint")
        .agg(
            {
                "nindivs_": "sum",
                "mean_age_": lambda x: np.average(x, weights=kf.loc[x.index, "w"]),
                "prevalence_": lambda x: np.average(x, weights=kf.loc[x.index, "w"]),
            }
        )
        .reset_index()
        .assign(sex="all")
    )

    # Drop rows with sex=unknown
    kf = kf.loc[kf["sex"] != "unknown"].reset_index(drop=True)

    # Combine the two datasets
    kf = pd.concat([kf, kf_all])

    # Drop redundant columns
    kf = kf.drop(columns=["w", "n_endpoint"])

    # Remove personal data
    cols = ["nindivs_", "mean_age_", "prevalence_"]
    kf.loc[kf["nindivs_"] <= MIN_SUBJECTS_PERSONAL_DATA, cols,] = np.nan

    # Pivot and flatten hierarchical columns
    kf = kf.pivot(index="endpoint", columns="sex").reset_index()
    kf.columns = ["".join(col).strip() for col in kf.columns.values]

    return kf


def cumulative_incidence(cohort, all_cases, endpoints):
    """
    Cumulative incidence with age as timescale stratified by sex

    Args:
        minimal_phenotype (DataFrame): minimal phenotype dataset
        first_events (DataFrame): first events dataset
        endpoints (DataFrame): endpoint definition dataset
b
    Returns:
        result (DataFrame): dataset with the following columns:
            endpoint: the name of the endpoint
            bch: baseline cumulative hazard by age group and sex
            params: coefficients
    """

    n_endpoints = endpoints.shape[0]
    result = pd.DataFrame(index=endpoints["endpoint"], columns=["bch", "params"])

    for i, row in endpoints.iterrows():

        outcome, female = row

        # Fit the Cox PH model
        logger.info(f"Outcome {i+1}/{n_endpoints}: {outcome}")
        if pd.isnull(female):
            df_cph = build_cph_dataset(outcome, None, cohort, all_cases)
            cph = survival_analysis(df_cph, "age", stratify_by_sex=True)
        else:
            subcohort = cohort.loc[cohort["female"] == female]
            subcohort = subcohort.reset_index(drop=True)
            df_cph = build_cph_dataset(outcome, None, subcohort, all_cases)
            cph = survival_analysis(df_cph, "age", drop_sex=True)

        bch = np.nan
        params = np.nan

        if cph:
            # Calculate number of events by age group
            counts = df_cph.loc[df_cph["outcome"] == 1].reset_index(drop=True)
            counts["age"] = round((counts["stop"] - counts["birth_year"]) / 10) * 10
            counts = counts.groupby("age")["outcome"].sum().reset_index()
            counts = counts.rename(columns={"outcome": "n_events"})

            # Calculate baseline cumulative hazard by age group
            bch = cph.baseline_cumulative_hazard_
            bch = bch.reset_index()
            bch = bch.rename(columns={"index": "age", 0: "male", 1: "female"})
            bch["age"] = round(bch["age"] / 10) * 10
            bch = bch.groupby("age").mean()
            bch = bch.merge(counts, on="age", how="left")
            bch = bch.loc[bch["n_events"] > MIN_SUBJECTS_PERSONAL_DATA]
            bch = bch.drop(columns=["n_events"])
            bch = bch.set_index("age").to_dict()

            # Extract parameters
            params = cph.params_.to_dict()

        # Add data to resuls
        result.loc[outcome] = {"bch": bch, "params": params}

    return result

