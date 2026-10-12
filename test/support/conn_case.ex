defmodule WigleExplorerWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint WigleExplorerWeb.Endpoint
      use WigleExplorerWeb, :verified_routes
      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
