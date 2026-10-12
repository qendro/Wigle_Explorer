defmodule WigleExplorerWeb.ExplorerLiveTest do
  use WigleExplorerWeb.ConnCase, async: false
  import Phoenix.ConnTest, except: [response: 2]
  import Phoenix.LiveViewTest
  import WigleExplorer.WigleFixtures
  alias WigleExplorer.Wigle.Client

  setup do
    Req.Test.set_req_test_to_shared()
    Req.Test.verify_on_exit!()
    :ok
  end

  test "initial page renders without querying WiGLE", %{conn: conn} do
    original = Application.fetch_env!(:wigle_explorer, :wigle_credentials)
    on_exit(fn -> Application.put_env(:wigle_explorer, :wigle_credentials, original) end)
    Application.put_env(:wigle_explorer, :wigle_credentials, {"", ""})
    {:ok, view, html} = live(conn, "/")
    assert html =~ "Networks, mapped."
    assert has_element?(view, "#search-area")
    assert has_element?(view, "#search-area[disabled]")
    assert has_element?(view, "#draw-area", "Draw area")
    assert has_element?(view, "#network-type option[value=bluetooth]", "Bluetooth")
    assert has_element?(view, "#network-type option[value=cellular]", "Cellular")
    refute has_element?(view, "#clear-area")
    assert html =~ "Connect WiGLE to start exploring"
    assert has_element?(view, "#empty-state", "Your next discovery starts here")
    assert has_element?(view, "#loaded-count", "0")
    assert has_element?(view, "#advanced-search-content[hidden]")
    view |> element("#toggle-advanced") |> render_click()
    refute has_element?(view, "#advanced-search-content[hidden]")
    assert has_element?(view, "#advanced-match option[value=contains][selected]")
    assert has_element?(view, "#advanced-location option[value=anywhere][selected]")
    assert has_element?(view, "#advanced-submit[disabled]")

    view
    |> form("#advanced-search-form", %{
      search: %{type: "bluetooth", encryption: "WPA2", search_by: "mac"}
    })
    |> render_change()

    assert has_element?(view, "#advanced-encryption[disabled] option[value=any][selected]")
    assert has_element?(view, "#advanced-match option[value=contains][disabled]")
    assert has_element?(view, "#advanced-match option[value=exact][selected]")
    view |> form("#advanced-search-form", %{search: %{seen_within: "custom"}}) |> render_change()
    assert has_element?(view, "#advanced-date[required]")
  end

  test "search renders summary, filters and sorts loaded rows, and selects details without extra calls",
       %{conn: conn} do
    Req.Test.expect(
      Client,
      &Req.Test.json(
        &1,
        response(
          [
            network("01", "Alpha", "2026-10-01T00:00:00.000Z"),
            network("02", "Zulu")
          ],
          684,
          "next"
        )
      )
    )

    {:ok, view, _} = live(conn, "/")
    render_hook(view, "area_selection", %{selected: false, drawing: true})
    assert has_element?(view, "#search-area[disabled]")
    assert has_element?(view, "#draw-area", "Cancel drawing")
    render_hook(view, "search_area", %{bounds: bounds()})
    render_async(view)
    assert row_ids(view) == []
    render_hook(view, "area_selection", %{selected: true, drawing: false})
    assert has_element?(view, "#search-area", "Search selected area")
    assert has_element?(view, "#clear-area", "Clear area")
    render_hook(view, "search_area", %{bounds: bounds()})
    render_async(view)
    assert has_element?(view, "#total-count", "684")
    assert has_element?(view, "#loaded-count", "2")
    search_bounds = bounds()

    assert_push_event(view, "networks_updated", %{
      bounds: ^search_bounds,
      geojson: %{features: [_, _]}
    })

    assert ["02", "01"] == row_ids(view)
    view |> form("#table-controls", %{filter: "", sort: "name"}) |> render_change()
    assert ["01", "02"] == row_ids(view)
    view |> form("#table-controls", %{filter: "aLpHa", sort: "name"}) |> render_change()
    assert ["01"] == row_ids(view)
    view |> element("#network-01") |> render_click()
    assert has_element?(view, "#network-details", "Alpha")
    assert has_element?(view, ".raw-data", "Preserve me")
    assert has_element?(view, "#network-01.selected-row")
    assert_push_event(view, "network_selected", %{id: "01", coordinates: [-87.6298, 41.8781]})
    render_hook(view, "select_network", %{id: "02"})
    assert has_element?(view, "#detail-title", "Zulu")
    assert has_element?(view, "#network-02.selected-row")
    render_hook(view, "area_selection", %{selected: false, drawing: false})
    assert has_element?(view, "#search-area", "Search this area")
    refute has_element?(view, "#clear-area")
    assert Enum.sort(row_ids(view)) == ["01", "02"]
  end

  test "type changes keep existing results and pagination until a new search succeeds", %{
    conn: conn
  } do
    Req.Test.expect(Client, fn conn ->
      assert conn.request_path == "/api/v2/network/search"
      Req.Test.json(conn, response([network("01", "First")], 2, "wifi-next"))
    end)

    Req.Test.expect(Client, fn conn ->
      conn = fetch_query_params(conn)
      assert conn.request_path == "/api/v2/network/search"
      assert conn.query_params["searchAfter"] == "wifi-next"
      Req.Test.json(conn, response([network("02", "Second")], 2))
    end)

    Req.Test.expect(Client, fn conn ->
      assert conn.request_path == "/api/v2/bluetooth/search"
      Req.Test.json(conn, response([bluetooth("03", "Beacon")], 2, "bt-next"))
    end)

    Req.Test.expect(Client, fn conn ->
      conn = fetch_query_params(conn)
      assert conn.request_path == "/api/v2/bluetooth/search"
      assert conn.query_params["searchAfter"] == "bt-next"
      Req.Test.json(conn, response([bluetooth("04", "Speaker")], 2))
    end)

    Req.Test.expect(Client, fn conn ->
      assert conn.request_path == "/api/v2/cell/search"
      Req.Test.json(conn, response([cellular("05", "LTE observation")], 2, "cell-next"))
    end)

    Req.Test.expect(Client, fn conn ->
      conn = fetch_query_params(conn)
      assert conn.request_path == "/api/v2/cell/search"
      assert conn.query_params["searchAfter"] == "cell-next"
      Req.Test.json(conn, response([cellular("06")], 2))
    end)

    {:ok, view, _} = live(conn, "/")
    render_hook(view, "search_area", %{bounds: bounds()})
    render_async(view)
    view |> form("#network-type-form", %{network_type: "bluetooth"}) |> render_change()
    assert has_element?(view, "#network-type-notice", "Loaded results are Wi-Fi")
    assert has_element?(view, "#results-title", "Wi-Fi networks")
    view |> element("#load-more") |> render_click()
    render_async(view)
    assert Enum.sort(row_ids(view)) == ["01", "02"]
    refute has_element?(view, "#load-more")
    view |> element("#network-01") |> render_click()
    render_hook(view, "search_area", %{bounds: bounds()})
    render_async(view)
    assert row_ids(view) == ["03"]
    refute has_element?(view, "#network-details")
    refute has_element?(view, "#network-type-notice")
    assert has_element?(view, "#results-title", "Bluetooth devices")
    assert has_element?(view, "th", "Device address")
    assert has_element?(view, "th", "Capabilities")
    refute has_element?(view, "th", "Encryption")
    view |> element("#network-03") |> render_click()
    assert has_element?(view, "#network-details", "Device class")
    assert has_element?(view, "#network-details", "Manufacturer ID")
    render_hook(view, "close_details", %{})
    view |> form("#network-type-form", %{network_type: "cellular"}) |> render_change()
    assert has_element?(view, "#network-type-notice", "Loaded results are Bluetooth")
    view |> element("#load-more") |> render_click()
    render_async(view)
    assert Enum.sort(row_ids(view)) == ["03", "04"]
    render_hook(view, "search_area", %{bounds: bounds()})
    render_async(view)
    assert row_ids(view) == ["05"]
    assert has_element?(view, "#results-title", "Cellular networks")
    assert has_element?(view, "th", "Network ID")
    assert has_element?(view, "th", "Radio type")
    view |> element("#load-more") |> render_click()
    render_async(view)
    assert Enum.sort(row_ids(view)) == ["05", "06"]
    view |> element("#network-05") |> render_click()
    assert has_element?(view, "#network-details", "LTE")
    assert has_element?(view, "#network-details", "Example cellular attributes")
  end

  test "failed replacement and rate limited pagination preserve loaded results", %{conn: conn} do
    Req.Test.expect(Client, &Req.Test.json(&1, response([network("01")], 10, "next")))
    Req.Test.expect(Client, &Plug.Conn.send_resp(&1, 401, "bad auth"))
    Req.Test.expect(Client, &Plug.Conn.send_resp(&1, 429, "limit"))
    {:ok, view, _} = live(conn, "/")
    render_hook(view, "search_area", %{bounds: bounds()})
    render_async(view)
    render_hook(view, "advanced_search", %{criteria: %{"value" => ""}, bounds: nil})
    render_async(view)
    assert has_element?(view, "#api-error", "Enter an SSID")
    assert row_ids(view) == ["01"]
    render_hook(view, "advanced_search", %{criteria: %{"value" => "Replacement"}, bounds: nil})
    render_async(view)
    assert has_element?(view, "#api-error", "WiGLE authentication failed")
    assert row_ids(view) == ["01"]
    view |> element("#load-more") |> render_click()
    render_async(view)
    assert has_element?(view, "#api-error", "WiGLE API limit reached")
    assert row_ids(view) == ["01"]
  end

  test "load all warns for large searches and explicitly completes small searches", %{conn: conn} do
    Req.Test.expect(Client, &Req.Test.json(&1, response([network("01")], 100, "large")))
    parent = self()

    Req.Test.expect(Client, fn conn ->
      conn = fetch_query_params(conn)
      assert conn.query_params["ssidlike"] == "Cafe%"
      assert conn.query_params["encryption"] == "WPA2"
      assert conn.query_params["longrange1"] == "-87.65"
      send(parent, {:initial_filters, conn.query_params})
      Req.Test.json(conn, response([network("01")], 3, "small"))
    end)

    Req.Test.expect(Client, fn conn ->
      conn = fetch_query_params(conn)
      send(parent, {:page_filters, Map.delete(conn.query_params, "searchAfter")})
      assert conn.query_params["searchAfter"] == "small"
      Req.Test.json(conn, response([network("02")], 3, "final"))
    end)

    Req.Test.expect(Client, fn conn ->
      conn = fetch_query_params(conn)
      send(parent, {:page_filters, Map.delete(conn.query_params, "searchAfter")})
      assert conn.query_params["searchAfter"] == "final"
      Req.Test.json(conn, response([network("03")], 3))
    end)

    {:ok, view, _} = live(conn, "/")
    render_hook(view, "search_area", %{bounds: bounds()})
    render_async(view)
    view |> element("#load-all") |> render_click()
    assert has_element?(view, "#load-all-warning", "10 additional requests")
    assert row_ids(view) == ["01"]
    view |> element("#toggle-advanced") |> render_click()

    criteria = %{
      "value" => "Cafe",
      "match" => "starts_with",
      "encryption" => "WPA2",
      "location" => "map",
      "seen_within" => "7d"
    }

    view |> form("#advanced-search-form", %{search: criteria}) |> render_change()
    assert row_ids(view) == ["01"]
    render_hook(view, "advanced_search", %{criteria: criteria, bounds: bounds()})
    render_async(view)
    assert has_element?(view, "#search-description", "SSID starts with “Cafe”")
    assert has_element?(view, "#search-description", "WPA2 · Current Map Area · Last 7 Days")
    assert_receive {:initial_filters, filters}
    assert filters["lasttime"] =~ ~r/^\d{14}$/

    view
    |> form("#advanced-search-form", %{
      search: %{value: "Changed", type: "bluetooth", seen_within: "any", location: "anywhere"}
    })
    |> render_change()

    view |> element("#load-all") |> render_click()
    render_async(view)
    render_async(view)
    assert Enum.sort(row_ids(view)) == ["01", "02", "03"]
    assert_receive {:page_filters, ^filters}
    assert_receive {:page_filters, ^filters}
    assert has_element?(view, "#search-description", "SSID starts with “Cafe”")
    refute has_element?(view, "#load-more")
  end

  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(".network-row")
    |> LazyHTML.attribute("id")
    |> Enum.map(&String.replace_prefix(&1, "network-", ""))
  end
end
