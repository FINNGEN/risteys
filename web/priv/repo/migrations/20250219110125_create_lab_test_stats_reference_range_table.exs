defmodule Risteys.Repo.Migrations.CreateLabTestStatsReferenceRangeTable do
  use Ecto.Migration

  def change do
    create table(:lab_test_stats_reference_range_table) do
      add :omop_concept_dbid, references(:omop_concepts, on_delete: :delete_all), null: false
      add :reference_range, :string, null: true
      add :nrecords, :integer, null: false
      add :npeople, :integer, null: false

      timestamps()
    end

    create unique_index(
             :lab_test_stats_reference_range_table,
             [:omop_concept_dbid, :reference_range]
           )
  end
end
