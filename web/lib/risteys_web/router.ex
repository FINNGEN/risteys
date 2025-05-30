defmodule RisteysWeb.Router do
  use RisteysWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RisteysWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RisteysWeb do
    pipe_through :browser

    get "/", HomeController, :index

    get "/changelog", ChangelogController, :index

    get "/documentation", DocumentationController, :index

    get "/endpoints/:name", FGEndpointController, :show

    get "/lab-tests/", LabTestController, :index
    get "/lab-tests/:omop_id", LabTestController, :show

    get "/random/endpoint", FGEndpointController, :redir_random
    get "/random/lab-test", LabTestController, :redir_random

    # Redirect legacy URLs to keep shared and published links working
    get "/phenocode/:name", FGEndpointController, :redirect_legacy_url
    get "/endpoint/:name", FGEndpointController, :redirect_legacy_url
  end

  scope "/api", RisteysWeb do
    pipe_through :api

    get "/endpoints/", FGEndpointController, :index_json
  end

  scope "/auth", RisteysWeb do
    pipe_through :browser

    get "/:provider/set_redir/:fg_endpoint", AuthController, :set_redir

    # This will be auto-magically called by Ueberauth, we don't need to implement it.
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:risteys, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RisteysWeb.Telemetry
    end
  end
end
