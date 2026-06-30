defmodule RisteysWeb.LiveTableTest do
  @moduledoc """
  Characterization tests for the shared interactive-table base. They lock the
  sort/filter/CSV behaviour that the CodeWAS and LabWAS tables relied on before the
  refactor, exercising the *real* column definitions (their match/sort_value/csv_value
  functions), not stand-ins.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias RisteysWeb.LiveTable
  alias RisteysWeb.LiveTable.Column
  alias RisteysWeb.Live.CodeWASTable
  alias RisteysWeb.Live.LabWASTable

  @endpoint RisteysWeb.Endpoint

  defp csv_rows(csv) do
    csv
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.map(&String.split(&1, ","))
  end

  defp code_row(attrs), do: struct(Risteys.CodeWAS.Codes, attrs)
  defp labwas_endpoint_row(attrs), do: struct(Risteys.LabWAS.Stats, attrs)

  describe "sort/3 with :nil_is_0 (CodeWAS/LabWAS default)" do
    defp num_col(nil_sort \\ :nil_is_0) do
      %Column{
        id: "v",
        label: "v",
        csv_label: "v",
        sortable: true,
        nil_sort: nil_sort,
        sort_value: fn row -> row.v end,
        cell: fn _ -> nil end,
        csv_value: fn row -> to_string(row.v) end
      }
    end

    test "ascending treats nil as just below 0" do
      rows = [%{v: 3}, %{v: 1}, %{v: nil}, %{v: 2}, %{v: 0}]
      sorted = LiveTable.sort(rows, "v_asc", [num_col()]) |> Enum.map(& &1.v)
      assert sorted == [nil, 0, 1, 2, 3]
    end

    test "descending sinks nil below 0" do
      rows = [%{v: 3}, %{v: 1}, %{v: nil}, %{v: 2}, %{v: 0}]
      sorted = LiveTable.sort(rows, "v_desc", [num_col()]) |> Enum.map(& &1.v)
      assert sorted == [3, 2, 1, 0, nil]
    end

    test "unknown sorter leaves rows untouched" do
      rows = [%{v: 3}, %{v: 1}]
      assert LiveTable.sort(rows, "nope_desc", [num_col()]) == rows
    end
  end

  describe "sort/3 with :nil_at_end" do
    test "nil stays last regardless of direction" do
      cols = [num_col(:nil_at_end)]
      rows = [%{v: 3}, %{v: nil}, %{v: 1}]
      assert LiveTable.sort(rows, "v_asc", cols) |> Enum.map(& &1.v) == [1, 3, nil]
      assert LiveTable.sort(rows, "v_desc", cols) |> Enum.map(& &1.v) == [3, 1, nil]
    end
  end

  describe "filter/3 (CodeWAS columns)" do
    setup do
      %{columns: CodeWASTable.columns()}
    end

    test "code filter is a case-insensitive substring", %{columns: columns} do
      rows = [
        code_row(code: "I10", vocabulary: "ICD10fi", description: "Hypertension"),
        code_row(code: "E11", vocabulary: "ICD10fi", description: "Diabetes")
      ]

      out = LiveTable.filter(rows, %{"code-filter" => "i1"}, columns)
      assert Enum.map(out, & &1.code) == ["I10"]
    end

    test "vocabulary filter matches raw code, short and full naming", %{columns: columns} do
      rows = [
        code_row(code: "I10", vocabulary: "ICD10fi", description: "x"),
        code_row(code: "A01", vocabulary: "ATC", description: "y")
      ]

      # "finland" only appears in ICD10fi's short/full naming, not its raw code.
      assert LiveTable.filter(rows, %{"vocabulary-filter" => "finland"}, columns)
             |> Enum.map(& &1.code) == ["I10"]

      # "therapeutic" only appears in ATC's full naming.
      assert LiveTable.filter(rows, %{"vocabulary-filter" => "therapeutic"}, columns)
             |> Enum.map(& &1.code) == ["A01"]
    end

    test "a nil description is dropped for any query, including empty", %{columns: columns} do
      # Faithful to the pre-refactor per-row guard (`if is_nil(row.description) -> false`):
      # a nil description fails the description filter for every query, even "". Such rows
      # are still visible on initial load because mount sorts without filtering.
      nil_desc = [code_row(code: "I10", vocabulary: "ICD10fi", description: nil)]
      assert LiveTable.filter(nil_desc, %{"description-filter" => "x"}, columns) == []
      assert LiveTable.filter(nil_desc, %{"description-filter" => ""}, columns) == []

      # A present description is kept by an empty query.
      with_desc = [code_row(code: "I10", vocabulary: "ICD10fi", description: "Hyp")]
      assert LiveTable.filter(with_desc, %{"description-filter" => ""}, columns) == with_desc
    end

    test "filters AND together; absent filters match everything", %{columns: columns} do
      rows = [
        code_row(code: "I10", vocabulary: "ICD10fi", description: "Hypertension"),
        code_row(code: "I11", vocabulary: "ICD10fi", description: "Heart")
      ]

      out =
        LiveTable.filter(rows, %{"code-filter" => "i1", "description-filter" => "heart"}, columns)

      assert Enum.map(out, & &1.code) == ["I11"]
      assert LiveTable.filter(rows, %{}, columns) == rows
    end
  end

  describe "filter/3 (LabWAS facets)" do
    test "endpoint facet matches OMOP id or name" do
      columns = LabWASTable.columns(:endpoint)

      rows = [
        labwas_endpoint_row(omop_concept_id: "3004501", omop_concept_name: "Glucose"),
        labwas_endpoint_row(omop_concept_id: "3019550", omop_concept_name: "Sodium")
      ]

      assert LiveTable.filter(rows, %{"facet" => "gluc"}, columns)
             |> Enum.map(& &1.omop_concept_id) == ["3004501"]

      assert LiveTable.filter(rows, %{"facet" => "3019550"}, columns)
             |> Enum.map(& &1.omop_concept_name) == ["Sodium"]
    end

    test "lab_test facet matches endpoint name or longname" do
      columns = LabWASTable.columns(:lab_test)

      rows = [
        %{fg_endpoint_name: "T2D", fg_endpoint_longname: "Type 2 diabetes", mean_value_unit: nil},
        %{
          fg_endpoint_name: "I9_HYPTENS",
          fg_endpoint_longname: "Hypertension",
          mean_value_unit: nil
        }
      ]

      assert LiveTable.filter(rows, %{"facet" => "diabetes"}, columns)
             |> Enum.map(& &1.fg_endpoint_name) == ["T2D"]
    end
  end

  describe "filter_params/1" do
    test "lists the declared filter params in column order" do
      assert LiveTable.filter_params(CodeWASTable.columns()) ==
               ["code-filter", "vocabulary-filter", "description-filter"]

      assert LiveTable.filter_params(LabWASTable.columns(:endpoint)) ==
               ["facet", "mean-value-unit"]
    end
  end

  describe "to_csv/2 (CodeWAS)" do
    test "group-qualified header, masked low N, and +∞ preserved" do
      columns = CodeWASTable.columns()

      rows = [
        code_row(
          code: "I10",
          vocabulary: "ICD10fi",
          description: "Hypertension",
          odds_ratio: 12.34,
          nlog10p: 5.67,
          n_matched_cases: nil,
          n_matched_controls: 10
        ),
        code_row(
          code: "A01",
          vocabulary: "ATC",
          description: "Drug",
          odds_ratio: Float.max_finite(),
          nlog10p: 1.0,
          n_matched_cases: 5,
          n_matched_controls: 6
        )
      ]

      [header, row1, row2] = csv_rows(LiveTable.to_csv(rows, columns))

      assert header == [
               "Code",
               "Vocabulary",
               "Description",
               "Odds Ratio",
               "-log10(p)",
               "N matched cases",
               "N matched controls"
             ]

      # nil count → "*" (privacy mask preserved), vocabulary uses its short naming
      assert row1 == ["I10", "ICD-10 Finland", "Hypertension", "12.3", "5.7", "*", "10"]
      assert row2 == ["A01", "ATC", "Drug", "+∞", "1.0", "5", "6"]
    end
  end

  describe "to_csv/2 (LabWAS endpoint facet)" do
    test "group-qualified headers, 0 / em-dash / +∞ preserved" do
      columns = LabWASTable.columns(:endpoint)

      rows = [
        labwas_endpoint_row(
          omop_concept_id: "3004501",
          omop_concept_name: "Glucose",
          with_measurement_n_cases: 0,
          with_measurement_n_controls: 7,
          with_measurement_odds_ratio: Float.max_finite(),
          with_measurement_mlogp: 2.5,
          mean_n_measurements_cases: 1.2,
          mean_n_measurements_controls: 3.4,
          mean_value_cases: nil,
          mean_value_controls: 5.6,
          mean_value_unit: "mmol/L",
          mean_value_mlogp: nil,
          mean_value_n_cases: 8,
          mean_value_n_controls: 9
        )
      ]

      [header, row1] = csv_rows(LiveTable.to_csv(rows, columns))

      assert header == [
               "OMOP Concept",
               "People with measurements: N Cases",
               "People with measurements: N Controls",
               "People with measurements: OR",
               "People with measurements: -log10(p)",
               "Mean N measurements: cases",
               "Mean N measurements: controls",
               "Mean measured value: cases",
               "Mean measured value: controls",
               "Mean measured value: unit",
               "Mean measured value: -log10(p)",
               "Mean measured value: N cases",
               "Mean measured value: N controls"
             ]

      assert row1 == [
               "(3004501) Glucose",
               "0",
               "7",
               "+∞",
               "2.50",
               "1.2",
               "3.4",
               "—",
               "5.60",
               "mmol/L",
               "—",
               "8",
               "9"
             ]
    end
  end

  describe "table/1 component renders (DB-free)" do
    defp render_table(columns, rows, grid_class) do
      render_component(&LiveTable.table/1,
        id: "t",
        grid_class: grid_class,
        columns: columns,
        rows: rows,
        form: Phoenix.Component.to_form(%{"sorter" => "x"}),
        active_sorter: "nlog10p_desc",
        filters: %{}
      )
    end

    test "CodeWAS table: download button, header, widgets, and a body row" do
      rows = [
        code_row(
          code: "I10",
          vocabulary: "ICD10fi",
          description: "Hypertension",
          odds_ratio: 12.34,
          nlog10p: 5.67,
          n_matched_cases: nil,
          n_matched_controls: 10
        )
      ]

      html =
        render_table(
          CodeWASTable.columns(),
          rows,
          "data-grid-table codewas--data-grid-table codewas--data-grid-table-conf"
        )

      assert html =~ ~s(phx-click="download_csv")
      assert html =~ ~s(role="grid")
      # widget hooks for the hidden form + a sorter button
      assert html =~ ~s(form="form-t")
      assert html =~ ~s(value="nlog10p_desc")
      # body cell renders the vocabulary short naming and the privacy mask
      assert html =~ "ICD-10 Finland"
      assert html =~ ">*<"
      assert html =~ "12.3"
    end

    test "LabWAS endpoint facet: grouped top-header and a verified-route link render" do
      rows = [
        labwas_endpoint_row(
          omop_concept_id: "3004501",
          omop_concept_name: "Glucose",
          with_measurement_n_cases: 5,
          with_measurement_n_controls: 7,
          with_measurement_odds_ratio: 1.5,
          with_measurement_mlogp: 2.5,
          mean_n_measurements_cases: 1.2,
          mean_n_measurements_controls: 3.4,
          mean_value_cases: 4.5,
          mean_value_controls: 5.6,
          mean_value_unit: "mmol/L",
          mean_value_mlogp: 1.1,
          mean_value_n_cases: 8,
          mean_value_n_controls: 9
        )
      ]

      html =
        render_table(
          LabWASTable.columns(:endpoint),
          rows,
          "data-grid-table labwas--data-grid-table labwas--data-grid-table-conf"
        )

      # grouped top-header row is present
      assert html =~ "People with measurements"
      assert html =~ ~s(class="facet top-header")
      # verified-route link built by ~p in the facet cell
      assert html =~ ~s(href="/lab-tests/3004501")
      assert html =~ "Glucose"
    end

    test "LabWAS lab_test facet: endpoint link and Name label render" do
      rows = [
        %{
          fg_endpoint_name: "T2D",
          fg_endpoint_longname: "Type 2 diabetes",
          with_measurement_n_cases: 5,
          with_measurement_n_controls: 7,
          with_measurement_odds_ratio: 1.5,
          with_measurement_mlogp: 2.5,
          mean_n_measurements_cases: 1.2,
          mean_n_measurements_controls: 3.4,
          mean_value_cases: 4.5,
          mean_value_controls: 5.6,
          mean_value_unit: "mmol/L",
          mean_value_mlogp: 1.1,
          mean_value_n_cases: 8,
          mean_value_n_controls: 9
        }
      ]

      html =
        render_table(
          LabWASTable.columns(:lab_test),
          rows,
          "data-grid-table labwas--data-grid-table labwas--data-grid-table-conf"
        )

      # facet group label for this facet
      assert html =~ "Endpoint"
      # verified-route link built by ~p"/endpoints/#{name}" in the facet cell
      assert html =~ ~s(href="/endpoints/T2D")
      assert html =~ "Type 2 diabetes"
    end
  end
end
