# Import ontology data into the database
#
# Usage:
#     mix run import_ontology.exs <json-file-ontology> <csv-file-corrected-descriptions>
#
# where <json-file-ontology> is a JSON file containing ontology data
# with the following structure:
# {
#   "<endpoint-name>": {
#     {
#       "description": "some text description.",
#       "<ontology-name>": [val1, val2, ...],
#       ...
#     }
#   },
#   ...
# }
#
# The map data for each endpoint will be imported "as is" in a row
# cell in the database.
#
# and where <csv-file-corrected-descriptions> is a CSV file with the following columns:
# - Endpoint
# - Corrected description

alias Risteys.{FGEndpoint, Repo}
import Ecto.Query
require Logger

Logger.configure(level: :info)
[ontology_filepath, corrections_filepath | _] = System.argv()


Logger.info("Parsing corrected descriptions")
corrections =
  corrections_filepath
  |> File.stream!()
  |> CSV.decode!(headers: true)
  |> Stream.filter(fn %{"Approved for release?" => checked?} -> checked? == "checked" end)
  |> Enum.into(%{}, fn %{"Endpoint" => endpoint, "Corrected description" => description} ->
    {endpoint, description}
  end)


ontology_filepath
|> File.read!()
|> Jason.decode!()
|> Enum.each(fn {name, data} ->
  {description, ontology} = Map.pop(data, "description")

  description =
    case Map.fetch(corrections, name) do
      {:ok, corrected_description} ->
	Logger.info("applying corrected description for endpoint #{name}")
	corrected_description

      :error ->
	description
    end

  Logger.info("Importing #{name}…")

  # Update the endpoint with the ontology and description
  case Repo.get_by(FGEndpoint.Definition, name: name) do
    nil ->
      Logger.debug(
        "Endpoint #{name} not in DB, may be not imported due to restrictions on OMIT or LEVEL."
      )

    endpoint ->
      changeset = FGEndpoint.Definition.changeset(endpoint, %{ontology: ontology, description: description})
      Repo.try_update(%FGEndpoint.Definition{}, changeset)
  end
end)

# Display some stats
ontologies = Repo.all(from endpoint in FGEndpoint.Definition, select: endpoint.ontology)

with_data =
  Enum.filter(ontologies, fn m ->
    if is_nil(m) do
      false
    else
      m |> Map.keys() |> length() > 0
    end
  end)
  |> length()

total = length(ontologies)
Logger.info("There are #{with_data} / #{total} endpoints with ontology data.")
