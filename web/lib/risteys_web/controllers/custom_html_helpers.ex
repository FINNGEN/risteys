defmodule RisteysWeb.CustomHTMLHelpers do
  def ahref_extern(href, content) do
    Phoenix.HTML.Link.link(content,
      to: href,
      target: "_blank",
      rel: "noopener noreferrer external"
    )
  end

  def ahref_feedback(conn, content) do
    where_from = Phoenix.Controller.current_path(conn)
    href = "https://airtable.com/shrTzTwby7JhFEqi6?prefill_Page=" <> where_from
    ahref_extern(href, content)
  end

  def change_release_url(conn, dataset, version_number) do
    path = conn.request_path

    cond do
      version_number <= 6 ->
        path = String.replace_leading(path, "/documentation", "/methods")
        path = String.replace_leading(path, "/endpoints", "/phenocode")
        "https://r#{version_number}.risteys.finngen.fi" <> path

      version_number <= 8 ->
        path = String.replace_leading(path, "/endpoints", "/phenocode")
        "https://r#{version_number}.risteys.finngen.fi" <> path

      version_number == 9 ->
        "https://r9.risteys.finngen.fi" <> path

      dataset == :fg and version_number == 10 ->
        "https://r10.risteys.finngen.fi" <> path

      dataset == :fg_fr ->
        "https://r#{version_number}.risteys.finngen.fi" <> path
    end
  end
end
