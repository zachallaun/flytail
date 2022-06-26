defmodule FlytailWeb.PageController do
  use FlytailWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
