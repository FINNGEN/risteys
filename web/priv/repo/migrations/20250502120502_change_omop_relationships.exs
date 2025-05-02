defmodule Risteys.Repo.Migrations.ChangeOmopRelationships do
  use Ecto.Migration

  def change do
    # Remove existing indexes (will be recreated at the end)
    drop index(:omop_loinc_relationships, [:lab_test_id])
    drop index(:omop_loinc_relationships, [:loinc_component_id])

    drop unique_index(
           :omop_loinc_relationships,
           [:lab_test_id, :loinc_component_id],
           name: :uidx_omop_loinc_relationships
         )

    # Renaming of table name and table columns
    rename table("omop_loinc_relationships"), to: table("omop_concept_relationships")

    rename table("omop_concept_relationships"), :lab_test_id, to: :child_dbid
    rename table("omop_concept_relationships"), :loinc_component_id, to: :parent_dbid

    # Recreate the index
    create index(:omop_concept_relationships, [:child_dbid])
    create index(:omop_concept_relationships, [:parent_dbid])

    create unique_index(
             :omop_concept_relationships,
             [:child_dbid, :parent_dbid],
             name: :uidx_omop_concept_relationships
           )
  end
end
