defmodule RisteysWeb.Live.LabWASTable do
  use RisteysWeb, :live_view

  alias RisteysWeb.LiveTable
  alias RisteysWeb.LiveTable.Column

  @default_sorter "with-meas-mlog10p_desc"

  def mount(_params, session, socket) do
    init_form = to_form(%{"sorter" => @default_sorter})

    {facet, all_rows, download_name} =
      case session do
        %{"endpoint" => endpoint} ->
          {:endpoint, Risteys.LabWAS.get_fgendpoint_labwas(endpoint), endpoint.name}

        %{"lab_test_omop_id" => lab_test_omop_id} ->
          {:lab_test, Risteys.LabWAS.get_lab_test_labwas(lab_test_omop_id), lab_test_omop_id}
      end

    columns = columns(facet)

    socket =
      socket
      |> assign(:form, init_form)
      |> assign(:facet, facet)
      |> assign(:download_name, download_name)
      |> assign(:columns, columns)
      |> assign(:active_sorter, @default_sorter)
      |> assign(:filters, %{})
      |> assign(:all_rows, all_rows)
      # Initial load is sorted but unfiltered. Filtering starts on the first update_table event.
      |> assign(:display_rows, LiveTable.sort(all_rows, @default_sorter, columns))

    {:ok, socket, layout: false}
  end

  def handle_event("sort_table", %{"sorter" => sorter}, socket) do
    {:noreply, socket |> assign(:active_sorter, sorter) |> recompute()}
  end

  def handle_event("update_table", params, socket) do
    filters = Map.take(params, LiveTable.filter_params(socket.assigns.columns))
    {:noreply, socket |> assign(:filters, filters) |> recompute()}
  end

  def handle_event("download_csv", _params, socket) do
    content = LiveTable.to_csv(socket.assigns.display_rows, socket.assigns.columns)
    filename = "risteys_labwas_#{socket.assigns.download_name}.csv"
    {:noreply, push_event(socket, "download-csv", %{filename: filename, content: content})}
  end

  defp recompute(socket) do
    display_rows =
      LiveTable.view(
        socket.assigns.all_rows,
        socket.assigns.filters,
        socket.assigns.active_sorter,
        socket.assigns.columns
      )

    assign(socket, :display_rows, display_rows)
  end

  @doc """
  The LabWAS table columns for a given facet (`:endpoint` or `:lab_test`), in display
  order. The facet-specific identity column comes first; the 12 measurement columns
  are shared. Public so it can be exercised in tests.
  """
  def columns(facet) do
    [facet_column(facet) | measurement_columns()]
  end

  defp facet_column(:endpoint) do
    %Column{
      id: "facet",
      label: Phoenix.HTML.raw(~s|<span class="font-mono">(ID)</span> Name|),
      label_class: "facet",
      csv_label: "OMOP Concept",
      group: :facet,
      group_label: "OMOP Concept",
      group_class: "facet",
      widget_class: "facet",
      filter: %{
        param: "facet",
        match: fn row, query ->
          String.contains?(row.omop_concept_id, query) or
            String.contains?(
              String.downcase(row.omop_concept_name || ""),
              String.downcase(query)
            )
        end
      },
      cell: fn assigns ->
        ~H"""
        <div role="rowheader" title={@row.omop_concept_name}>
          <a href={~p"/lab-tests/#{@row.omop_concept_id}"}>
            (<span class="font-mono"><%= @row.omop_concept_id %></span>) <%= @row.omop_concept_name %>
          </a>
        </div>
        """
      end,
      csv_value: fn row -> "(#{row.omop_concept_id}) #{row.omop_concept_name}" end
    }
  end

  defp facet_column(:lab_test) do
    %Column{
      id: "facet",
      label: "Name",
      label_class: "facet",
      csv_label: "Endpoint",
      group: :facet,
      group_label: "Endpoint",
      group_class: "facet",
      widget_class: "facet",
      filter: %{
        param: "facet",
        match: fn row, query ->
          String.contains?(String.downcase(row.fg_endpoint_name), String.downcase(query)) or
            String.contains?(String.downcase(row.fg_endpoint_longname), String.downcase(query))
        end
      },
      cell: fn assigns ->
        ~H"""
        <div role="rowheader" title={@row.fg_endpoint_longname}>
          <a href={~p"/endpoints/#{@row.fg_endpoint_name}"}>
            <%= @row.fg_endpoint_longname %>
          </a>
        </div>
        """
      end,
      csv_value: fn row -> row.fg_endpoint_longname end
    }
  end

  defp measurement_columns do
    [
      # Group: People with measurements
      number_column(
        "with-meas-ncases",
        "N Cases",
        "People with measurements: N Cases",
        "with-meas",
        :with_measurement_n_cases,
        &int_str/1
      )
      |> with_group("People with measurements"),
      number_column(
        "with-meas-ncontrols",
        "N Controls",
        "People with measurements: N Controls",
        "with-meas",
        :with_measurement_n_controls,
        &int_str/1
      ),
      number_column(
        "with-meas-odds-ratio",
        "OR",
        "People with measurements: OR",
        "with-meas",
        :with_measurement_odds_ratio,
        &or_str/1
      ),
      number_column(
        "with-meas-mlog10p",
        Phoenix.HTML.raw("-log<sub>10</sub>(p)"),
        "People with measurements: -log10(p)",
        "with-meas",
        :with_measurement_mlogp,
        &p2/1
      ),

      # Group: Mean N measurements
      number_column(
        "mean-nmeas-cases",
        "cases",
        "Mean N measurements: cases",
        "mean-nmeas",
        :mean_n_measurements_cases,
        &n1/1
      )
      |> with_group("Mean N measurements"),
      number_column(
        "mean-nmeas-controls",
        "controls",
        "Mean N measurements: controls",
        "mean-nmeas",
        :mean_n_measurements_controls,
        &n1/1
      ),

      # Group: Mean measured value
      number_column(
        "mean-value-cases",
        "cases",
        "Mean measured value: cases",
        "mean-value",
        :mean_value_cases,
        &mv2/1
      )
      |> with_group("Mean measured value"),
      number_column(
        "mean-value-controls",
        "controls",
        "Mean measured value: controls",
        "mean-value",
        :mean_value_controls,
        &mv2/1
      ),
      unit_column(),
      number_column(
        "mean-value-mlog10p",
        Phoenix.HTML.raw("-log<sub>10</sub>(p)"),
        "Mean measured value: -log10(p)",
        "mean-value",
        :mean_value_mlogp,
        &mv2/1
      ),
      number_column(
        "mean-value-ncases",
        "N cases",
        "Mean measured value: N cases",
        "mean-value",
        :mean_value_n_cases,
        &int_str/1
      ),
      number_column(
        "mean-value-ncontrols",
        "N controls",
        "Mean measured value: N controls",
        "mean-value",
        :mean_value_n_controls,
        &int_str/1
      )
    ]
  end

  # A numeric, sortable column. `field` is the row key; `formatter` turns the value
  # into the displayed/CSV string (so display and export cannot drift).
  defp number_column(id, label, csv_label, group_class, field, formatter) do
    %Column{
      id: id,
      label: label,
      label_class: "#{group_class} header-numbers",
      csv_label: csv_label,
      group_class: group_class,
      widget_class: "#{group_class} header-numbers",
      sortable: true,
      sort_value: fn row -> Map.get(row, field) end,
      cell: fn assigns ->
        # Compute the displayed value in plain Elixir; the template only reads @value
        # (referencing the captured `field`/`formatter` inside ~H would disable change
        # tracking and warn).
        assigns = Map.put(assigns, :value, formatter.(Map.get(assigns.row, field)))

        ~H"""
        <div class="cell-numbers" role="gridcell"><%= @value %></div>
        """
      end,
      csv_value: fn row -> formatter.(Map.get(row, field)) end
    }
  end

  defp unit_column do
    %Column{
      id: "mean-value-unit",
      label: "unit",
      label_class: "mean-value col-unit",
      csv_label: "Mean measured value: unit",
      group_class: "mean-value",
      widget_class: "mean-value col-unit",
      filter: %{
        param: "mean-value-unit",
        match: fn row, query ->
          String.contains?(
            String.downcase(row.mean_value_unit || ""),
            String.downcase(query)
          )
        end
      },
      cell: fn assigns ->
        ~H"""
        <div class="col-unit" role="gridcell"><%= @row.mean_value_unit %></div>
        """
      end,
      csv_value: fn row -> row.mean_value_unit || "" end
    }
  end

  # Mark a column as the first of its group so the top-header row gets one spanning cell.
  defp with_group(column, group_label) do
    %{column | group: String.to_atom(column.group_class), group_label: group_label}
  end

  defp int_str(value), do: to_string(value)

  defp or_str(value) do
    if value == Float.max_finite() do
      "+∞"
    else
      :erlang.float_to_binary(value, decimals: 2)
    end
  end

  # -log10(p) and other always-present floats, 2 decimals.
  defp p2(value), do: :erlang.float_to_binary(value, decimals: 2)

  # Mean N measurements, always-present floats, 1 decimal.
  defp n1(value), do: :erlang.float_to_binary(value, decimals: 1)

  # Mean measured value floats, nil-safe, 2 decimals.
  defp mv2(nil), do: "—"
  defp mv2(value), do: :erlang.float_to_binary(value, decimals: 2)
end
