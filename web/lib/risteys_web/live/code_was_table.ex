defmodule RisteysWeb.Live.CodeWASTable do
  use RisteysWeb, :live_view

  alias RisteysWeb.LiveTable
  alias RisteysWeb.LiveTable.Column

  @default_sorter "nlog10p_desc"

  def mount(_params, %{"endpoint" => endpoint}, socket) do
    columns = columns()
    init_form = to_form(%{"sorter" => @default_sorter})
    all_rows = Risteys.CodeWAS.list_codes(endpoint)

    socket =
      socket
      |> assign(:form, init_form)
      |> assign(:endpoint, endpoint)
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
    filename = "risteys_codewas_#{socket.assigns.endpoint.name}.csv"
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
  The CodeWAS table columns, in display order. Public so it can be exercised in tests.
  """
  def columns do
    [
      %Column{
        id: "code",
        label: "Code",
        csv_label: "Code",
        widget_class: "header-numbers codewas--data-grid-table--widget--code",
        filter: %{
          param: "code-filter",
          match: fn row, query -> substring?(row.code, query) end
        },
        cell: fn assigns ->
          ~H"""
          <div role="rowheader" class="font-mono" title={@row.code}><%= @row.code %></div>
          """
        end,
        csv_value: fn row -> row.code end
      },
      %Column{
        id: "vocabulary",
        label: "Vocabulary",
        csv_label: "Vocabulary",
        widget_class: "header-numbers codewas--data-grid-table--widget--vocabulary",
        filter: %{
          param: "vocabulary-filter",
          match: fn row, query ->
            namings = Risteys.CodeWAS.Codes.vocabulary_namings(row.vocabulary)

            substring?(row.vocabulary, query) or
              substring?(namings.short, query) or
              substring?(namings.full, query)
          end
        },
        cell: fn assigns ->
          ~H"""
          <div role="rowheader"><%= to_descriptive_vocabulary(@row.vocabulary) %></div>
          """
        end,
        csv_value: fn row -> Risteys.CodeWAS.Codes.vocabulary_namings(row.vocabulary).short end
      },
      %Column{
        id: "description",
        label: "Description",
        csv_label: "Description",
        widget_class: "codewas--data-grid-table--widget--description",
        filter: %{
          param: "description-filter",
          match: fn row, query ->
            not is_nil(row.description) and substring?(row.description, query)
          end
        },
        cell: fn assigns ->
          ~H"""
          <div role="gridcell" title={@row.description}><%= @row.description %></div>
          """
        end,
        csv_value: fn row -> row.description || "" end
      },
      %Column{
        id: "odds_ratio",
        label: "Odds Ratio",
        label_class: "header-numbers",
        csv_label: "Odds Ratio",
        widget_class: "header-numbers codewas--data-grid-table--widget--odds-ratio",
        sortable: true,
        sort_value: fn row -> row.odds_ratio end,
        cell: fn assigns ->
          ~H"""
          <div class="cell-numbers" role="gridcell"><%= display_odds_ratio(@row.odds_ratio) %></div>
          """
        end,
        csv_value: fn row -> display_odds_ratio(row.odds_ratio) end
      },
      %Column{
        id: "nlog10p",
        label: Phoenix.HTML.raw("-log<sub>10</sub>(p)"),
        label_class: "header-numbers",
        csv_label: "-log10(p)",
        widget_class: "header-numbers codewas--data-grid-table--widget--nlog10p",
        sortable: true,
        sort_value: fn row -> row.nlog10p end,
        cell: fn assigns ->
          ~H"""
          <div class="cell-numbers" role="gridcell">
            <%= :erlang.float_to_binary(@row.nlog10p, decimals: 1) %>
          </div>
          """
        end,
        csv_value: fn row -> :erlang.float_to_binary(row.nlog10p, decimals: 1) end
      },
      %Column{
        id: "n_matched_cases",
        label: "N matched cases",
        label_class: "header-numbers",
        csv_label: "N matched cases",
        widget_class: "header-numbers codewas--data-grid-table--widget--n-matched-cases",
        sortable: true,
        sort_value: fn row -> row.n_matched_cases end,
        cell: fn assigns ->
          ~H"""
          <div class="cell-numbers" role="gridcell"><%= mask_low_n(@row.n_matched_cases) %></div>
          """
        end,
        csv_value: fn row -> mask_low_n_csv(row.n_matched_cases) end
      },
      %Column{
        id: "n_matched_controls",
        label: "N matched controls",
        label_class: "header-numbers",
        csv_label: "N matched controls",
        widget_class: "header-numbers codewas--data-grid-table--widget--n-matched-controls",
        sortable: true,
        sort_value: fn row -> row.n_matched_controls end,
        cell: fn assigns ->
          ~H"""
          <div class="cell-numbers" role="gridcell"><%= mask_low_n(@row.n_matched_controls) %></div>
          """
        end,
        csv_value: fn row -> mask_low_n_csv(row.n_matched_controls) end
      }
    ]
  end

  defp substring?(value, query) do
    String.contains?(String.downcase(value), String.downcase(query))
  end

  defp display_odds_ratio(odds_ratio) do
    if odds_ratio == Float.max_finite() do
      "+∞"
    else
      :erlang.float_to_binary(odds_ratio, decimals: 1)
    end
  end

  defp mask_low_n(value) do
    if is_nil(value) do
      Phoenix.HTML.Tag.content_tag(:abbr, "*",
        title: "To safeguard privacy, we will not display the precise number of study subjects."
      )
    else
      value
    end
  end

  # Plain-text counterpart of mask_low_n/1 for CSV export: keep the privacy mask.
  defp mask_low_n_csv(value) do
    if is_nil(value), do: "*", else: to_string(value)
  end

  defp to_descriptive_vocabulary(value) do
    # TODO(Vincent) Use our abbr/2 function when we figure out a way that
    # the tooltip appears on top of everything when used in a table.
    namings = Risteys.CodeWAS.Codes.vocabulary_namings(value)

    tag =
      if not is_nil(namings.abbr) do
        :abbr
      else
        :span
      end

    Phoenix.HTML.Tag.content_tag(
      tag,
      namings.short,
      title: namings.full
    )
  end
end
