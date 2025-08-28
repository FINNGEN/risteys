"""Functions for computing age and year distributions"""

import numpy as np
import pandas as pd
from risteys_pipeline.utils.log import logger
from risteys_pipeline.config import MIN_SUBJECTS_PERSONAL_DATA


def green_distribution(dist):
    """
    Aggregate bins to have no individual-level data based on `MIN_SUBJECTS_PERSONAL_DATA`.
    Values 0 < x < MIN_PERSONAL_DATA are considered individual-level data.

    Input:
        dist (DataFrame): distribution to be aggregated

    Returns:
        res (DataFrame): distribution with no individual-level data
    """

    res = []

    # Early return if the count is too low to produce non individual-level data
    if dist.sum() >= MIN_SUBJECTS_PERSONAL_DATA:

        # Initialize rolling bin lower bound and accumulated count
        interval_left = None
        acc_count = 0

        # Aggregate individual-level data up and update the interval endpoints
        for (endpoint, interval), count in dist.items():
            acc_count += count
            interval_left = interval.left if interval_left is None else interval_left
            if (acc_count == 0) | (acc_count >= MIN_SUBJECTS_PERSONAL_DATA):
                res.append(
                    {"left": interval_left, "right": interval.right, "count": acc_count}
                )
                acc_count = 0
                interval_left = None

        # If the last count was personal-level data, it was discarded in the previous loop. Fixed here.
        # The value is accumulated from right to left until it is added to a large enough bin
        if (acc_count != 0) & (acc_count < MIN_SUBJECTS_PERSONAL_DATA):
            res[-1]["count"] += acc_count
            res[-1]["right"] = interval.right
            while (res[-1]["count"] != 0) & (res[-1]["count"] < 5):
                last = res.pop()
                res[-1]["count"] += last["count"]
                res[-1]["right"] = last["right"]

    return res


def compute_distribution(first_events, column):
    """
    Compute distribution of values in the given column (age/year) for all endpoints.
    Bins are aggregated so that each bar contains at least `MIN_SUBJECTS_PERSONAL_DATA` persons.
    
    No sex-specific distributions are computed as they are currently not used.

    Args:
        first_events (DataFrame): first events dataset
        column (str): column used for the distributions; "age" or "year"

    Returns:
        res (DataFrame): distribution of values
    """

    logger.info(f"Computing distribution for {column}")

    # Add brackets
    if column == "age":
        min_age = 0
        max_age = 100
        by_age = 10
        brackets = list(range(min_age, max_age, by_age)) + [np.inf]
    elif column == "year":
        min_year = 1970
        max_year = round(first_events["year"].max())
        by_year = 5
        brackets = [-np.inf] + list(range(min_year, max_year, by_year)) + [max_year]

    # Compute distribution
    dist = (
        first_events[["endpoint", column]]
        .assign(bin=pd.cut(first_events[column], brackets, right=False))
        .groupby(["endpoint", "bin"])
        .size()
        .sort_index()
        .groupby("endpoint")
        .apply(lambda x: green_distribution(x))
    )

    # Reshape dataframe
    res = []
    for endpoint, bins in dist.items():
        for bin in bins:
            res.append([endpoint, "all", bin["left"], bin["right"], bin["count"]])
    res = pd.DataFrame(res, columns=["endpoint", "sex", "left", "right", "count"])

    return res


if __name__ == "__main__":
    from risteys_pipeline.finregistry.load_data import load_data
    from risteys_pipeline.utils.write_data import get_output_filepath

    endpoint_definitions, minimal_phenotype, first_events = load_data()

    dist_age = compute_distribution(first_events, "age")
    dist_year = compute_distribution(first_events, "year")

    dist_age.to_csv(get_output_filepath("distribution_age", "csv"), index=False)
    dist_year.to_csv(get_output_filepath("distribution_year", "csv"), index=False)
