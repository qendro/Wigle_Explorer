defmodule WigleExplorerWeb.ExplorerLive do
  use WigleExplorerWeb, :live_view

  alias WigleExplorer.Wigle.{Client, Network, Search, SearchResult}
  import WigleExplorerWeb.ExplorerComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "WiGLE Explorer",
       configured?: Client.configured?(),
       map_style: Application.fetch_env!(:wigle_explorer, :map_style_url),
       result: nil,
       network_type: "wifi",
       display_type: "wifi",
       advanced_open?: false,
       advanced_values: Search.defaults(),
       selected: nil,
       visible_networks: [],
       filter: "",
       sort: "last_seen",
       loading: nil,
       area_selected?: false,
       drawing_area?: false,
       error: nil,
       load_all?: false,
       requests_left: 0,
       load_warning?: false,
       newest: nil,
       oldest: nil
     )}
  end

  @impl true
  def handle_event("toggle_advanced", _, socket) do
    {:noreply, assign(socket, advanced_open?: not socket.assigns.advanced_open?)}
  end

  def handle_event("advanced_change", %{"search" => params}, socket) do
    {:noreply, assign(socket, advanced_values: Search.form_values(params))}
  end

  def handle_event("advanced_search", %{"criteria" => criteria, "bounds" => bounds}, socket)
      when is_map(criteria) do
    if socket.assigns.loading != nil or socket.assigns.drawing_area? do
      {:noreply, socket}
    else
      socket = assign(socket, advanced_values: Search.form_values(criteria))

      socket =
        if criteria["type"] in ["wifi", "bluetooth"],
          do: assign(socket, network_type: criteria["type"]),
          else: socket

      {:noreply,
       socket
       |> assign(loading: :search, error: nil, load_warning?: false)
       |> start_async(:search, fn -> Client.advanced_search(criteria, bounds) end)}
    end
  end

  def handle_event("search_area", %{"bounds" => bounds}, socket) do
    if socket.assigns.loading != nil or socket.assigns.drawing_area? do
      {:noreply, socket}
    else
      network_type = socket.assigns.network_type

      {:noreply,
       socket
       |> assign(loading: :search, error: nil, load_warning?: false)
       |> start_async(:search, fn ->
         Client.search_networks(bounds, network_type: network_type)
       end)}
    end
  end

  def handle_event("network_type", %{"network_type" => network_type}, socket) do
    if network_type in ["wifi", "bluetooth", "cellular"] and is_nil(socket.assigns.loading) do
      {:noreply, socket |> assign(network_type: network_type) |> update_rows()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("area_selection", %{"selected" => selected, "drawing" => drawing}, socket)
      when is_boolean(selected) and is_boolean(drawing) do
    {:noreply, assign(socket, area_selected?: selected, drawing_area?: drawing)}
  end

  def handle_event("load_more", _, socket), do: {:noreply, load_page(socket, false, 1)}

  def handle_event("load_all", _, socket) do
    result = socket.assigns.result

    cond do
      is_nil(result) or socket.assigns.loading ->
        {:noreply, socket}

      SearchResult.estimated_requests(result) > 10 ->
        {:noreply, assign(socket, load_warning?: true)}

      true ->
        {:noreply, load_page(socket, true, 10)}
    end
  end

  def handle_event("filter", %{"filter" => filter, "sort" => sort}, socket) do
    sort = if sort in ["name", "first_seen", "last_seen"], do: sort, else: "last_seen"
    {:noreply, socket |> assign(filter: filter, sort: sort) |> update_rows()}
  end

  def handle_event("select_network", %{"id" => id}, socket) do
    network = Enum.find(networks(socket), &(&1.id == id))

    if network do
      socket =
        if Enum.any?(socket.assigns.visible_networks, &(&1.id == id)) do
          socket
        else
          socket |> assign(filter: "") |> update_rows()
        end

      coordinates =
        if Network.valid_coordinates?(network), do: [network.longitude, network.latitude]

      {:noreply,
       socket
       |> assign(selected: network)
       |> push_event("network_selected", %{id: id, coordinates: coordinates})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_details", _, socket) do
    {:noreply, socket |> assign(selected: nil) |> push_event("network_selected", %{id: nil})}
  end

  def handle_event("map_sync", _, socket), do: {:noreply, update_map(socket)}

  @impl true
  def handle_async(:search, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(result: result, selected: nil, loading: nil, filter: "", load_all?: false)
     |> update_results()
     |> push_event("network_selected", %{id: nil})}
  end

  def handle_async(:page, {:ok, {:ok, result}}, socket) do
    socket = socket |> assign(result: result, loading: nil) |> update_results()

    cond do
      socket.assigns.load_all? and not result.complete? and socket.assigns.requests_left > 0 ->
        {:noreply, load_page(socket, true, socket.assigns.requests_left)}

      socket.assigns.load_all? and not result.complete? ->
        {:noreply, assign(socket, load_all?: false, load_warning?: true)}

      true ->
        {:noreply, assign(socket, load_all?: false)}
    end
  end

  def handle_async(_operation, {:ok, {:error, reason}}, socket), do: failure(socket, reason)
  def handle_async(_operation, {:exit, _reason}, socket), do: failure(socket, :api_failure)

  defp load_page(socket, all?, budget) do
    result = socket.assigns.result

    if not is_nil(socket.assigns.loading) or is_nil(result) or result.complete? do
      socket
    else
      socket
      |> assign(
        loading: :page,
        error: nil,
        load_warning?: false,
        load_all?: all?,
        requests_left: budget - 1
      )
      |> start_async(:page, fn -> Client.next_page(result) end)
    end
  end

  defp failure(socket, reason) do
    {:noreply, assign(socket, loading: nil, load_all?: false, error: error_message(reason))}
  end

  defp error_message(:missing_credentials),
    do: "Add WIGLE_API_NAME and WIGLE_API_TOKEN to .env, then recreate the app container."

  defp error_message(:authentication),
    do: "WiGLE authentication failed. Check WIGLE_API_NAME and WIGLE_API_TOKEN."

  defp error_message(:rate_limited),
    do: "WiGLE API limit reached. Existing loaded results remain available."

  defp error_message(:invalid_bounds),
    do:
      "Zoom in to a single map area before searching. Areas crossing the date line cannot be searched together."

  defp error_message(:invalid_network_type),
    do: "Select Wi-Fi, Bluetooth, or Cellular before searching."

  defp error_message({:invalid_search, message}), do: message

  defp error_message(:pagination_stalled),
    do:
      "WiGLE pagination did not advance. Loaded results remain available; try a smaller search area."

  defp error_message(_), do: "Unable to retrieve WiGLE data."

  defp update_results(socket) do
    dates =
      networks(socket) |> Enum.map(& &1.last_seen) |> Enum.filter(&is_binary/1) |> Enum.sort()

    socket
    |> assign(newest: List.last(dates), oldest: List.first(dates))
    |> update_rows()
    |> update_map()
  end

  defp update_rows(socket) do
    filter = String.downcase(String.trim(socket.assigns.filter))

    rows =
      networks(socket)
      |> Enum.filter(fn n ->
        String.contains?(String.downcase("#{n.name} #{n.identifier}"), filter)
      end)
      |> sort_rows(socket.assigns.sort)

    display_type =
      if socket.assigns.result,
        do: socket.assigns.result.network_type,
        else: socket.assigns.network_type

    assign(socket, visible_networks: rows, display_type: display_type)
  end

  defp sort_rows(rows, "name"), do: Enum.sort_by(rows, &String.downcase(&1.name || ""))
  defp sort_rows(rows, "first_seen"), do: Enum.sort_by(rows, &(&1.first_seen || ""), :desc)
  defp sort_rows(rows, _), do: Enum.sort_by(rows, &(&1.last_seen || ""), :desc)

  defp update_map(socket) do
    if socket.assigns.result do
      push_event(socket, "networks_updated", %{
        geojson: Network.feature_collection(networks(socket)),
        bounds: socket.assigns.result.bounds
      })
    else
      socket
    end
  end

  defp networks(%{assigns: %{result: nil}}), do: []
  defp networks(socket), do: socket.assigns.result.networks
end
