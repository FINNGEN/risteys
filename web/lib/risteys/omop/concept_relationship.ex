defmodule Risteys.OMOP.ConceptRelationship do
  use Ecto.Schema
  import Ecto.Changeset

  schema "omop_concept_relationships" do
    field :child_dbid, :id
    field :parent_dbid, :id

    timestamps()
  end

  @doc false
  def changeset(concept_relationship, attrs) do
    concept_relationship
    |> cast(attrs, [:child_dbid, :parent_dbid])
    |> validate_required([:child_dbid, :parent_dbid])
    |> unique_constraint([:child_dbid, :parent_dbid],
      name: :uidx_omop_concept_relationships
    )
  end
end
