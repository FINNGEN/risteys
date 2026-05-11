defmodule Risteys.LabTestStats.QCTable do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_test_stats_qc_table" do
    field :test_name, :string
    field :measurement_unit_source, :string
    field :measurement_unit_harmonized, :string
    field :nrecords, :integer
    field :npeople, :integer
    field :percent_missing_measurement_value, :float
    field :test_outcome_counts, {:array, :map}
    field :distribution_measurement_values, :map
    field :omop_concept_dbid, :id

    timestamps()
  end

  @doc false
  def changeset(qc_table, attrs) do
    qc_table
    |> cast(attrs, [
      :omop_concept_dbid,
      :test_name,
      :measurement_unit_source,
      :measurement_unit_harmonized,
      :nrecords,
      :npeople,
      :percent_missing_measurement_value,
      :test_outcome_counts,
      :distribution_measurement_values
    ])
    |> validate_required([
      :omop_concept_dbid,
      :test_name,
      :nrecords,
      :npeople,
      :percent_missing_measurement_value
    ])
    |> unique_constraint([:omop_concept_dbid, :test_name, :measurement_unit_source])
  end
end
