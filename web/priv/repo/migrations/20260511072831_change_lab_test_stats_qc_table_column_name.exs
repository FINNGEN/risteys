defmodule Risteys.Repo.Migrations.ChangeLabTestStatsQcTableColumnName do
  use Ecto.Migration

  def change do
    drop index(:lab_test_stats_qc_table, [:omop_concept_dbid, :test_name, :measurement_unit])
    rename table(:lab_test_stats_qc_table), :measurement_unit, to: :measurement_unit_source
    create unique_index(:lab_test_stats_qc_table, [:omop_concept_dbid, :test_name, :measurement_unit_source])
  end
end
