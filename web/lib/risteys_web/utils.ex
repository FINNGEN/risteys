defmodule RisteysWeb.Utils do
  @doc """
  Custom sorter that puts nil values at the end.
  To be used as the sorter of Enum.sort_by/3
  """
  def sorter_nil_end(direction) do
    fn aa, bb ->
      case {aa, bb, direction} do
        {nil, _, _} -> false
        {_, nil, _} -> true
        {_, _, :asc} -> aa < bb
        {_, _, :desc} -> aa > bb
      end
    end
  end

  @doc """
  Custom sorter that considers nil values to be just below 0.
  To be used as the sorter of Enum.sort_by/3
  """
  def sorter_nil_is_0(direction) do
    fn aa, bb ->
      case {aa, bb, direction} do
        {nil, 0, :asc} -> true
        {nil, 0, :desc} -> false
        {0, nil, :asc} -> false
        {0, nil, :desc} -> true
        {nil, _, :asc} -> 0 < bb
        {nil, _, :desc} -> 0 > bb
        {_, nil, :asc} -> 0 > aa
        {_, nil, :desc} -> 0 < aa
        {_, _, :asc} -> aa < bb
        {_, _, :desc} -> aa > bb
      end
    end
  end

  @doc """
  Generate an text input field for a Live View.
  """
  def text_input_field(name, form_id, value, placeholder) do
    Phoenix.HTML.Tag.tag(
      :input,
      type: "text",
      name: name,
      form: form_id,
      value: value,
      placeholder: placeholder
    )
  end

  @doc """
  Generate a pair of asc/desc sorting button for a Live View.
  """
  def sorter_buttons(column, form_id, active_sorter) do
    [
      gen_button(:asc, column, form_id, active_sorter),
      gen_button(:desc, column, form_id, active_sorter)
    ]
  end

  defp gen_button(direction, column, form_id, active_sorter) do
    content =
      case direction do
        :asc ->
          "▲"

        :desc ->
          "▼"
      end

    value =
      case direction do
        :asc ->
          column <> "_asc"

        :desc ->
          column <> "_desc"
      end

    class =
      case {direction, active_sorter} do
        {:asc, ^value} ->
          "radio-left active"

        {:asc, _} ->
          "radio-left"

        {:desc, ^value} ->
          "radio-right active"

        {:desc, _} ->
          "radio-right"
      end

    Phoenix.HTML.Tag.content_tag(
      :button,
      content,
      name: "sorter",
      value: value,
      form: form_id,
      class: class
    )
  end

  def round_and_str(number, precision) do
    case number do
      nil ->
        "—"

      _ ->
        :io_lib.format("~.#{precision}. f", [number]) |> to_string()
    end
  end

  @doc """
  Takes a string number, parse it as an integer or a float, and return the parsed number.
  """
  def parse_number(number_str) do
    case {Integer.parse(number_str), Float.parse(number_str)} do
      {{parsed_integer, ""}, _} -> parsed_integer
      {{_parsed, _remainder}, {parsed_float, ""}} -> parsed_float
    end
  end

  def pretty_number(number, float_decimal_places \\ 2)

  def pretty_number(number, _float_decimal_places) when is_integer(number) do
    pretty_number_str_to_int(number)
  end

  def pretty_number(number, decimal_places) when is_float(number) do
    pretty_number_str_to_float(number, decimal_places)
  end

  defp pretty_number_str_to_int(number) do
    number
    |> Integer.to_string()
    |> pretty_str_number()
  end

  defp pretty_number_str_to_float(number, decimal_places) do
    [left, right] =
      number
      |> :erlang.float_to_binary(decimals: decimal_places)
      |> String.split(".")

    [
      pretty_str_number(left),
      right
    ]
    |> Enum.join(".")
  end

  defp pretty_str_number(str_number) do
    non_breaking_space = " "

    str_number
    |> String.split("", trim: true)
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.intersperse([non_breaking_space])
    |> Enum.concat()
    |> Enum.reverse()
    |> Enum.join()
  end
end
