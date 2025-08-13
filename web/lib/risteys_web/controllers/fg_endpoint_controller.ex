defmodule RisteysWeb.FGEndpointController do
  use RisteysWeb, :controller

  alias Risteys.{
    Repo,
    FGEndpoint,
    KeyFigures,
    CodeWAS,
    LabWAS
  }

  import Ecto.Query

  def redirect_legacy_url(conn, %{"name" => name}) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/endpoints/#{name}")
  end

  def show(conn, %{"name" => name}) do
    # Directly returns a 404 when the given OMOP Concept ID is not in the database
    endpoint = Repo.get_by!(FGEndpoint.Definition, name: name)

    show_endpoint(conn, endpoint)
  end

  def redir_random(conn, _params) do
    endpoint = FGEndpoint.get_random_endpoint()

    redirect(conn, to: ~p"/endpoints/#{endpoint}")
  end

  def index_json(conn, _params) do
    endpoints = FGEndpoint.list_endpoint_names()

    conn
    |> assign(:endpoints, endpoints)
    |> render("index.json")
  end

  defp show_endpoint(conn, endpoint) do
    description =
      if not is_nil(endpoint.description) do
        endpoint.description
      else
        "No definition available."
      end

    ontology =
      if not is_nil(endpoint.ontology) do
        endpoint.ontology
      else
        %{}
      end

    # Get key figures
    key_figures_FG = get_key_figures(endpoint, "FG")
    key_figures_FR = get_key_figures(endpoint, "FR")
    key_figures_FR_index = get_key_figures(endpoint, "FR_index")

    # Variants in correlations
    authz_list_variants? =
      case get_session(conn, :user_is_authz) do
        # authz is nil when login was never done
        nil -> false
        authz -> authz
      end

    variants_by_corr =
      if authz_list_variants? do
        FGEndpoint.list_variants_by_correlation(endpoint)
      else
        []
      end

    # CodeWAS table
    codewas_cohort = CodeWAS.get_cohort_stats(endpoint)
    codewas_codes = CodeWAS.list_codes(endpoint)

    # LabWAS table
    labwas_rows = LabWAS.get_fgendpoint_labwas(endpoint)

    conn
    |> assign(:endpoint, endpoint)
    |> assign(:page_title, endpoint.name)
    |> assign(:replacements, FGEndpoint.find_replacement_endpoints(endpoint))
    |> assign(:explainer_steps, FGEndpoint.get_explainer_steps(endpoint))
    |> assign(:count_registries, FGEndpoint.get_count_registries(endpoint))
    |> assign(:ontology, ontology)
    |> assign(:broader_endpoints, FGEndpoint.broader_endpoints(endpoint))
    |> assign(:narrower_endpoints, FGEndpoint.narrower_endpoints(endpoint))
    |> assign(:key_figures_FG, key_figures_FG)
    |> assign(:key_figures_FR, key_figures_FR)
    |> assign(:key_figures_FR_index, key_figures_FR_index)
    |> assign(:description, description)
    |> assign(:mortality_data, Risteys.FGEndpoint.get_mortality_data(endpoint.name))
    |> assign(:has_drug_stats, FGEndpoint.has_drug_stats?(endpoint))
    |> assign(:authz_list_variants?, authz_list_variants?)
    |> assign(:variants_by_corr, variants_by_corr)
    |> assign(:codewas_cohort, codewas_cohort)
    |> assign(:codewas_codes, codewas_codes)
    |> assign(:labwas_rows, labwas_rows)
    |> render("show.html")
  end

  defp get_key_figures(endpoint, dataset) do
    key_fig =
      Repo.one(
        from kf in KeyFigures,
          where: kf.fg_endpoint_id == ^endpoint.id and kf.dataset == ^dataset,
          select: %{
            fg_endpoint_id: kf.fg_endpoint_id,
            nindivs_all: kf.nindivs_all,
            nindivs_female: kf.nindivs_female,
            nindivs_male: kf.nindivs_male,
            median_age_all: kf.median_age_all,
            median_age_female: kf.median_age_female,
            median_age_male: kf.median_age_male,
            prevalence_all: kf.prevalence_all,
            prevalence_female: kf.prevalence_female,
            prevalence_male: kf.prevalence_male,
            dataset: kf.dataset
          }
      )

    no_key_figures = %{
      fg_endpoint_id: "-",
      nindivs_all: "-",
      nindivs_female: "-",
      nindivs_male: "-",
      median_age_all: "-",
      median_age_female: "-",
      median_age_male: "-",
      prevalence_all: "-",
      prevalence_female: "-",
      prevalence_male: "-",
      dataset: "-"
    }

    # create and return key_figures
    case key_fig do
      nil ->
        no_key_figures

      _ ->
        Enum.reduce(
          key_fig,
          %{},
          fn {k, v}, acc ->
            case v do
              nil -> Map.put(acc, k, "-")
              _ -> Map.put(acc, k, v)
            end
          end
        )
    end
  end
end
