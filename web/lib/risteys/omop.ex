defmodule Risteys.OMOP do
  @moduledoc """
  The OMOP context.
  """

  import Ecto.Query, warn: false
  alias Risteys.Repo
  alias Risteys.OMOP.Concept
  alias Risteys.OMOP.ConceptRelationship

  require Logger

  @doc """
  List lab tests and their parent.
  """
  def get_lab_tests_tree() do
    Repo.all(
      from rel in ConceptRelationship,
        left_join: lab_test in Concept,
        on: rel.child_dbid == lab_test.id,
        left_join: parent in Concept,
        on: rel.parent_dbid == parent.id,
        select: %{
          lab_test_concept_id: lab_test.concept_id,
          lab_test_concept_name: lab_test.concept_name,
          parent_concept_id: parent.concept_id,
          parent_concept_name: parent.concept_name
        }
    )
    |> Enum.reduce(
      %{},
      fn rec, acc ->
        parent =
          %{
            parent_concept_id: rec.parent_concept_id,
            parent_concept_name: rec.parent_concept_name
          }

        new_child =
          %{
            lab_test_concept_id: rec.lab_test_concept_id,
            lab_test_concept_name: rec.lab_test_concept_name
          }

        children =
          acc
          |> Map.get(parent, MapSet.new())
          |> MapSet.put(new_child)

        Map.put(acc, parent, children)
      end
    )
    |> Enum.map(fn {parent, lab_tests} ->
      lab_tests = Enum.sort_by(lab_tests, fn %{lab_test_concept_name: name} -> name end)

      %{
        parent_concept_name: parent.parent_concept_name,
        parent_concept_id: parent.parent_concept_id,
        lab_tests: lab_tests
      }
    end)
    |> Enum.sort_by(fn %{parent_concept_name: name} -> name end)
  end

  @doc """
  Get a map from OMOP Concept IDs to the database IDs of the OMOP concepts.
  """
  def get_map_omop_ids() do
    Repo.all(
      from omop_concept in Concept,
        select: {omop_concept.concept_id, omop_concept.id}
    )
    |> Enum.into(%{})
  end

  @doc """
  Reset the OMOP concepts and relationships from files.
  """
  def import_lab_test_omop_concepts(
        subset_omop_ids_file_path,
        omop_concepts_file_path,
        omop_relationships_file_path
      ) do
    # 1. Scan the input files to build child/parent pairs with metadata.
    subset_children_concept =
      subset_omop_ids_file_path
      |> File.stream!()
      |> Stream.map(&JSON.decode!/1)
      |> Stream.map(fn %{"OMOP_CONCEPT_ID" => omop_id} -> omop_id end)
      |> Stream.reject(fn omop_id -> omop_id == "NA" end)
      |> Enum.into(MapSet.new())

    # NOTE(Vincent 2025-05-05) Loading all the concepts, even the one we will
    # eventually not import, for simplifying downstream processing, though this
    # takes a lot of memory, and probably more CPU time for the creation of all
    # the %{}.
    all_concepts =
      omop_concepts_file_path
      |> File.stream!()
      |> CSV.decode!(headers: true)
      |> Stream.map(fn row ->
        %{
          "concept_id" => concept_id,
          "concept_name" => concept_name,
          "vocabulary_id" => vocabulary_id
        } = row

        {concept_id, %{name: concept_name, vocabulary_id: vocabulary_id}}
      end)
      |> Enum.into(%{})

    child_parent_pairs =
      omop_relationships_file_path
      |> File.stream!()
      |> CSV.decode!(headers: true)
      |> Stream.filter(fn %{"concept_id_1" => row_concept_id} ->
        MapSet.member?(subset_children_concept, row_concept_id)
      end)
      |> Stream.filter(fn row ->
        %{
          "relationship_id" => relationship_id,
          "concept_id_1" => child_concept_id
        } = row

        child_metadata = Map.get(all_concepts, child_concept_id)

        (child_metadata.vocabulary_id == "LOINC" and relationship_id == "Has component") or
          (child_metadata.vocabulary_id == "SNOMED" and relationship_id == "Is a")
      end)
      |> Stream.map(fn %{"concept_id_1" => child_concept_id, "concept_id_2" => parent_concept_id} ->
        child_metadata = Map.get(all_concepts, child_concept_id)
        parent_metadata = Map.get(all_concepts, parent_concept_id)

        child = %{concept_id: child_concept_id, concept_name: child_metadata.name}
        parent = %{concept_id: parent_concept_id, concept_name: parent_metadata.name}

        {child, parent}
      end)

    # 2. Update the database.
    Logger.debug("Resetting all OMOP concepts and relationships in the database: Start.")

    Repo.transaction(fn ->
      Risteys.Repo.delete_all(ConceptRelationship)
      Risteys.Repo.delete_all(Concept)

      Enum.each(child_parent_pairs, fn {child_concept, parent_concept} ->
        create_concept_pair(child_concept, parent_concept)
      end)
    end)

    Logger.debug("Resetting all OMOP concepts and relationships in the database: End.")
  end

  defp create_concept_pair(child_concept, parent_concept) do
    Repo.transaction(fn ->
      # 1. Get or insert concepts
      child_concept_struct = get_or_insert_concept(child_concept)
      parent_concept_struct = get_or_insert_concept(parent_concept)

      # 2. Insert OMOP child / parent relationship
      %ConceptRelationship{}
      |> ConceptRelationship.changeset(%{
        child_dbid: child_concept_struct.id,
        parent_dbid: parent_concept_struct.id
      })
      |> Repo.insert!()
    end)
  end

  defp get_or_insert_concept(attrs) do
    case Repo.get_by(Concept, concept_id: attrs.concept_id) do
      nil -> create_concept(attrs)
      existing -> existing
    end
  end

  defp create_concept(attrs) do
    %Concept{}
    |> Concept.changeset(attrs)
    |> Repo.insert!()
  end

  def get_parent_concept(child_concept_id) do
    Repo.one(
      from child_concept in Concept,
        join: rel in ConceptRelationship,
        on: rel.child_dbid == child_concept.id,
        join: parent_concept in Concept,
        on: rel.parent_dbid == parent_concept.id,
        where: child_concept.concept_id == ^child_concept_id,
        select: parent_concept
    )
  end

  def list_children_lab_tests(parent_concept) do
    Repo.all(
      from child_concept in Concept,
        join: rel in ConceptRelationship,
        on: child_concept.id == rel.child_dbid,
        where: rel.parent_dbid == ^parent_concept.id,
        select: child_concept
    )
  end
end
