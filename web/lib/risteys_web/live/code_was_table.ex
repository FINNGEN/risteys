defmodule RisteysWeb.Live.CodeWASTable do
  use RisteysWeb, :live_view

  def mount(_params, %{"endpoint" => endpoint}, socket) do
    default_sorter = "nlog10p_desc"

    init_form = to_form(%{"sorter" => default_sorter})

    all_codes = Risteys.CodeWAS.list_codes(endpoint)

    socket =
      socket
      |> assign(:form, init_form)
      |> assign(:all_codes, all_codes)
      |> assign(:active_sorter, default_sorter)
      |> assign(:code_filter, "")
      |> assign(:vocabulary_filter, "")
      |> assign(:description_filter, "")
      |> assign(:display_codes, all_codes)

    {:ok, socket, layout: false}
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
      "code-filter" => code_filter,
      "vocabulary-filter" => vocabulary_filter,
      "description-filter" => description_filter
    } = filters

    socket =
      socket
      |> assign(:code_filter, code_filter)
      |> assign(:vocabulary_filter, vocabulary_filter)
      |> assign(:description_filter, description_filter)
      |> update_table()

    {:noreply, socket}
  end

  defp update_table(socket) do
    display_codes =
      socket.assigns.all_codes
      |> Enum.filter(fn row ->
        code_filter =
          String.contains?(
            String.downcase(row.code),
            String.downcase(socket.assigns.code_filter)
          )

        vocabulary_namings = Risteys.CodeWAS.Codes.vocabulary_namings(row.vocabulary)

        vocabulary_filter =
          String.contains?(
            String.downcase(row.vocabulary),
            String.downcase(socket.assigns.vocabulary_filter)
          ) or
            String.contains?(
              String.downcase(vocabulary_namings.short),
              String.downcase(socket.assigns.vocabulary_filter)
            ) or
            String.contains?(
              String.downcase(vocabulary_namings.full),
              String.downcase(socket.assigns.vocabulary_filter)
            )

        description_filter =
          if is_nil(row.description) do
            false
          else
            String.contains?(
              String.downcase(row.description),
              String.downcase(socket.assigns.description_filter)
            )
          end

        code_filter and vocabulary_filter and description_filter
      end)
      |> sort_with_nil(socket.assigns.active_sorter)

    assign(socket, :display_codes, display_codes)
  end

  defp sort_with_nil(elements, sorter) do
    {mapper, direction} =
      case sorter do
        "code_asc" ->
          {fn row -> String.downcase(row.code) end, :asc}

        "code_desc" ->
          {fn row -> String.downcase(row.code) end, :desc}

        "vocabulary_asc" ->
          {fn row -> String.downcase(row.vocabulary) end, :asc}

        "vocabulary_desc" ->
          {fn row -> String.downcase(row.vocabulary) end, :desc}

        "nlog10p_asc" ->
          {fn row -> row.nlog10p end, :asc}

        "nlog10p_desc" ->
          {fn row -> row.nlog10p end, :desc}

        "odds_ratio_asc" ->
          {fn row -> row.odds_ratio end, :asc}

        "odds_ratio_desc" ->
          {fn row -> row.odds_ratio end, :desc}

        "n_matched_cases_asc" ->
          {fn row -> row.n_matched_cases end, :asc}

        "n_matched_cases_desc" ->
          {fn row -> row.n_matched_cases end, :desc}

        "n_matched_controls_asc" ->
          {fn row -> row.n_matched_controls end, :asc}

        "n_matched_controls_desc" ->
          {fn row -> row.n_matched_controls end, :desc}
      end

    Enum.sort_by(elements, mapper, RisteysWeb.Utils.sorter_nil_is_0(direction))
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
