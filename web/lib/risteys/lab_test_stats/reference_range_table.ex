defmodule Risteys.LabTestStats.ReferenceRangeTable do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_test_stats_reference_range_table" do
    field :omop_concept_dbid, :id
    field :reference_range, :string
    field :nrecords, :integer
    field :npeople, :integer

    timestamps()
  end

  @doc false
  def changeset(reference_range_table, attrs) do
    reference_range_table
    |> cast(attrs, [:omop_concept_dbid, :reference_range, :nrecords, :npeople])
    |> validate_required([:omop_concept_dbid, :nrecords, :npeople])
    |> validate_change(:npeople, &Risteys.Utils.is_green/2)
    |> unique_constraint([:omop_concept_dbid, :reference_range])
  end
end
