defmodule WigleExplorer.Wigle.ClientTest do
  use ExUnit.Case, async: false
  alias WigleExplorer.Wigle.{Client, Network, Search, SearchResult}
  import WigleExplorer.WigleFixtures

  setup :verify_on_exit

  test "all network types send bounds and server auth and preserve normalized and raw data" do
    for {kind, path, fixture} <- families() do
      raw = fixture.("AA:BB:CC:DD:EE:01")

      Req.Test.expect(Client, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.request_path == path

        assert conn.query_params == %{
                 "latrange1" => "41.87",
                 "latrange2" => "41.89",
                 "longrange1" => "-87.65",
                 "longrange2" => "-87.61",
                 "resultsPerPage" => "100"
               }

        assert Plug.Conn.get_req_header(conn, "authorization") == [
                 "Basic " <> Base.encode64("test-name:test-token")
               ]

        Req.Test.json(conn, response([raw], 684, "opaque-cursor"))
      end)

      assert {:ok, result} = Client.search_networks(bounds(), network_type: kind)
      assert result.network_type == kind
      assert result.total_results == 684
      assert result.result_count == 1
      assert result.search_after == "opaque-cursor"
      refute result.complete?
      record = hd(result.networks)
      assert record.kind == kind
      assert record.identifier == (raw["netid"] || raw["id"])
      assert record.name == (raw["name"] || raw["ssid"])
      assert record.last_seen == raw["lasttime"]
      assert record.raw == raw

      case kind do
        "wifi" ->
          assert record.encryption == "WPA2"

        "bluetooth" ->
          assert record.capabilities == ["LE", "Beacon"]
          assert record.device_class == 1024
          assert record.manufacturer_id == 76

        "cellular" ->
          assert record.type == "LTE"
          assert record.attributes == "Example cellular attributes"
      end

      assert %{features: [%{geometry: %{coordinates: [-87.6298, 41.8781]}}]} =
               Network.feature_collection(result.networks)
    end

    for {kind, key, fixture} <- [
          {"wifi", "ssidlike", &network/1},
          {"bluetooth", "namelike", &bluetooth/1}
        ] do
      Req.Test.expect(Client, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params[key] == "%Cafe%"
        assert conn.query_params["lasttime"] == "20241011000000"
        refute Map.has_key?(conn.query_params, "latrange1")

        if kind == "wifi",
          do: assert(conn.query_params["encryption"] == "None"),
          else: refute(Map.has_key?(conn.query_params, "encryption"))

        Req.Test.json(conn, response([fixture.("03")], 2, "advanced-next"))
      end)

      assert {:ok, result} =
               Client.advanced_search(
                 %{
                   "type" => kind,
                   "value" => "Cafe",
                   "encryption" => if(kind == "wifi", do: "None", else: "any"),
                   "seen_within" => "custom",
                   "custom_date" => "2024-10-11"
                 },
                 bounds()
               )

      assert result.bounds == nil
      assert result.description =~ "contains “Cafe”"
      assert result.description =~ "Anywhere"
    end
  end

  test "every next page reuses its network type, opaque cursor and bounds and appends unique records" do
    for {kind, path, fixture} <- families() do
      first =
        SearchResult.from_response(response([fixture.("01")], 4, "next:123"), bounds(), kind)

      Req.Test.expect(Client, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.request_path == path
        assert conn.query_params["searchAfter"] == "next:123"
        assert conn.query_params["longrange1"] == "-87.65"
        refute Map.has_key?(conn.query_params, "first")
        Req.Test.json(conn, response([fixture.("01"), fixture.("02")], 4, "next:456"))
      end)

      assert {:ok, next} = Client.next_page(first)
      assert Enum.map(next.networks, & &1.id) == ["01", "02"]
      assert next.network_type == kind
      assert next.search_after == "next:456"
      assert next.result_count == 2
      assert next.page_size == 2
      refute next.complete?
    end

    for kind <- ["wifi", "bluetooth"] do
      filters = %{netid: "AA:BB:CC", lasttime: "20261010010203"}

      first = %{
        SearchResult.from_response(response([network("01")], 3, "advanced-cursor"), nil, kind)
        | filters: filters,
          description: "Original advanced search"
      }

      Req.Test.expect(Client, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        assert conn.query_params == %{
                 "netid" => "AA:BB:CC",
                 "lasttime" => "20261010010203",
                 "resultsPerPage" => "100",
                 "searchAfter" => "advanced-cursor"
               }

        Req.Test.json(conn, response([network("02")], 3, "next"))
      end)

      assert {:ok, next} = Client.next_page(first)
      assert next.filters == filters
      assert next.description == first.description
      assert next.bounds == nil
    end
  end

  test "a 429 is returned without any automatic retry" do
    Req.Test.expect(Client, &Plug.Conn.send_resp(&1, 429, "limit"))
    assert {:error, :rate_limited} = Client.search_networks(bounds())
  end

  test "missing credentials never send a request and authentication failures are clear" do
    original = Application.fetch_env!(:wigle_explorer, :wigle_credentials)
    on_exit(fn -> Application.put_env(:wigle_explorer, :wigle_credentials, original) end)
    Application.put_env(:wigle_explorer, :wigle_credentials, {"", ""})
    assert {:error, :missing_credentials} = Client.search_networks(bounds())
    Application.put_env(:wigle_explorer, :wigle_credentials, original)
    Req.Test.expect(Client, &Plug.Conn.send_resp(&1, 401, "unauthorized"))
    assert {:error, :authentication} = Client.search_networks(bounds())
  end

  test "small pages stay incomplete, exhaustion stops requests, and stalled cursors are rejected" do
    partial = SearchResult.from_response(response([network("01")], 3, "cursor"), bounds())
    refute partial.complete?
    assert SearchResult.estimated_requests(partial) == 2
    Req.Test.expect(Client, &Req.Test.json(&1, response([network("02")], 3, "cursor")))
    assert {:error, :pagination_stalled} = Client.next_page(partial)
    exhausted = SearchResult.from_response(response([], 0), bounds())
    assert exhausted.complete?
    assert {:ok, ^exhausted} = Client.next_page(exhausted)
    assert {:error, :invalid_bounds} = Client.search_networks(%{"south" => 0})

    assert {:error, :invalid_network_type} =
             Client.search_networks(bounds(), network_type: "unknown")

    assert {:error, :invalid_bounds} = Client.search_networks(nil)

    assert {:error, :invalid_bounds} =
             Client.advanced_search(%{"value" => "Cafe", "location" => "map"}, nil)

    for criteria <- [
          %{"value" => "   "},
          %{"value" => "Cafe", "type" => "cellular"},
          %{"value" => "Cafe", "encryption" => "injected"},
          %{"value" => "Cafe", "type" => "bluetooth", "encryption" => "WPA2"},
          %{"search_by" => "mac", "match" => "contains", "value" => "AA:BB:CC"},
          %{"search_by" => "mac", "match" => "exact", "value" => "AA:BB:CC"},
          %{"search_by" => "mac", "match" => "starts_with", "value" => "AA:BB"},
          %{"value" => "Cafe", "seen_within" => "custom", "custom_date" => "invalid"},
          %{"value" => "Cafe", "seen_within" => "custom", "custom_date" => "9999-12-31"}
        ] do
      assert {:error, {:invalid_search, _}} = Client.advanced_search(criteria, bounds())
    end

    for {kind, match, key, value} <- [
          {"wifi", "exact", :ssid, "Cafe_100%"},
          {"wifi", "starts_with", :ssidlike, "Cafe%"},
          {"bluetooth", "exact", :name, "Cafe_100%"},
          {"bluetooth", "starts_with", :namelike, "Cafe%"}
        ] do
      input = if match == "exact", do: "Cafe_100%", else: "Cafe"

      assert {:ok, search} =
               Search.prepare(
                 %{"type" => kind, "match" => match, "value" => input, "location" => "map"},
                 bounds()
               )

      assert search.filters == %{key => value}
      assert search.bounds == bounds()
    end

    for {match, value} <- [{"exact", "aa-bb-cc-dd-ee-ff"}, {"starts_with", "aa:bb:cc"}] do
      assert {:ok, search} =
               Search.prepare(%{"search_by" => "mac", "match" => match, "value" => value}, nil)

      assert search.filters.netid == value |> String.replace("-", ":") |> String.upcase()
    end

    now = ~U[2024-02-29 12:34:56Z]

    for {period, expected} <- [
          {"24h", "20240228123456"},
          {"7d", "20240222123456"},
          {"30d", "20240130123456"},
          {"90d", "20231201123456"},
          {"1y", "20230228123456"},
          {"5y", "20190228123456"}
        ] do
      assert {:ok, search} =
               Search.prepare(%{"value" => "Cafe", "seen_within" => period}, nil, now)

      assert search.filters.lasttime == expected
    end
  end

  defp families do
    [
      {"wifi", "/api/v2/network/search", &network/1},
      {"bluetooth", "/api/v2/bluetooth/search", &bluetooth/1},
      {"cellular", "/api/v2/cell/search", &cellular/1}
    ]
  end

  defp verify_on_exit(_context) do
    Req.Test.verify_on_exit!()
    :ok
  end
end
