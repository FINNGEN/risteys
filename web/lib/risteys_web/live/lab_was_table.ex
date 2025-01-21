defmodule RisteysWeb.Live.LabWASTable do
  use RisteysWeb, :live_view

  def mount(_params, session, socket) do
    default_sorter = "with-meas-mlog10p_desc"
    init_form = to_form(%{"sorter" => default_sorter})

    socket =
      case session do
        %{"endpoint" => endpoint} ->
          set_facet_assigns(socket, :endpoint, endpoint)

        %{"lab_test_omop_id" => lab_test_omop_id} ->
          set_facet_assigns(socket, :lab_test, lab_test_omop_id)
      end

    socket =
      socket
      |> assign(:form, init_form)
      |> assign(:filter_facet, "")
      |> assign(:filter_unit, "")
      |> assign(:active_sorter, default_sorter)
      |> assign(:display_rows, socket.assigns.all_labwas_rows)

    {:ok, socket, layout: false}
  end

  def set_facet_assigns(socket, :endpoint, endpoint) do
    assigns = %{}

    facet_header = ~H"""
    <span class="font-mono">(ID)</span> Name
    """

    socket
    |> assign(:facet, :endpoint)
    |> assign(:all_labwas_rows, Risteys.LabWAS.get_fgendpoint_labwas(endpoint))
    |> assign(:facet_top_header, "OMOP Concept")
    |> assign(:facet_header, facet_header)
  end

  def set_facet_assigns(socket, :lab_test, lab_test_omop_id) do
    socket
    |> assign(:facet, :lab_test)
    |> assign(:all_labwas_rows, Risteys.LabWAS.get_lab_test_labwas(lab_test_omop_id))
    |> assign(:facet_top_header, "Endpoint")
    |> assign(:facet_header, "Name")
  end

  def render_facet_row_index(%{facet: :endpoint} = assigns) do
    ~H"""
    <div role="rowheader" title={@row.omop_concept_name}>
      <a href={~p"/lab-tests/#{@row.omop_concept_id}"}>
        (<span class="font-mono"><%= @row.omop_concept_id %></span>) <%= @row.omop_concept_name %>
      </a>
    </div>
    """
  end

  def render_facet_row_index(%{facet: :lab_test} = assigns) do
    ~H"""
    <div role="rowheader" title={@row.fg_endpoint_longname}>
      <a href={~p"/endpoints/#{@row.fg_endpoint_name}"}>
        <%= @row.fg_endpoint_longname %>
      </a>
    </div>
    """
  end

  def handle_event("sort_table", %{"sorter" => sorter}, socket) do
    socket =
      socket
      |> assign(:active_sorter, sorter)
      |> update_table()

    {:noreply, socket}
  end

  def handle_event("update_table", filters, socket) do
    %{
      "facet" => filter_facet,
      "mean-value-unit" => filter_unit
    } = filters

    socket =
      socket
      |> assign(:filter_facet, filter_facet)
      |> assign(:filter_unit, filter_unit)
      |> update_table()

    {:noreply, socket}
  end

  defp update_table(socket) do
    display_rows =
      socket.assigns.all_labwas_rows
      |> Enum.filter(fn row ->
        filter_facet = apply_filter_facet(socket.assigns.facet, row, socket.assigns.filter_facet)

        filter_unit =
          String.contains?(
            String.downcase(row.mean_value_unit || ""),
            String.downcase(socket.assigns.filter_unit)
          )

        filter_facet and filter_unit
      end)
      |> sort_with_nil(socket.assigns.active_sorter)

    assign(socket, :display_rows, display_rows)
  end

  defp apply_filter_facet(:endpoint, row, text_filter) do
    filter_omop_id = String.contains?(row.omop_concept_id, text_filter)

    filter_omop_name =
      String.contains?(
        String.downcase(row.omop_concept_name || ""),
        String.downcase(text_filter)
      )

    filter_omop_id or filter_omop_name
  end

  defp apply_filter_facet(:lab_test, row, text_filter) do
    filter_fg_endpoint_name =
      String.contains?(
        String.downcase(row.fg_endpoint_name),
        String.downcase(text_filter)
      )

    filter_fg_endpoint_longname =
      String.contains?(
        String.downcase(row.fg_endpoint_longname),
        String.downcase(text_filter)
      )

    filter_fg_endpoint_name or filter_fg_endpoint_longname
  end

  defp sort_with_nil(elements, sorter) do
    {mapper, direction} =
      case sorter do
        "with-meas-ncases_asc" ->
          {fn row -> row.with_measurement_n_cases end, :asc}

        "with-meas-ncases_desc" ->
          {fn row -> row.with_measurement_n_cases end, :desc}

        "with-meas-ncontrols_asc" ->
          {fn row -> row.with_measurement_n_controls end, :asc}

        "with-meas-ncontrols_desc" ->
          {fn row -> row.with_measurement_n_controls end, :desc}

        "with-meas-odds-ratio_asc" ->
          {fn row -> row.with_measurement_odds_ratio end, :asc}

        "with-meas-odds-ratio_desc" ->
          {fn row -> row.with_measurement_odds_ratio end, :desc}

        "with-meas-mlog10p_asc" ->
          {fn row -> row.with_measurement_mlogp end, :asc}

        "with-meas-mlog10p_desc" ->
          {fn row -> row.with_measurement_mlogp end, :desc}

        "mean-nmeas-cases_asc" ->
          {fn row -> row.mean_n_measurements_cases end, :asc}

        "mean-nmeas-cases_desc" ->
          {fn row -> row.mean_n_measurements_cases end, :desc}

        "mean-nmeas-controls_asc" ->
          {fn row -> row.mean_n_measurements_controls end, :asc}

        "mean-nmeas-controls_desc" ->
          {fn row -> row.mean_n_measurements_controls end, :desc}

        "mean-value-cases_asc" ->
          {fn row -> row.mean_value_cases end, :asc}

        "mean-value-cases_desc" ->
          {fn row -> row.mean_value_cases end, :desc}

        "mean-value-controls_asc" ->
          {fn row -> row.mean_value_controls end, :asc}

        "mean-value-controls_desc" ->
          {fn row -> row.mean_value_controls end, :desc}

        "mean-value-mlog10p_asc" ->
          {fn row -> row.mean_value_mlogp end, :asc}

        "mean-value-mlog10p_desc" ->
          {fn row -> row.mean_value_mlogp end, :desc}

        "mean-value-ncases_asc" ->
          {fn row -> row.mean_value_n_cases end, :asc}

        "mean-value-ncases_desc" ->
          {fn row -> row.mean_value_n_cases end, :desc}

        "mean-value-ncontrols_asc" ->
          {fn row -> row.mean_value_n_controls end, :asc}

        "mean-value-ncontrols_desc" ->
          {fn row -> row.mean_value_n_controls end, :desc}
      end

    Enum.sort_by(elements, mapper, RisteysWeb.Utils.sorter_nil_is_0(direction))
  end
end
