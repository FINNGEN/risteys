defmodule Risteys.LabWAS do
  import Ecto.Query

  alias Risteys.Repo
  alias Risteys.LabWAS.Stats

  require Logger

  def get_fgendpoint_labwas(fg_endpoint) do
    Repo.all(
      from stats in Stats,
        where: stats.fg_endpoint_id == ^fg_endpoint.id,
        order_by: [desc: :with_measurement_mlogp]
    )
  end

  def get_lab_test_labwas(lab_test_omop_id) do
    Repo.all(
      from stats in Stats,
        join: fg_endpoint in Risteys.FGEndpoint.Definition,
        on: fg_endpoint.id == stats.fg_endpoint_id,
        where: stats.omop_concept_id == ^lab_test_omop_id,
        order_by: [desc: :with_measurement_mlogp],
        select: %{
          fg_endpoint_name: fg_endpoint.name,
          fg_endpoint_longname: fg_endpoint.longname,
          with_measurement_n_cases: stats.with_measurement_n_cases,
          with_measurement_n_controls: stats.with_measurement_n_controls,
          with_measurement_odds_ratio: stats.with_measurement_odds_ratio,
          with_measurement_mlogp: stats.with_measurement_mlogp,
          mean_n_measurements_cases: stats.mean_n_measurements_cases,
          mean_n_measurements_controls: stats.mean_n_measurements_controls,
          mean_value_cases: stats.mean_value_cases,
          mean_value_controls: stats.mean_value_controls,
          mean_value_unit: stats.mean_value_unit,
          mean_value_n_cases: stats.mean_value_n_cases,
          mean_value_n_controls: stats.mean_value_n_controls,
          mean_value_mlogp: stats.mean_value_mlogp
        }
    )
  end

  def import_stats(file_path) do
    endpoints = Risteys.FGEndpoint.list_endpoints_ids()

    stats =
      file_path
      |> File.stream!()
      |> Stream.map(fn line ->
        line
        |> Jason.decode!()
        |> parse_labwas_row(endpoints)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, :ok} =
      Repo.transaction(
        fn ->
          Repo.delete_all(Stats)

          Enum.each(stats, &create_labwas_stats/1)
        end,
        timeout: :infinity
      )
  end

  defp parse_labwas_row(row, endpoints) do
    %{
      "FG_Endpoint" => endpoint_name,
      "OMOP_Concept_ID" => omop_concept_id,
      "OMOP_Concept_Name" => omop_concept_name,
      "FG_Endpoint_N_Cases" => fg_endpoint_n_cases,
      "FG_Endpoint_N_Controls" => fg_endpoint_n_controls,
      "With_Measurement_N_Cases" => with_measurement_n_cases,
      "With_Measurement_N_Controls" => with_measurement_n_controls,
      "With_Measurement_Odds_Ratio" => with_measurement_odds_ratio,
      "With_Measurement_mlogp" => with_measurement_mlogp,
      "Mean_N_Measurements_Cases" => mean_n_measurements_cases,
      "Mean_N_Measurements_Controls" => mean_n_measurements_controls,
      "Mean_Value_N_Cases" => mean_value_n_cases,
      "Mean_Value_N_Controls" => mean_value_n_controls,
      "Mean_Value_Unit" => mean_value_unit,
      "Mean_Value_Cases" => mean_value_cases,
      "Mean_Value_Controls" => mean_value_controls,
      "Mean_Value_mlogp" => mean_value_mlogp
    } = row

    with_measurement_odds_ratio =
      case with_measurement_odds_ratio do
        "inf" ->
          Float.max_finite()

        float_value ->
          float_value
      end

    case Map.get(endpoints, endpoint_name) do
      nil ->
        Logger.warning("Endpoint '#{endpoint_name}' not found, not importing data row.")
        nil

      fg_endpoint_id ->
        %{
          fg_endpoint_id: fg_endpoint_id,
          omop_concept_id: omop_concept_id,
          omop_concept_name: omop_concept_name,
          fg_endpoint_n_cases: fg_endpoint_n_cases,
          fg_endpoint_n_controls: fg_endpoint_n_controls,
          with_measurement_n_cases: with_measurement_n_cases,
          with_measurement_n_controls: with_measurement_n_controls,
          with_measurement_odds_ratio: with_measurement_odds_ratio,
          with_measurement_mlogp: with_measurement_mlogp,
          mean_n_measurements_cases: mean_n_measurements_cases,
          mean_n_measurements_controls: mean_n_measurements_controls,
          mean_value_n_cases: mean_value_n_cases,
          mean_value_n_controls: mean_value_n_controls,
          mean_value_unit: mean_value_unit,
          mean_value_cases: mean_value_cases,
          mean_value_controls: mean_value_controls,
          mean_value_mlogp: mean_value_mlogp
        }
    end
  end

  defp create_labwas_stats(attrs) do
    %Stats{}
    |> Stats.changeset(attrs)
    |> Repo.insert!()
  end
end
