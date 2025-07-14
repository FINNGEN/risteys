defmodule Risteys.CodeWAS.Codes do
  use Ecto.Schema
  import Ecto.Changeset

  schema "codewas_codes" do
    field(:code, :string)
    field(:description, :string)
    field(:vocabulary, :string)
    field(:odds_ratio, :float)
    field(:nlog10p, :float)
    field(:n_matched_cases, :integer)
    field(:n_matched_controls, :integer)
    field(:fg_endpoint_id, :id)

    timestamps()
  end

  @doc false
  def changeset(codewas_codes, attrs) do
    codewas_codes
    |> cast(attrs, [
      :code,
      :vocabulary,
      :description,
      :odds_ratio,
      :nlog10p,
      :n_matched_cases,
      :n_matched_controls,
      :fg_endpoint_id
    ])
    |> validate_required([:code, :vocabulary, :odds_ratio, :nlog10p, :fg_endpoint_id])
    |> validate_change(:n_matched_cases, &Risteys.Utils.is_green/2)
    |> validate_change(:n_matched_controls, &Risteys.Utils.is_green/2)
    |> unique_constraint(:codewas_codes)
  end

  def vocabulary_namings(vocabulary) do
    %{
      "ATC" => %{
        abbr: "ATC",
        short: "ATC",
        full: "Anatomical Therapeutic Chemical Classification System"
      },
      "FHL" => %{
        abbr: "FHL",
        short: "FHL",
        full: "Finnish Hospital League"
      },
      "HPN" => %{
        abbr: "HP",
        short: "HP",
        full: "Heart Patients"
      },
      "HPO" => %{
        abbr: "HP",
        short: "HP",
        full: "Heart Patients"
      },
      "ICD10fi" => %{
        abbr: nil,
        short: "ICD-10 Finland",
        full: "ICD-10 Finland"
      },
      "ICD9fi" => %{
        abbr: nil,
        short: "ICD-9 Finland",
        full: "ICD-9 Finland"
      },
      "ICD8fi" => %{
        abbr: nil,
        short: "ICD-8 Finland",
        full: "ICD-8 Finland"
      },
      "ICDO3" => %{
        abbr: nil,
        short: "ICD-O-3",
        full: "ICD-O-3"
      },
      "ICPC" => %{
        abbr: "ICPC",
        short: "ICPC",
        full: "International Classification of Primary Care"
      },
      "REIMB" => %{
        abbr: nil,
        short: "Kela drug reimbursment",
        full: "Kela drug reimbursment"
      },
      "SPAT" => %{
        abbr: nil,
        short: "SPAT",
        full: "Finnish primary care outpatient procedures"
      },
      "NCSPfi" => %{
        abbr: nil,
        short: "NOMESCO Finland",
        full: "NOMESCO Classification of Surgical Procedures (Finland)"
      }
    }
    |> Map.get(vocabulary, %{abbr: nil, short: vocabulary, full: vocabulary})
  end
end
