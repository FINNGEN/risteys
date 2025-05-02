defmodule RisteysWeb.LabTestController do
  use RisteysWeb, :controller

  def index(conn, _params) do
    lab_tests_tree_stats =
      Risteys.OMOP.get_lab_tests_tree()
      |> Risteys.LabTestStats.merge_stats()

    conn
    |> assign(:page_title, "Lab tests")
    |> assign(:lab_tests_tree_stats, lab_tests_tree_stats)
    |> assign(:lab_tests_overall_stats, Risteys.LabTestStats.get_overall_stats())
    |> render(:index)
  end

  def show(conn, %{"omop_id" => omop_id} = _params) do
    url_athena_base = "https://athena.ohdsi.org/search-terms/terms/"

    link_athena_lab_test =
      RisteysWeb.CustomHTMLHelpers.ahref_extern(url_athena_base <> omop_id, "OHDSI Athena")

    # OMOP collection
    parent_concept = Risteys.OMOP.get_parent_concept(omop_id)

    n_in_collection =
      parent_concept
      |> Risteys.OMOP.list_children_lab_tests()
      |> length()

    n_other_in_collection = n_in_collection - 1

    link_athena_parent_concept =
      RisteysWeb.CustomHTMLHelpers.ahref_extern(
        url_athena_base <> parent_concept.concept_id,
        "OHDSI Athena"
      )

    pretty_stats =
      omop_id
      |> Risteys.LabTestStats.get_single_lab_test_stats()
      |> RisteysWeb.LabTestHTML.show_prettify_stats()

    conn
    |> assign(:omop_concept_id, omop_id)
    |> assign(:link_athena_lab_test, link_athena_lab_test)
    |> assign(:parent_concept, parent_concept)
    |> assign(:n_other_in_collection, n_other_in_collection)
    |> assign(:link_athena_parent_concept, link_athena_parent_concept)
    |> assign(:lab_test, pretty_stats)
    |> render()
  end

  def redir_random(conn, _params) do
    lab_test_omop_id = Risteys.LabTestStats.get_random_omop_id()

    redirect(conn, to: ~p"/lab-tests/#{lab_test_omop_id}")
  end
end
