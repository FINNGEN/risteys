"""Survival analysis for priority endpoints"""

import pandas as pd
import logging
from tqdm import tqdm

from risteys_pipeline.config import *
from risteys_pipeline.utils.log import logger
from risteys_pipeline.utils.write_data import get_output_filepath
from risteys_pipeline.finregistry.load_data import (
    load_data,
    load_priority_endpoints_data,
    load_related_endpoints_data,
)
from risteys_pipeline.survival_analysis import *

DAYS_IN_YEAR = 365.25
DAYS_BETWEEN_ENDPOINTS = 180


def filter_first_events(first_events, priority, cohort):
    """
    Apply the following filtering to the first events:
    - include only the priority endpoints
    - include only persons in the cohort
    - include events within the followup period
    - include endpoints with at least MIN_SUBJECTS_SURVIVAL_ANALYSIS * 2 persons

    Args:
        first_events (DataFrame): first events dataset
        priority (DataFrame): priority endpoints dataset
        cohort (DataFrame): cohort dataset

    Returns:
        first_events (DataFrame): filtered first events dataset
    """
    first_events = first_events.loc[first_events["endpoint"].isin(priority["endpoint"])]
    first_events = first_events.loc[
        (first_events["personid"].values.isin(cohort.index))
        & (first_events["year"] >= FOLLOWUP_START)
        & (first_events["year"] <= FOLLOWUP_END)
    ]
    first_events = first_events.reset_index(drop=True)
    endpoint_counts = first_events.groupby("endpoint").size()
    endpoint_counts = endpoint_counts[
        endpoint_counts > MIN_SUBJECTS_SURVIVAL_ANALYSIS * 2
    ]
    first_events = first_events.loc[
        first_events["endpoint"].values.isin(endpoint_counts.index)
    ]
    first_events = first_events.reset_index(drop=True)

    return first_events


def get_counts(endpoint, first_events, cohort, related_endpoints):
    """
    Get the number of eligible persons for endpoint-endpoint survival analysis for each endpoint.
    Only endpoints with >50 persons are included.

    Args:
        endpoint (str): name of the endpoint
        first_events (DataFrame): first events dataset
        cohort (DataFrame): cohort dataset
        related_endpoints (DataFrame): related endpoints dataset

    Returns:
        DataFrame: counts for endpoints
    """
    cases = get_cases(endpoint, first_events, cohort)
    temp = first_events.loc[first_events["personid"].values.isin(cases.index)]
    temp = temp.reset_index(drop=True)
    temp = temp.merge(cases["stop"], how="left", right_index=True, left_on="personid")
    temp = temp.loc[
        (temp["year"] - temp["stop"]).values >= (DAYS_BETWEEN_ENDPOINTS / DAYS_IN_YEAR)
    ]
    temp = temp.groupby("endpoint").size()
    temp = temp[temp >= 50]
    temp = temp.to_frame().reset_index()
    temp = temp.rename(columns={0: "count", "endpoint": "endpoint2"})
    temp["endpoint1"] = endpoint

    # Exclude related endpoints
    excl = related_endpoints.loc[
        related_endpoints["Endpoint"] == endpoint, "AllLinkedUnique"
    ]
    if len(excl) > 0:
        temp = temp.loc[~temp["endpoint2"].isin(excl.reset_index(drop=True)[0])]

    return temp[["endpoint1", "endpoint2", "count"]]


def run_survival_analysis(endpoint1, endpoint2, first_events, cohort):
    """
    Run survival analysis.

    If both endpoints include both sexes, use sex as a covariate.
    If both endpoints include one sex, drop sex and match the sex in the cohort.
    If the endpoints only include persons of different sexes, do not run the analysis.

    Args:
        endpoint1 (str): name of the first endpoint ("exposure endpoint")
        endpoint2 (str): name of the second endpoint ("outcome endpoint")
        first_events (DataFrame): first events dataset
        cohort (DataFrame): cohort dataset

    Returns:
        params (DataFrame): coefficient, confidence interval, and p value

    """
    params = None

    cases = get_cases(endpoint2, first_events, cohort)
    exposed = get_exposed(
        endpoint1, first_events, cohort, cases, buffer=DAYS_BETWEEN_ENDPOINTS
    )

    exposed_cases = cases.join(exposed, how="inner")
    sexes = exposed_cases["female"].unique()

    if len(sexes) > 0:

        if len(sexes) == 2:
            logger.debug(f"{endpoint1}-{endpoint2}: Data of both sexes")
            df_survival = build_survival_dataset(cases, cohort, exposed)
        else:
            logger.debug(
                f"{endpoint1}-{endpoint2}: Data of one sex (female={sexes[0]})"
            )
            cohort_ = cohort.loc[cohort["female"] == sexes[0]]
            df_survival = build_survival_dataset(cases, cohort_, exposed)
            df_survival = df_survival.drop(columns=["female"])

        df_survival = set_timescale(df_survival, "age")
        model = survival_analysis(df_survival, "cox")

        if model is not None:
            logger.debug("Formatting the output")

            params = model.summary

            params = params.reset_index()
            params = params.loc[params["covariate"] == "exposure"]
            params = params.reset_index(drop=True)
            params = params.drop(columns="covariate")

            params["prior"] = endpoint1
            params["outcome"] = endpoint2
            params["lag_hr"] = ""
            params["nindivs_prior_outcome"] = exposed_cases.shape[0]
            params["prior_hr"] = params["exp(coef)"]
            params["prior_ci_lower"] = params["exp(coef) lower 95%"]
            params["prior_ci_upper"] = params["exp(coef) upper 95%"]
            params["prior_pval"] = params["p"]

            cols = [
                "prior",
                "outcome",
                "lag_hr",
                "nindivs_prior_outcome",
                "prior_hr",
                "prior_ci_lower",
                "prior_ci_upper",
                "prior_pval",
            ]
            params = params[cols]

    return params


def survival_analysis_loop(endpoint, first_events, cohort, related_endpoints):
    """
    Run survival analysis for all endpoints with sufficient data with endpoint as exposure.

    Args:
        endpoint (str): name of the first endpoint ("exposure endpoint")
        first_events (DataFrame): first events dataset
        cohort (DataFrame): cohort dataset
        related_endpoints (DataFrame): related endpoints dataset

    Returns:
        params (DataFrame): results dataset
    """
    endpoint1 = endpoint
    counts = get_counts(endpoint1, first_events, cohort, related_endpoints)

    res = []
    for endpoint2 in counts["endpoint2"]:
        params = run_survival_analysis(endpoint1, endpoint2, first_events, cohort)
        if params is not None:
            res.append(params)
    if res:
        res = pd.concat(res, axis=0)

    return res


if __name__ == "__main__":
    from multiprocessing import get_context
    from tqdm import tqdm

    N_PROCESSES = 20

    logger.setLevel(logging.DEBUG)

    endpoints, minimal_phenotype, first_events = load_data()
    priority = load_priority_endpoints_data()
    related_endpoints = load_related_endpoints_data()
    n_endpoints = priority.shape[0]

    cohort = get_cohort(minimal_phenotype)
    first_events = filter_first_events(first_events, priority, cohort)

    logger.info("Start multiprocessing")
    with get_context("spawn").Pool(processes=N_PROCESSES) as pool, tqdm(
        total=n_endpoints
    ) as pbar:
        result = [
            pool.apply_async(
                survival_analysis_loop,
                args=(endpoint, first_events, cohort, related_endpoints),
                callback=lambda _: pbar.update(),
            )
            for endpoint in priority["endpoint"]
        ]
        result = [r.get() for r in result]

    logger.info("Combining the results")
    params = [x for x in result if len(x) > 0]
    params = pd.concat(params, axis=0, ignore_index=True)

    logger.info("Writing output to file")
    output_path = get_output_filepath("surv_priority_endpoints", "csv")
    params.to_csv(output_path, index=False)
