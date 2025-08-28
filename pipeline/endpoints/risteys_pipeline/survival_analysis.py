import numpy as np
import pandas as pd

from lifelines import CoxPHFitter, AalenJohansenFitter
from lifelines.utils import ConvergenceError

from risteys_pipeline.utils.log import logger
from risteys_pipeline.config import (
    FOLLOWUP_START,
    FOLLOWUP_END,
    MIN_SUBJECTS_PERSONAL_DATA,
    MIN_SUBJECTS_SURVIVAL_ANALYSIS,
)
from risteys_pipeline.sample import sample_cases, sample_controls

DAYS_IN_YEAR = 365.25
OUTCOME_COMPETING_EVENT = 2
N_CASES = 10_000
CONTROLS_PER_CASE = 1.5


def get_cohort(minimal_phenotype):
    """
    Get cohort dataset for survival analysis.

    Eligibility criteria: 
    - born before the end of the follow-up
    - either not dead or died after the start of the follow-up
    - sex information is not missing

    Args:
        minimal_phenotype (DataFrame): minimal phenotype dataset

    Returns
        cohort (DataFrame): cohort dataset with personid as an index
    """
    logger.debug("Building the cohort")

    cols = ["personid", "birth_year", "death_year", "female"]
    cohort = minimal_phenotype[cols]

    cohort = cohort.loc[
        (cohort["birth_year"].values < FOLLOWUP_END)
        & (
            (cohort["death_year"].isnull())
            | (cohort["death_year"].values > FOLLOWUP_START)
        )
        & (~cohort["female"].isnull())
    ]
    cohort = cohort.reset_index(drop=True)

    cohort["outcome"] = 0
    cohort["start"] = np.maximum(cohort["birth_year"], FOLLOWUP_START)
    cohort["stop"] = np.minimum(cohort["death_year"].fillna(np.inf), FOLLOWUP_END)

    cohort = cohort.set_index("personid")

    return cohort[["start", "stop", "outcome", "birth_year", "female"]]


def get_cases(outcome, first_events, cohort):
    """
    Get cases for survival analysis.

    Eligibility criteria: 
    - event during the follow-up period
    - case is a member of the cohort

    Args:
        outcome (str): outcome endpoint
        first_events (DataFrame): first events dataset 
        cohort (DataFrame): cohort dataset

    Returns: 
        cases (DataFrame): dataset with all persons with `endpoint`
    """
    if (outcome == "death") | (outcome == "DEATH"):
        # stop < FOLLOWUP_END only if the person dies before FOLLOWUP_END
        # Note: should be re-implemented if censoring can occur for different reasons than death, e.g. immigration
        cases = cohort.loc[cohort["stop"] < FOLLOWUP_END].copy()
    else:
        cases = (
            first_events.loc[
                (first_events["endpoint"].values == outcome)
                & (first_events["year"].values > FOLLOWUP_START)
                & (first_events["year"].values < FOLLOWUP_END)
            ]
            .filter(["personid", "year"])
            .set_index("personid")
            .join(cohort, how="inner")
        )
        cases["stop"] = cases["year"]

    cases["outcome"] = 1

    return cases[["start", "stop", "outcome", "birth_year", "female"]]


def get_exposed(exposure, first_events, cohort, cases, buffer=30):
    """
    Get exposed persons for survival analysis. 

    Eligibility criteria: 
    - exposure during the follow-up period
    - exposed person is a member of the cohort
    - exposure at least `buffer` days before the outcome

    Args:
        exposure (str): exposure endpoint
        first_events (DataFrame): first events dataset
        cohort (DataFrame): cohort dataset
        cases (DataFrame): cases dataset
        buffer (int): number of days required between exposure and outcome

    Returns:
        exposed (DataFrame): dataset with all exposed persons
    """
    exposed = get_cases(exposure, first_events, cohort)
    exposed = exposed.rename(columns={"outcome": "exposure", "stop": "exposure_year"})
    exposed = exposed[["exposure_year", "exposure"]]
    exposed = exposed.join(cases, how="left").fillna({"stop": np.inf})
    exposed = exposed.loc[
        (exposed["stop"] - exposed["exposure_year"]) > (buffer / DAYS_IN_YEAR)
    ]

    return exposed[["exposure_year", "exposure"]]


def add_exposure(exposed, df_survival):
    """
    Add exposure as a time-varying covariate to the `df_survival` dataset.
    Two rows are added for each exposed person: start -> exposure and exposure -> stop.

    Args:
        exposed (DataFrame): exposed dataset
        df_survival (DataFrame): dataset for survival analysis

    Returns:
        df_survival (DataFrame): dataset for survival analysis with `exposure` column
    """
    logger.debug("Adding exposure")

    df_survival = df_survival.merge(exposed.reset_index(), how="left", on="personid")
    df_survival = df_survival.fillna({"exposure": 0})

    exposed_rows = df_survival["exposure"] == 1

    # Second part of exposure (exposure -> stop)
    temp = df_survival[exposed_rows].reset_index(drop=True)
    temp["exposure"] = 1
    temp["start"] = temp["exposure_year"]

    # First part of exposure (start -> exposure)
    df_survival.loc[exposed_rows, "exposure"] = 0
    df_survival.loc[exposed_rows, "outcome"] = 0
    df_survival.loc[exposed_rows, "stop"] = df_survival.loc[
        exposed_rows, "exposure_year"
    ]

    # Combine the two parts (start -> exposure -> stop)
    df_survival = pd.concat([df_survival, temp], axis=0, ignore_index=True)

    df_survival = df_survival.drop(columns=["exposure_year"])

    return df_survival


def add_death_as_competing_event(df_survival):
    """
    Add death as a competing event to the dataset.

    Competing events are denoted with value `OUTCOME_COMPETING_EVENT` in the `outcome` column.
    Periods that don't end in either the event, exposure or the end of study must end in a competing event.

    Args:  
        df_survival (DataFrame): survival dataset

    Returns:
        df_survival (DataFrame): survival dataset with competing evens added
    """
    if "exposure" in df_survival.columns:
        # `followup_outcome`/`followup_exposure`: person's outcome/exposure during the full follow-up
        followup_outcome = df_survival.groupby("personid")["outcome"].transform("sum")
        followup_exposure = df_survival.groupby("personid")["exposure"].transform("sum")
        indx = (
            (df_survival["stop"] < FOLLOWUP_END)
            & (followup_outcome == 0)
            & (followup_exposure - df_survival["exposure"] == 0)
        )
    else:
        indx = (df_survival["stop"] < FOLLOWUP_END) & (df_survival["outcome"] == 0)

    df_survival.loc[indx, "outcome"] = OUTCOME_COMPETING_EVENT

    return df_survival


def build_survival_dataset(
    cases, cohort, exposed=None, n_cases=N_CASES, controls_per_case=CONTROLS_PER_CASE
):
    """
    Build survival dataset.

    Exposure is included as a time-varying covariate, if present.
    Controls are sampled from the cohort.

    Args:
        cases (DataFrame): cases dataset
        cohort (DataFrame): cohort dataset, possibly filtered to a specific sex
        exposed (DataFrame, default None): exposure dataset

    Returns:
        df_survival (DataFrame): survival dataset
    """
    logger.debug("Building the survival dataset")

    cases_sample = sample_cases(cases, n_cases, exposed).reset_index()
    n_controls = round(cases_sample.shape[0] * controls_per_case)
    controls_sample = sample_controls(cohort, n_controls, cases, exposed).reset_index()

    df_survival = pd.concat([cases_sample, controls_sample], ignore_index=True)

    if exposed is not None:
        df_survival = add_exposure(exposed, df_survival)

    time_epsilon = 0.01
    df_survival = df_survival.loc[df_survival.stop - df_survival.start > time_epsilon, :]
    df_survival = df_survival.reset_index(drop=True)

    return df_survival


def check_min_subjects(df):
    """
    Check that the requirement for the minimum number of subjects is met.

    The minimum number of subjects for the survival analysis (`MIN_SUBJECTS_SURVIVAL_ANALYSIS`)
    cannot bypass the requirement for personal data (`MIN_SUBJECTS_PERSONAL_DATA`)

    If exposure is included, the requirement applies to each of the following:
    - exposed cases
    - non-exposed cases
    - exposed controls
    - non-exposed controls

    Args:
        df (DataFrame): dataset with the following columns: `personid`, `outcome`, `exposure` (optional)

    Returns: 
        check (bool): True if there's enough subjects, otherwise False
    """
    min_persons = max(MIN_SUBJECTS_PERSONAL_DATA, MIN_SUBJECTS_SURVIVAL_ANALYSIS)

    if "exposure" in df.columns:
        tbl = pd.crosstab(
            df["outcome"],
            df["exposure"],
            values=df["personid"],
            aggfunc=pd.Series.nunique,
        )
    else:
        tbl = df.groupby("outcome")["personid"].nunique()

    check = tbl.values.min() > min_persons

    logger.debug(f"Min subjects test passed: {check}")

    return check


def set_timescale(df_survival, timescale="age"):
    """
    Set timescale for the survival dataset as either age or time-on-study.

    If "age":
    - `start` is the age at birth or the start of follow-up (or exposure), whichever occurs first
    - `stop` is the age at outcome, death or end of follow-up (or exposure), whichever occurs first

    If "time-on-study":
    - `start` is removed from the dataset
    - `stop` is the follow-up time between `start` and `stop`, as defined above

    Args: 
        df_survival (DataFrame): survival dataset
        timescale (str, default "age"): timescale, either "age" or "time-on-study"

    Returns:
        df_survival (DataFrame): survival dataset with timescale set
    """
    logger.debug("Setting timescale")
    if timescale == "age":
        df_survival["start"] = df_survival["start"] - df_survival["birth_year"]
        df_survival["stop"] = df_survival["stop"] - df_survival["birth_year"]
    elif timescale == "time-on-study":
        df_survival["stop"] = df_survival["stop"] - df_survival["start"]
        df_survival = df_survival.drop(columns=["start"])
    else:
        raise ValueError("Timescale must be 'age' or 'time-on-study'")

    return df_survival


def survival_analysis(df_survival, model_type="cox"):
    """
    Fit a survival model to the data and return the model object.
    
    This function handles the following: 
    - check that the requirement for the minimum number of persons is satisfied
    - handle different timescales 
    - fit the model
    - catch convergence errors

    Args:
        df_survival (DataFrame): survival dataset
        model_type (str, default "cox"): model to fit, "cox" for Cox PH model or "aalen-johansen" for Aalen-Johansen estimator

    Returns: 
        model (object): fitted survival model or None
    """

    model = None

    if (df_survival is not None) & (check_min_subjects(df_survival)):

        df_survival = df_survival.drop(columns="personid")
        entry_col = "start" if "start" in df_survival.columns else None

        if model_type == "cox":
            logger.debug("Fitting the Cox PH model")
            model = CoxPHFitter()
            try:
                model.fit(
                    df_survival,
                    entry_col=entry_col,
                    duration_col="stop",
                    event_col="outcome",
                    weights_col="weight",
                    robust=True,
                )
            except ConvergenceError:
                model = None

        elif model_type == "aalen-johansen":
            logger.debug("Fitting the Aalen-Johansen model")
            model = AalenJohansenFitter(calculate_variance=False)
            try:
                model.fit(
                    durations=df_survival["stop"],
                    event_observed=df_survival["outcome"],
                    event_of_interest=1,
                    entry=df_survival["start"] if entry_col is not None else None,
                    weights=df_survival["weight"],
                )
            except ConvergenceError:
                model = None

        else:
            raise ValueError("Model must be 'cox' or 'aalen-johansen'")

    return model
