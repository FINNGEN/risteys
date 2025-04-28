defmodule RisteysWeb.LabTestHTML do
  use RisteysWeb, :html

  embed_templates "lab_test_html/*"

  defp index_prettify_stats(stats, overall_stats) do
    assigns = %{}
    pretty_stats = stats

    npeople_total =
      stats.npeople_total && RisteysWeb.Utils.pretty_number(stats.npeople_total)

    plot_npeople_absolute = plot_count(stats.npeople_total, overall_stats.npeople)

    percent_people_two_plus_records =
      stats.percent_people_two_plus_records &&
        RisteysWeb.Utils.pretty_number(stats.percent_people_two_plus_records) <> "%"

    plot_percent_people_two_plus_records =
      plot_count(
        stats.percent_people_two_plus_records,
        overall_stats.percent_people_two_plus_records
      )

    sex_female_percent =
      case stats.sex_female_percent do
        nil -> nil
        value -> RisteysWeb.Utils.round_and_str(value, 2) <> "%"
      end

    plot_sex_female_percent = plot_sex(stats.sex_female_percent)

    median_years_first_to_last_measurement =
      case stats.median_years_first_to_last_measurement do
        nil ->
          nil

        _ ->
          stats.median_years_first_to_last_measurement
          |> RisteysWeb.Utils.pretty_number(2)
      end

    # in years
    tick_every = 1.0

    plot_median_duration_first_to_last_measurement =
      plot_count(
        stats.median_years_first_to_last_measurement,
        overall_stats.median_years_first_to_last_measurement,
        tick_every
      )

    pretty_stats =
      Map.merge(pretty_stats, %{
        npeople_total: npeople_total,
        plot_npeople_absolute: plot_npeople_absolute,
        sex_female_percent: sex_female_percent,
        plot_sex_female_percent: plot_sex_female_percent,
        percent_people_two_plus_records: percent_people_two_plus_records,
        plot_percent_people_two_plus_records: plot_percent_people_two_plus_records,
        median_years_first_to_last_measurement: median_years_first_to_last_measurement,
        plot_median_duration_first_to_last_measurement:
          plot_median_duration_first_to_last_measurement
      })

    missing_value = ~H"""
    <span class="missing-value">&mdash;</span>
    """

    pretty_stats =
      for {key, value} <- pretty_stats, into: %{} do
        {key, value || missing_value}
      end

    pretty_stats
  end

  defp plot_sex(nil), do: ""

  defp plot_sex(female_percent) do
    width = 60
    height = 5
    viewbox = "0 0 #{width} #{height}"

    assigns = %{
      female_percent: female_percent,
      width: width,
      height: height,
      viewbox: viewbox,
      split_position: female_percent / 100 * width
    }

    # Making the plot stretch but keep its height is done by setting the following on <svg>:
    # - fixed `height`
    # - `width="100%"`
    # - `preserveAspectRatio="none"`
    ~H"""
    <svg
      viewBox={@viewbox}
      height={@height}
      width="100%"
      preserveAspectRatio="none"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <rect width={@width} height={@height} fill="#bfcde6" />
      <rect width={@split_position} height={@height} fill="#dd9fbd" />
      <rect x={@split_position} width="1" height={@height} fill="black" />
    </svg>
    """
  end

  defp plot_count(npeople, npeople_max, tick_every \\ nil)

  defp plot_count(nil, _, _), do: ""

  defp plot_count(npeople, npeople_max, tick_every) do
    tick_percents =
      case tick_every do
        nil ->
          []

        _ ->
          last = round(npeople_max)
          step = round(tick_every)
          Range.to_list(step..last//step)
      end
      |> Enum.map(&(100 * &1 / npeople_max))

    assigns = %{
      npeople_percent: 100 * npeople / npeople_max,
      tick_percents: tick_percents
    }

    ~H"""
    <div style="width: 100%; height: 0.3em; background-color: var(--bg-color-plot-empty); position: relative;">
      <div style={"width: #{@npeople_percent}%; height: 100%; background-color: var(--bg-color-plot); position: absolute;"}>
      </div>
      <%= for tick_percent <- @tick_percents do %>
        <div style={"width: #{tick_percent}%; height: 100%; border-right: 1px solid var(--bg-color-plot-empty); position: absolute;"}>
        </div>
      <% end %>
    </div>
    """

    width = 60
    height = 5
    viewbox = "0 0 #{width} #{height}"

    tick_x_positions =
      case tick_every do
        nil ->
          []

        _ ->
          last = round(npeople_max)
          step = round(tick_every)
          Range.to_list(step..last//step)
      end
      |> Enum.map(&(&1 / npeople_max * width))

    assigns = %{
      width: width,
      height: height,
      viewbox: viewbox,
      width_npeople: npeople / npeople_max * width,
      tick_x_positions: tick_x_positions
    }

    ~H"""
    <svg
      viewBox={@viewbox}
      height={@height}
      width="100%"
      preserveAspectRatio="none"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <rect width={@width} height={@height} fill="var(--bg-color-plot-empty)" />
      <rect width={@width_npeople} height={@height} fill="var(--bg-color-plot)" />
      <%= for tick_x <- @tick_x_positions do %>
        <rect x={tick_x} width="1" height={@height} fill="var(--bg-color-plot-empty)" />
      <% end %>
    </svg>
    """
  end

  def show_prettify_stats(lab_test) do
    npeople_both_sex =
      lab_test.npeople_both_sex && RisteysWeb.Utils.pretty_number(lab_test.npeople_both_sex)

    percent_people_two_plus_records =
      lab_test.percent_people_two_plus_records &&
        RisteysWeb.Utils.pretty_number(lab_test.percent_people_two_plus_records)

    median_n_measurements =
      lab_test.median_n_measurements &&
        RisteysWeb.Utils.pretty_number(lab_test.median_n_measurements, 1)

    median_years_first_to_last_measurement =
      case lab_test.median_years_first_to_last_measurement do
        nil ->
          nil

        num ->
          num
          |> RisteysWeb.Utils.pretty_number(2)
      end

    distribution_lab_values =
      case lab_test.distribution_lab_values do
        nil ->
          nil

        %{unit: "titre"} = dist ->
          build_obsplot_payload(:categorical, dist, "Measured value (titre)", "Number of records")

        dist ->
          # TODO(Vincent 2024-10-30) ::OBSPLOT_FORMATTING
          # Ideally the formatting would be already correct when it comes here.
          # So either make it correct in the pipeline output, or otherwise when
          # importing the data.
          bins =
            for bin <- dist.bins do
              %{bin | "x1x2_formatted" => "#{bin["x1x2_formatted"]} #{dist.unit}"}
            end

          dist = %{dist | bins: bins}

          build_obsplot_payload(
            :continuous,
            dist,
            "Measured value",
            "Number of records",
            "lab-values"
          )
      end

    qc_table =
      Enum.map(lab_test.qc_table, fn qc_row ->
        percent_missing_formatted =
          qc_row.percent_missing_measurement_value &&
            RisteysWeb.Utils.pretty_number(qc_row.percent_missing_measurement_value)

        plot_test_outcome =
          build_obsplot_payload(:qc_table_test_outcome, qc_row.test_outcome_counts)

        plot_harmonized_value_distribution =
          qc_row.distribution_measurement_values &&
            build_obsplot_payload(
              :qc_table_harmonized_value_distribution,
              qc_row.distribution_measurement_values
            )

        %{
          percent_missing_measurement_value_formatted: percent_missing_formatted,
          plot_harmonized_value_distribution: plot_harmonized_value_distribution,
          plot_test_outcome: plot_test_outcome
        }
        |> Map.merge(qc_row)
      end)

    distribution_year_of_birth =
      if is_nil(lab_test.distribution_year_of_birth) do
        nil
      else
        build_obsplot_payload(:years, lab_test.distribution_year_of_birth)
      end

    distribution_age_first_measurement =
      case lab_test.distribution_age_first_measurement do
        nil ->
          nil

        dist ->
          # TODO(Vincent 2024-10-30) ::OBSPLOT_FORMATTING
          bins =
            for bin <- dist["bins"] do
              %{bin | "x1x2_formatted" => "#{bin["x1x2_formatted"]} years"}
            end

          dist = %{dist | "bins" => bins}

          build_obsplot_payload(
            :continuous,
            dist,
            "Age at first measurement",
            "Number of people"
          )
      end

    distribution_age_last_measurement =
      case lab_test.distribution_age_last_measurement do
        nil ->
          nil

        dist ->
          build_obsplot_payload(
            :continuous,
            dist,
            "Age at last measurement",
            "Number of people"
          )
      end

    distribution_age_start_of_registry =
      case lab_test.distribution_age_start_of_registry do
        nil ->
          nil

        dist ->
          build_obsplot_payload(
            :continuous,
            dist,
            "Age at start of registry",
            "Number of people"
          )
      end

    distribution_nyears_first_to_last_measurement =
      case lab_test.distribution_nyears_first_to_last_measurement do
        nil ->
          nil

        dist ->
          build_obsplot_payload(
            :continuous,
            dist,
            "Duration",
            "Number of people"
          )
      end

    distribution_n_measurements_over_years =
      case lab_test.distribution_n_measurements_over_years do
        nil ->
          nil

        dist ->
          build_obsplot_payload(:year_months, dist)
      end

    distribution_n_measurements_per_person =
      case lab_test.distribution_n_measurements_per_person do
        nil ->
          nil

        dist ->
          build_obsplot_payload(:n_measurements_per_person, dist)
      end

    distribution_value_range_per_person =
      case lab_test.distribution_value_range_per_person do
        nil ->
          nil

        dist ->
          build_obsplot_payload(
            :continuous,
            dist,
            "Value range",
            "Number of people"
          )
      end

    Map.merge(lab_test, %{
      npeople_both_sex: npeople_both_sex,
      percent_people_two_plus_records: percent_people_two_plus_records,
      median_n_measurements: median_n_measurements,
      median_years_first_to_last_measurement: median_years_first_to_last_measurement,
      distribution_lab_values: distribution_lab_values,
      qc_table: qc_table,
      distribution_year_of_birth: distribution_year_of_birth,
      distribution_age_first_measurement: distribution_age_first_measurement,
      distribution_age_last_measurement: distribution_age_last_measurement,
      distribution_age_start_of_registry: distribution_age_start_of_registry,
      distribution_nyears_first_to_last_measurement:
        distribution_nyears_first_to_last_measurement,
      distribution_n_measurements_over_years: distribution_n_measurements_over_years,
      distribution_n_measurements_per_person: distribution_n_measurements_per_person,
      distribution_value_range_per_person: distribution_value_range_per_person
    })
  end

  defp build_obsplot_payload(:categorical, distribution, x_label, y_label) do
    payload = %{
      bins: distribution.bins,
      x_label: x_label,
      y_label: y_label
    }

    assigns = %{
      payload: Jason.encode!(payload)
    }

    ~H"""
    <div class="obsplot" data-obsplot-type="categorical" data-obsplot={@payload}></div>
    """
  end

  defp build_obsplot_payload(
         :continuous,
         distribution,
         x_label,
         y_label,
         plot_type \\ "continuous"
       ) do
    # TODO(Vincent 2024-10-30) Refactor distribution schemas so that they arrive here with a
    # unified structure.
    # Currently dist lab values has :bins, :break_min, etc. has schema fields, so they it arrives
    # here :bins, etc. But the other distributions have schemas with just :distribution, so they
    # arrive here with "bins", etc. has keys.
    # I think the best way would be that all the distribution schemas have :bins, :xmin, :xmax,
    # etc. has keys.
    bins =
      case distribution do
        %{bins: bins} -> bins
        %{"bins" => bins} -> bins
      end

    xmin =
      case distribution do
        %{break_min: xmin} -> xmin
        %{"xmin" => xmin} -> xmin
      end

    xmax =
      case distribution do
        %{break_max: xmax} -> xmax
        %{"xmax" => xmax} -> xmax
      end

    payload = %{
      bins: bins,
      x_label: x_label,
      y_label: y_label,
      xmin: xmin,
      xmax: xmax
    }

    assigns = %{
      payload: Jason.encode!(payload),
      plot_type: plot_type
    }

    ~H"""
    <div class="obsplot" data-obsplot-type={@plot_type} data-obsplot={@payload}></div>
    """
  end

  defp build_obsplot_payload(:years, distribution) do
    %{
      "bins" => list_bins,
      "break_min" => break_min,
      "break_max" => break_max
    } = distribution

    # Remove (-inf; _] and (_ ; +inf)
    bins = Enum.reject(list_bins, fn %{"x1" => x1, "x2" => x2} -> is_nil(x1) or is_nil(x2) end)

    assigns = %{
      payload: Jason.encode!(%{xmin: break_min, xmax: break_max, bins: bins})
    }

    if Enum.empty?(bins) do
      nil
    else
      ~H"""
      <div class="obsplot" data-obsplot-type="years" data-obsplot={@payload}></div>
      """
    end
  end

  defp build_obsplot_payload(:year_months, dist) do
    assigns = %{
      payload: Jason.encode!(dist)
    }

    ~H"""
    <div class="obsplot" data-obsplot-type="year-months" data-obsplot={@payload}></div>
    """
  end

  defp build_obsplot_payload(:n_measurements_per_person, dist) do
    assigns = %{
      payload: Jason.encode!(dist)
    }

    ~H"""
    <div class="obsplot" data-obsplot-type="n-measurements-per-person" data-obsplot={@payload}></div>
    """
  end

  defp build_obsplot_payload(:qc_table_test_outcome, nil) do
    nil
  end

  defp build_obsplot_payload(:qc_table_test_outcome, distribution) do
    sum_count =
      distribution
      |> Enum.map(fn %{"count" => count} -> count end)
      |> Enum.sum()

    bins =
      for bin <- distribution do
        %{"count" => count, "test_outcome" => test_outcome} = bin

        percent_count = 100 * count / sum_count
        x_label = RisteysWeb.Utils.pretty_number(percent_count) <> "%"

        yy = test_outcome || "NA"

        %{x: percent_count, y: yy, x_label: x_label}
      end

    order_labels = [
      "NA",
      "N",
      "A",
      "AA",
      "L",
      "LL",
      "H",
      "HH"
    ]

    bins =
      for label <- order_labels do
        with_this_label = Enum.filter(bins, fn %{y: yy} -> yy == label end)

        case with_this_label do
          [] -> nil
          # There should be only one bin with a given label
          [head | _rest] -> head
        end
      end
      |> Enum.reject(&is_nil/1)

    assigns = %{
      payload: Jason.encode!(%{bins: bins})
    }

    ~H"""
    <div class="obsplot" data-obsplot-type="qc-table-test-outcome" data-obsplot={@payload}></div>
    """
  end

  defp build_obsplot_payload(:qc_table_harmonized_value_distribution, distribution) do
    %{
      "bins" => list_bins,
      "xmin" => xmin,
      "xmax" => xmax
    } = distribution

    bins =
      for bin <- list_bins do
        %{"x1" => x1, "x2" => x2, "yy" => yy, "x1x2_formatted" => x1x2_formatted} = bin

        %{
          x1: x1,
          x2: x2,
          y: yy,
          x1x2_formatted: x1x2_formatted
        }
      end
      # Remove (-inf; _] and (_ ; +inf)
      |> Enum.reject(fn bin -> is_nil(bin.x1) or is_nil(bin.x2) end)

    assigns = %{
      payload:
        Jason.encode!(%{
          xmin: xmin,
          xmax: xmax,
          bins: bins
        })
    }

    if Enum.empty?(bins) do
      nil
    else
      ~H"""
      <div
        class="obsplot"
        data-obsplot-type="qc-table-harmonized-value-distribution"
        data-obsplot={@payload}
      >
      </div>
      """
    end
  end
end
