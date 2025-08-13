defmodule RisteysWeb.ErrorHTMLTest do
  use RisteysWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html", %{conn: conn} do
    conn = get(conn, "/missing/page")
    assert html_response(conn, 404) =~ "Page Not Found"
  end

  test "renders 500.html", %{conn: conn} do
    assert render_to_string(RisteysWeb.ErrorHTML, "500", "html", conn: conn) =~
             "Internal Server Error"
  end
end
