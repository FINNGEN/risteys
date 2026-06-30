defmodule RisteysWeb.LiveTable.Column do
  @moduledoc """
  One column of a `RisteysWeb.LiveTable`.

  CSS classes are carried explicitly (`:label_class`, `:widget_class`, and the body
  class inside the `:cell` closure) so the generic renderer can reproduce each
  table's existing `priv/static/css/app.css` grid contract without deriving names.
  """

  @enforce_keys [:id, :label, :csv_label, :cell, :csv_value]
  defstruct id: nil,
            # Display header (the per-column row). May be safe HTML, e.g. raw("-log<sub>10</sub>(p)").
            label: nil,
            label_class: nil,
            # Plain, group-qualified CSV header. Kept distinct from :label because
            # several columns share a short label under different top-header groups.
            csv_label: nil,
            # Optional grouped top-header (LabWAS). group is an id used for uniqueness;
            # group_label is the displayed text; group_class is the spanning CSS class.
            group: nil,
            group_label: nil,
            group_class: nil,
            # Whether this column shows asc/desc sorter buttons in the widget row.
            sortable: false,
            # nil | %{param: String.t(), match: (row, query :: String.t() -> boolean)}
            filter: nil,
            widget_class: nil,
            # Per-column nil sort semantics: :nil_is_0 (default) | :nil_at_end
            nil_sort: :nil_is_0,
            # (row -> term) used by sort/3
            sort_value: nil,
            # (assigns -> Phoenix.LiveView.Rendered) — renders the full body cell div
            cell: nil,
            # (row -> String.t()) — plain CSV value (privacy masking included)
            csv_value: nil
end
