defmodule RisteysWeb.LabTestHTML do
  use RisteysWeb, :html

  embed_templates "lab_test_html/*"

  defp index_prettify_stats(stats, overall_stats) do
    assigns = %{}
    pretty_stats = stats

    npeople_total =
      stats.npeople_total && RisteysWeb.Utils.pretty_number(stats.npeople_total)

    sex_female_percent =
      case stats.sex_female_percent do
        nil -> nil
        value -> RisteysWeb.Utils.round_and_str(value, 2) <> "%"
      end

    median_n_measurements =
      stats.median_n_measurements &&
        RisteysWeb.Utils.pretty_number(stats.median_n_measurements, 1)

    plot_sex_female_percent = plot_sex(stats.sex_female_percent)

    plot_npeople_absolute = plot_count(stats.npeople_total, overall_stats.npeople)

    plot_median_n_measurements =
      plot_count(stats.median_n_measurements, overall_stats.median_n_measurements)

    median_nyears_first_to_last_measurement =
      case stats.median_ndays_first_to_last_measurement do
        nil ->
          nil

        _ ->
          stats.median_ndays_first_to_last_measurement
          |> days_to_years()
          |> RisteysWeb.Utils.pretty_number(2)
      end

    tick_every_year = 365.25

    plot_median_duration_first_to_last_measurement =
      plot_count(
        stats.median_ndays_first_to_last_measurement,
        overall_stats.median_ndays_first_to_last_measurement,
        tick_every_year
      )

    pretty_stats =
      Map.merge(pretty_stats, %{
        npeople_total: npeople_total,
        sex_female_percent: sex_female_percent,
        median_n_measurements: median_n_measurements,
        plot_npeople_absolute: plot_npeople_absolute,
        plot_sex_female_percent: plot_sex_female_percent,
        plot_median_n_measurements: plot_median_n_measurements,
        median_nyears_first_to_last_measurement: median_nyears_first_to_last_measurement,
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
    assigns = %{female_percent: female_percent}

    ~H"""
    <div style="width: 100%; height: 0.3em; background-color: #bfcde6;">
      <div style={"width: #{@female_percent}%; height: 100%; background-color: #dd9fbd; border-right: 1px solid #000;"}>
      </div>
    </div>
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
  end

  def show_prettify_stats(lab_test) do
    npeople_both_sex =
      lab_test.npeople_both_sex && RisteysWeb.Utils.pretty_number(lab_test.npeople_both_sex)

    median_n_measurements =
      lab_test.median_n_measurements &&
        RisteysWeb.Utils.pretty_number(lab_test.median_n_measurements, 1)

    median_nyears_first_to_last_measurement =
      case lab_test.median_ndays_first_to_last_measurement do
        nil ->
          nil

        num ->
          num
          |> days_to_years()
          |> RisteysWeb.Utils.pretty_number(2)
      end

    distributions_lab_values =
      for dist <- lab_test.distributions_lab_values do
        %{"bins" => bins} = dist
        y_label = "Number of records"

        case dist["measurement_unit"] do
          "binary" ->
            %{
              obsplot: build_obsplot_payload(:binary, bins, "nrecords", "", y_label),
              measurement_unit: "binary"
            }

          "titre" ->
            x_label = "Measured value (titre)"

            %{
              obsplot: build_obsplot_payload(:categorical, bins, "nrecords", x_label, y_label),
              measurement_unit: "titre"
            }

          _ ->
            x_label = "Measured value (#{dist["measurement_unit"]})"

            %{
              obsplot: build_obsplot_payload(:continuous, bins, :nrecords, x_label, y_label),
              measurement_unit: dist["measurement_unit"]
            }
        end
      end

    distribution_year_of_birth =
      build_obsplot_payload(
        :years,
        lab_test.distribution_year_of_birth["bins"],
        :npeople
      )

    Map.merge(lab_test, %{
      npeople_both_sex: npeople_both_sex,
      median_n_measurements: median_n_measurements,
      median_nyears_first_to_last_measurement: median_nyears_first_to_last_measurement,
      distributions_lab_values: distributions_lab_values,
      distribution_year_of_birth: distribution_year_of_birth
    })
  end

  defp build_obsplot_payload(:continuous, bins, y_key, x_label, y_label) do
    bins =
      for bin <- bins do
        %{^y_key => yy} = bin

        x1_str =
          if bin.range_left == :minus_infinity do
            "−∞"
          else
            RisteysWeb.Utils.pretty_number(bin.range_left)
          end

        x2_str =
          if bin.range_right == :plus_infinity do
            "+∞"
          else
            RisteysWeb.Utils.pretty_number(bin.range_right)
          end

        en_dash = "–"
        range_str = x1_str <> en_dash <> x2_str

        y_formatted = RisteysWeb.Utils.pretty_number(yy)

        %{
          "x1" => bin.range_left_finite,
          "x2" => bin.range_right_finite,
          "y" => yy,
          "x_formatted" => range_str,
          "y_formatted" => y_formatted
        }
      end

    payload = %{
      "bins" => bins,
      "x_label" => x_label,
      "y_label" => y_label
    }

    assigns = %{
      payload: Jason.encode!(payload)
    }

    ~H"""
    <div class="obsplot" data-obsplot-type="continuous" data-obsplot={@payload}></div>
    """
  end

  defp build_obsplot_payload(:binary, bins, y_key, x_label, y_label) do
    bins =
      for bin <- bins, into: %{} do
        %{^y_key => yy, "range" => xx} = bin

        xx =
          case xx do
            "0.0" -> :negative
            "1.0" -> :positive
          end

        {xx, yy}
      end

    # Make sure we have display both positive and negative, even if we don't have both of them in the data.
    default = %{
      positive: nil,
      negative: nil
    }

    bins = Map.merge(default, bins)

    bins = [
      %{x: "positive", y: bins.positive},
      %{x: "negative", y: bins.negative}
    ]

    assigns = %{
      payload: Jason.encode!(%{"bins" => bins, "x_label" => x_label, "y_label" => y_label})
    }

    ~H"""
    <div class="obsplot" data-obsplot-type="discrete" data-obsplot={@payload}></div>
    """
  end

  defp build_obsplot_payload(:categorical, bins, y_key, x_label, y_label) do
    bins =
      for %{"range" => xx, ^y_key => yy} <- bins do
        xx = RisteysWeb.Utils.parse_number(xx)
        %{"x" => xx, "y" => yy}
      end

    payload = %{
      "bins" => bins,
      "x_label" => x_label,
      "y_label" => y_label
    }

    assigns = %{
      payload: Jason.encode!(payload)
    }

    ~H"""
    <div class="obsplot" data-obsplot-type="categorical" data-obsplot={@payload}></div>
    """
  end

  defp build_obsplot_payload(:years, bins, y_key) do
    bins =
      for bin <- bins do
        %{^y_key => yy} = bin
        x_formatted = to_string(bin.range_left)
        y_formatted = RisteysWeb.Utils.pretty_number(yy)

        %{
          "x1" => bin.range_left_finite,
          "x2" => bin.range_right_finite,
          "y" => yy,
          "x_formatted" => x_formatted,
          "y_formatted" => y_formatted
        }
      end

    payload = %{
      "bins" => bins
    }

    assigns = %{
      payload: Jason.encode!(payload)
    }

    ~H"""
    <div class="obsplot" data-obsplot-type="years" data-obsplot={@payload}></div>
    """
  end

  defp days_to_years(ndays) do
    days_in_year = 365.25
    ndays / days_in_year
  end
end
