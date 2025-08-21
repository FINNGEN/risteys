# upset plots: upset_plots/interactive_plots/interactive_<ENDPOINT>.html
# info for detail tables: upset_plots/name_tables_json/name_table_<ENDPOINT>.html

# - we have list of endpoints with NO upset plots and name_table, get their reason, add info to DB
# - we have list of endpoints with upset plots and name_table, set info to DB, move upset plot, gen table
import Ecto.Query
require Logger
alias Risteys.FGEndpoint
alias Risteys.Repo
alias Risteys.KeyFigures

# --- CLI argument parser
[in_dir, dataset | _] = System.argv()

# Dataset "FG" or "FR" tells from which project the data comes and is used to
# save the plot and table files and status information accordingly to their own locations.
# Raise an error if correct dataset info is not provided
if dataset != "FG" and dataset != "FR" do
  raise ArgumentError, message: "Dataset 'FG' or 'FR' need to be given as a second argument"
end

# --- Configuration
runlog_file = "error_log.csv"
upset_plots_dir = "interactive_plots"
upset_plots_prefix = "interactive_"
upset_plots_suffix = ".html"
tables_dir = "name_tables_json"
tables_prefix = "name_table_"
tables_suffix = ".json"

upset_plots_output = "priv/static/upset_plot/" <> dataset <> "/"
table_template = "template_upset_table.html.heex"
tables_output = "priv/static/table_case_counts/" <> dataset <> "/"

# dataset specific keys for FGEndpoint.set_status function that sets status in the DB
dataset_atom = String.downcase(dataset)
key_upset_plot = String.to_atom("upset_plot_" <> dataset_atom)
key_upset_table = String.to_atom("upset_table_" <> dataset_atom)

Logger.configure(level: :info)

# --- Checking DB for existing endpoints
existing_endpoints_db =
  FGEndpoint.list_endpoint_names()
  |> MapSet.new()

# --- Gather input data
Logger.info("Gathering input data")

runlog_path =
  in_dir
  |> Path.expand()
  |> Path.join(runlog_file)

runlogs =
  if File.exists?(runlog_path) do
    runlog_path
    |> File.stream!()
    |> CSV.decode!(headers: true)
    |> Enum.reduce(%{}, fn row, acc ->
      %{
        "Endpoint" => endpoint,
        "Result" => result
      } = row

      Map.put_new(acc, endpoint, result)
    end)
  else
    Logger.warning(
      "The runlog file `#{runlog_file}` is missing. No failure reasons will be shown to the users."
    )

    :missing_file
  end

upset_plots_path =
  in_dir
  |> Path.expand()
  |> Path.join(upset_plots_dir)

upset_plots =
  upset_plots_path
  |> File.ls!()
  |> Enum.filter(fn file ->
    String.starts_with?(file, upset_plots_prefix) and String.ends_with?(file, upset_plots_suffix)
  end)
  |> Enum.map(fn file ->
    endpoint =
      file
      |> String.replace_prefix(upset_plots_prefix, "")
      |> String.replace_suffix(upset_plots_suffix, "")

    path = Path.join(upset_plots_path, file)
    {endpoint, path}
  end)
  |> Enum.filter(fn {endpoint, _path} -> endpoint in existing_endpoints_db end)
  |> Enum.into(%{})

tables_path =
  in_dir
  |> Path.expand()
  |> Path.join(tables_dir)

tables =
  tables_path
  |> File.ls!()
  |> Enum.filter(fn file ->
    String.starts_with?(file, tables_prefix) and String.ends_with?(file, tables_suffix)
  end)
  |> Enum.map(fn file ->
    endpoint =
      file
      |> String.replace_prefix(tables_prefix, "")
      |> String.replace_suffix(tables_suffix, "")

    path = Path.join(tables_path, file)

    {endpoint, path}
  end)
  |> Enum.filter(fn {endpoint, _path} -> endpoint in existing_endpoints_db end)
  |> Enum.into(%{})

# --- Import upset plots
Logger.info("Adding upset plots as static files and setting status in DB")

Enum.each(upset_plots, fn {endpoint, upset_path} ->
  Logger.debug("Importing upset plot for #{endpoint}")
  # Copy upset plot file to Risteys
  out = Path.join(upset_plots_output, Path.basename(upset_path))
  File.cp!(upset_path, out)

  # Set default mode to also be writable by user, otherwise phx.digest
  # will throw an error when called.
  read_write = 0o644
  File.chmod!(out, read_write)

  # Set upset plot status
  FGEndpoint.set_status!(endpoint, key_upset_plot, "ok")
end)

# --- Generate and import tables
Logger.info("Generating upset tables, adding as static files and setting status in DB")

registries = %{
  "PRIM_OUT" => "Avohilmo: Primary healthcare outpatient",
  "INPAT" => "Inpatient Hilmo",
  "OUTPAT" => "Outpatient Hilmo",
  "DEATH" => "Cause of death",
  "OPER_IN" => "Operations in inpatient Hilmo",
  "OPER_OUT" => "Operations in outpatient Hilmo",
  "PURCH" => "KELA drug purchase",
  "REIMB" => "KELA drug reimbursment",
  "CANC" => "Cancer"
}

db_endpoints_stats =
  Repo.all(
    from endp in FGEndpoint.Definition,
      join: key_fig in KeyFigures,
      on: endp.id == key_fig.fg_endpoint_id,
      where: endp.name in ^Map.keys(tables) and key_fig.dataset == ^dataset,
      select: {endp.name, key_fig.nindivs_all}
  )
  |> Enum.into(%{})

Enum.each(tables, fn {endpoint, table_path} ->
  Logger.debug("Generating and importing upset table for #{endpoint}")
  # Generate HTML file from JSON table
  rows =
    table_path
    |> File.read!()
    |> Jason.decode!()
    # Discard rows with N<5
    |> Enum.reject(fn %{"Frequency_people" => freq} -> freq == "<5" end)
    |> Enum.map(fn row ->
      %{
        "Source" => source,
        "Tag" => tag,
        "Frequency_people" => case_count
      } = row

      # Handle missing data
      name = Map.get(row, "Name", "unknown")

      case_count = String.to_integer(case_count)

      case_percentage =
        case Map.fetch(db_endpoints_stats, endpoint) do
          :error -> nil
          {:ok, nil} -> nil
          {:ok, total_cases} -> case_count / total_cases * 100
        end

      source_long = Map.fetch!(registries, source)

      %{
        source_long: source_long,
        source_code: source,
        tag: tag,
        name: name,
        case_count: case_count,
        case_percentage: case_percentage
      }
    end)

  if not Enum.empty?(rows) do
    # Put HTML file into Risteys
    html = EEx.eval_file(table_template, endpoint_name: endpoint, table: rows)
    out = Path.join(tables_output, endpoint <> ".html")
    File.write!(out, html)

    # Set table status
    FGEndpoint.set_status!(endpoint, key_upset_table, "ok")
  else
    Logger.warning("Discarding upset table for #{endpoint}: no rows left after filtering.")
  end
end)

# --- Handle endpoints without upset data
Logger.info("Setting status for endpoints in DB without upset plot or table")
all_db_endpoints = Repo.all(FGEndpoint.Definition)

# Create dataset specific keys for getting the status information from the DB
key_status_upset_plot = String.to_atom("status_upset_plot_" <> dataset_atom)
key_status_upset_table = String.to_atom("status_upset_table_" <> dataset_atom)

# Go through every endpoint and filter by plot or table status not to be "ok" to set correct status for those cases
for endpoint <- all_db_endpoints,
    Map.get(endpoint, key_status_upset_plot) != "ok" or
      Map.get(endpoint, key_status_upset_table) != "ok" do
  failure =
    if runlogs == :missing_file do
      "unknown reason"
    else
      case Map.fetch(runlogs, endpoint.name) do
        {:error, _} ->
          Logger.warning("#{endpoint.name} not found in run log file")
          "not run"

        {:ok, status} ->
          cond do
            status == "Endpoint set to omit" -> "omit"
            status =~ "Not enough data" or status =~ "sizes too small" -> "not enough data"
            status =~ "No data found" -> "no data"
            status =~ "pending unroll" -> "pending unroll"
            true -> "unknown reason"
          end
      end
    end

  if Map.get(endpoint, key_status_upset_plot) != "ok" do
    FGEndpoint.set_status!(endpoint, key_upset_plot, failure)
  end

  if Map.get(endpoint, key_status_upset_table) != "ok" do
    FGEndpoint.set_status!(endpoint, key_upset_table, failure)
  end
end
