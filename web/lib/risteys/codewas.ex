defmodule Risteys.CodeWAS do
  @moduledoc """
  The CodeWAS context
  """

  import Ecto.Query

  require Logger

  alias Risteys.Repo
  alias Risteys.CodeWAS
  alias Risteys.FGEndpoint

  def get_cohort_stats(endpoint) do
    Repo.one(
      from(cc in CodeWAS.Cohort,
        join: ee in FGEndpoint.Definition,
        on: cc.fg_endpoint_id == ee.id,
        where: ee.name == ^endpoint.name
      )
    )
  end

  def list_codes(endpoint) do
    Repo.all(
      from(cc in CodeWAS.Codes,
        join: ee in FGEndpoint.Definition,
        on: cc.fg_endpoint_id == ee.id,
        where: ee.name == ^endpoint.name,
        order_by: [desc: cc.nlog10p]
      )
    )
  end

  def import_file(codewas_file, codes_info) do
    codewas_file
    |> File.stream!()
    |> Enum.each(fn line ->
      line
      |> Jason.decode!()
      |> import_endpoint_codewas(codes_info)
    end)
  end

  def import_endpoint_codewas(codewas_data, codes_info) do
    %{
      "endpoint_name" => endpoint_name,
      "n_matched_cases" => n_matched_cases,
      "n_matched_controls" => n_matched_controls,
      "codes" => codes
    } = codewas_data

    endpoint = Repo.get_by(FGEndpoint.Definition, name: endpoint_name)

    case endpoint do
      nil ->
        Logger.warning(
          "Endpoint #{endpoint_name} not found in DB. Not importing CodeWAS cohort stats."
        )

      _ ->
        Logger.debug("Importing CodeWAS cohort data for endpoint #{endpoint_name}.")

        attrs = %{
          fg_endpoint_id: endpoint.id,
          n_matched_cases: n_matched_cases,
          n_matched_controls: n_matched_controls
        }

        Logger.debug("Parsing and importing CodeWAS codes data for endpoint #{endpoint.name}.")

        {:ok, _schema} =
          %CodeWAS.Cohort{}
          |> CodeWAS.Cohort.changeset(attrs)
          |> Repo.insert()

        for code_record <- codes do
          %{
            "code1" => code1,
            "code2" => code2,
            "code3" => code3,
            "description" => description,
            "vocabulary" => vocabulary,
            "odds_ratio" => odds_ratio,
            "nlog10p" => nlog10p,
            "n_matched_cases" => n_matched_cases,
            "n_matched_controls" => n_matched_controls
          } = code_record

          code_key = {code1, code2, code3, vocabulary}

          default_code =
            [code1, code2, code3]
            |> Enum.reject(fn cc -> cc == "NA" end)
            |> Enum.join(", ")

          code = Map.get(codes_info, code_key, default_code)

          odds_ratio =
            case odds_ratio do
              "Infinity" ->
                Float.max_finite()

              _ ->
                odds_ratio
            end

          attrs = %{
            fg_endpoint_id: endpoint.id,
            code: code,
            description: description,
            vocabulary: vocabulary,
            odds_ratio: odds_ratio,
            nlog10p: nlog10p,
            n_matched_cases: n_matched_cases,
            n_matched_controls: n_matched_controls
          }

          {:ok, _schema} =
            %CodeWAS.Codes{}
            |> CodeWAS.Codes.changeset(attrs)
            |> Repo.insert()
        end
    end
  end

  def build_codes_info(filepath) do
    filepath
    |> File.stream!()
    |> CSV.decode!(headers: true)
    # Convert empty strings to `nil` to account for missing values in CSV being decoded as empty
    # string, whereas JSON has a proper null.
    |> Stream.map(fn row ->
      for {key, val} <- row do
        if val == "" do
          {key, nil}
        else
          {key, val}
        end
      end
      |> Enum.into(%{})
    end)
    |> Enum.reduce(%{}, fn row, acc ->
      %{
        "FG_CODE1" => fg_code1,
        "FG_CODE2" => fg_code2,
        "FG_CODE3" => fg_code3,
        "code" => code,
        "vocabulary_id" => vocabulary
      } = row

      key = {fg_code1, fg_code2, fg_code3, vocabulary}

      Map.put(acc, key, code)
    end)
  end
end
