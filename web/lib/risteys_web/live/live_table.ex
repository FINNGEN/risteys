defmodule RisteysWeb.LiveTable do
  @moduledoc """
  Shared base for the interactive tables (CodeWAS, LabWAS).

  A table is described as a list of `%RisteysWeb.LiveTable.Column{}` (columns-as-data).
  The same column list drives:
    * sorting (`sort/3`) — each column carries its own sort value and nil semantics,
    * filtering (`filter/3`) — each filterable column carries its own match function,
    * CSV export (`to_csv/2`) — each column carries a plain-text value function and a
      group-qualified CSV header label,
    * rendering (`table/1`) — a generic function component that lays out the header
      rows (optional grouped top-header + label row + widget row) and the body.

  The owning LiveView keeps the full dataset and the filtered+sorted view, and only
  needs thin `handle_event/3` clauses that delegate to `view/4` and `to_csv/2`.

  CSV download is delivered with `Phoenix.LiveView.push_event(socket, "download-csv",
  %{filename: ..., content: ...})`; LiveView dispatches this as a `phx:download-csv`
  window event handled in `assets/js/app.js`.
  """
  use RisteysWeb, :html

  alias RisteysWeb.LiveTable.Column

  @doc """
  Filter then sort `rows` for display.

    * `filters` is a map of `%{param_name => query_string}` as sent by the table's
      `phx-change` form.
    * `sorter` is the active sorter value, e.g. `"nlog10p_desc"`.
  """
  def view(rows, filters, sorter, columns) do
    rows
    |> filter(filters, columns)
    |> sort(sorter, columns)
  end

  @doc """
  The filter param names declared by the columns. Use it in `update_table` to keep
  only the relevant keys from the `phx-change` params (which also include `_target`).
  """
  def filter_params(columns) do
    for %Column{filter: %{param: param}} <- columns, do: param
  end

  @doc """
  Keep the rows matching every filterable column's match function.

  An empty/absent query matches everything (substring of `""`).
  """
  def filter(rows, filters, columns) do
    active =
      for %Column{filter: %{param: param, match: match}} <- columns do
        {Map.get(filters, param, ""), match}
      end

    Enum.filter(rows, fn row ->
      Enum.all?(active, fn {query, match} -> match.(row, query) end)
    end)
  end

  @doc """
  Sort `rows` by the column targeted by `sorter` (e.g. `"odds_ratio_desc"`).

  The column's `:nil_sort` selects the nil-handling comparator from
  `RisteysWeb.Utils`. An unknown sorter leaves the rows untouched.
  """
  def sort(rows, sorter, columns) do
    {base, direction} =
      cond do
        String.ends_with?(sorter, "_asc") -> {String.replace_suffix(sorter, "_asc", ""), :asc}
        String.ends_with?(sorter, "_desc") -> {String.replace_suffix(sorter, "_desc", ""), :desc}
        true -> {sorter, :desc}
      end

    case Enum.find(columns, &(&1.id == base)) do
      nil ->
        rows

      %Column{sort_value: sort_value, nil_sort: nil_sort} ->
        comparator =
          case nil_sort do
            :nil_at_end -> RisteysWeb.Utils.sorter_nil_end(direction)
            _ -> RisteysWeb.Utils.sorter_nil_is_0(direction)
          end

        Enum.sort_by(rows, sort_value, comparator)
    end
  end

  @doc """
  Build the CSV text for the current `rows`, one column per `csv_label` header and
  one value per column's `:csv_value`. Returns the displayed representation
  (privacy masking included).
  """
  def to_csv(rows, columns) do
    header = Enum.map(columns, & &1.csv_label)

    data =
      Enum.map(rows, fn row ->
        Enum.map(columns, & &1.csv_value.(row))
      end)

    [header | data]
    |> CSV.encode()
    |> Enum.join("")
  end

  attr :id, :string, required: true, doc: "table id; the hidden form id is derived as form-<id>"
  attr :grid_class, :string, required: true, doc: "full class list for the role=grid container"
  attr :columns, :list, required: true, doc: "list of %RisteysWeb.LiveTable.Column{}"
  attr :rows, :list, required: true, doc: "the rows currently displayed (already filtered+sorted)"
  attr :form, :any, required: true, doc: "Phoenix.HTML.Form backing the hidden sort/filter form"
  attr :active_sorter, :string, required: true
  attr :filters, :map, default: %{}, doc: "current filter values keyed by param name"
  attr :download_label, :string, default: "Download table (CSV)"

  def table(assigns) do
    groups =
      assigns.columns
      |> Enum.filter(& &1.group)
      |> Enum.uniq_by(& &1.group)
      |> Enum.map(fn col -> %{label: col.group_label, class: col.group_class} end)

    assigns =
      assigns
      |> assign(:form_id, "form-#{assigns.id}")
      |> assign(:groups, groups)
      |> assign(:has_groups, groups != [])

    ~H"""
    <div class="live-table">
      <div class="live-table--toolbar">
        <button type="button" class="live-table--download-button" phx-click="download_csv">
          <%= @download_label %>
        </button>
      </div>

      <div class={@grid_class} role="grid">
        <div role="rowgroup">
          <div :if={@has_groups} role="row">
            <div :for={group <- @groups} class={"#{group.class} top-header"} role="columnheader">
              <%= group.label %>
            </div>
          </div>

          <div role="row">
            <div :for={col <- @columns} class={col.label_class} role="columnheader">
              <%= col.label %>
            </div>
          </div>

          <div role="row">
            <.form
              for={@form}
              id={@form_id}
              phx-submit="sort_table"
              phx-change="update_table"
              style="display: none;"
            >
            </.form>
            <div :for={col <- @columns} class={col.widget_class} role="columnheader">
              <%= cond do %>
                <% col.sortable -> %>
                  <%= RisteysWeb.Utils.sorter_buttons(col.id, @form_id, @active_sorter) %>
                <% col.filter -> %>
                  <%= RisteysWeb.Utils.text_input_field(
                    col.filter.param,
                    @form_id,
                    Map.get(@filters, col.filter.param, ""),
                    "type to filter"
                  ) %>
                <% true -> %>
              <% end %>
            </div>
          </div>
        </div>

        <div role="rowgroup">
          <div :for={row <- @rows} role="row">
            <%= for col <- @columns do %>
              <%= col.cell.(%{row: row}) %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
