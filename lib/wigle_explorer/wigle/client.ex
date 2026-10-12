defmodule WigleExplorer.Wigle.Client do
  require Logger
  alias WigleExplorer.Wigle.{Search, SearchResult}

  @search_paths %{
    "wifi" => "/api/v2/network/search",
    "bluetooth" => "/api/v2/bluetooth/search",
    "cellular" => "/api/v2/cell/search"
  }

  def configured? do
    {name, token} = credentials()
    is_binary(name) and String.trim(name) != "" and is_binary(token) and String.trim(token) != ""
  end

  def search_networks(bounds, options \\ []) do
    network_type = Keyword.get(options, :network_type, "wifi")
    filters = Keyword.get(options, :filters, %{})
    description = Keyword.get(options, :description)

    with :ok <- check_credentials(),
         :ok <- check_bounds(bounds, filters),
         {:ok, path} <- search_path(network_type) do
      params = Map.put(filters, :resultsPerPage, 100)

      params =
        if bounds do
          Map.merge(params, %{
            latrange1: bounds["south"],
            latrange2: bounds["north"],
            longrange1: bounds["west"],
            longrange2: bounds["east"]
          })
        else
          params
        end

      params =
        case Keyword.get(options, :search_after) do
          nil -> params
          cursor -> Map.put(params, :searchAfter, cursor)
        end

      request(path, params, %{
        bounds: bounds,
        network_type: network_type,
        filters: filters,
        description: description
      })
    end
  end

  def advanced_search(criteria, bounds) do
    with {:ok, search} <- Search.prepare(criteria, bounds) do
      search_networks(search.bounds,
        network_type: search.network_type,
        filters: search.filters,
        description: search.description
      )
    end
  end

  def next_page(%SearchResult{complete?: true} = result), do: {:ok, result}

  def next_page(%SearchResult{} = result) do
    with {:ok, page} <-
           search_networks(result.bounds,
             search_after: result.search_after,
             network_type: result.network_type,
             filters: result.filters,
             description: result.description
           ) do
      merged = SearchResult.append(result, page)

      if not merged.complete? and
           (page.search_after == result.search_after or
              length(merged.networks) == length(result.networks)) do
        Logger.warning("WiGLE pagination stopped: cursor or records did not advance")
        {:error, :pagination_stalled}
      else
        {:ok, merged}
      end
    end
  end

  defp request(path, params, context) do
    {name, token} = credentials()

    options = [
      url: "https://api.wigle.net" <> path,
      auth: {:basic, "#{name}:#{token}"},
      params: params,
      retry: false,
      redirect: false,
      receive_timeout: 40_000
    ]

    options
    |> Keyword.merge(Application.get_env(:wigle_explorer, :wigle_req_options, []))
    |> Req.get()
    |> parse_response(context)
  end

  defp parse_response(
         {:ok,
          %{
            status: 200,
            body:
              %{
                "success" => true,
                "results" => records,
                "totalResults" => total,
                "resultCount" => count
              } = body
          }},
         context
       )
       when is_list(records) and is_integer(total) and total >= 0 and is_integer(count) do
    Logger.info(
      "WiGLE #{context.network_type} search succeeded: #{length(records)} returned, #{total} matching"
    )

    result = SearchResult.from_response(body, context.bounds, context.network_type)
    {:ok, %{result | filters: context.filters, description: context.description}}
  end

  defp parse_response({:ok, %{status: status}}, _) when status in [401, 403] do
    Logger.warning("WiGLE authentication failed")
    {:error, :authentication}
  end

  defp parse_response({:ok, %{status: 429}}, _) do
    Logger.warning("WiGLE API limit reached (429)")
    {:error, :rate_limited}
  end

  defp parse_response({:ok, %{status: status}}, _) do
    Logger.warning("WiGLE returned an unsuccessful or unexpected response (HTTP #{status})")
    {:error, :api_failure}
  end

  defp parse_response({:error, _reason}, _) do
    Logger.warning("WiGLE request failed")
    {:error, :api_failure}
  end

  defp search_path(network_type) do
    case Map.fetch(@search_paths, network_type) do
      {:ok, path} -> {:ok, path}
      :error -> {:error, :invalid_network_type}
    end
  end

  defp credentials do
    Application.get_env(:wigle_explorer, :wigle_credentials, {nil, nil})
  end

  defp check_credentials do
    if configured?(), do: :ok, else: {:error, :missing_credentials}
  end

  defp check_bounds(nil, filters) do
    if Enum.any?([:ssid, :ssidlike, :name, :namelike, :netid], fn key ->
         is_binary(filters[key]) and String.trim(filters[key]) != ""
       end),
       do: :ok,
       else: {:error, :invalid_bounds}
  end

  defp check_bounds(
         %{"south" => south, "north" => north, "west" => west, "east" => east},
         _filters
       )
       when is_number(south) and is_number(north) and is_number(west) and is_number(east) and
              south >= -90 and north <= 90 and south < north and
              west >= -180 and east <= 180 and west < east,
       do: :ok

  defp check_bounds(_, _), do: {:error, :invalid_bounds}
end
