defmodule WigleExplorer.Wigle.SearchResult do
  alias WigleExplorer.Wigle.Network

  defstruct networks: [],
            total_results: 0,
            result_count: 0,
            search_after: nil,
            complete?: false,
            bounds: nil,
            network_type: "wifi",
            filters: %{},
            description: nil,
            page_size: 0

  def from_response(body, bounds, network_type \\ "wifi") do
    networks = Enum.map(body["results"], &Network.from_raw(&1, network_type))
    cursor = body["searchAfter"]
    total = body["totalResults"]

    %__MODULE__{
      networks: networks,
      total_results: total,
      result_count: body["resultCount"],
      search_after: cursor,
      bounds: bounds,
      network_type: network_type,
      page_size: length(networks),
      complete?: length(networks) >= total or cursor in [nil, ""] or networks == []
    }
  end

  def append(previous, page) do
    networks = Enum.uniq_by(previous.networks ++ page.networks, & &1.id)

    %{
      page
      | networks: networks,
        page_size: if(page.page_size > 0, do: page.page_size, else: previous.page_size),
        complete?: page.complete? or length(networks) >= page.total_results
    }
  end

  def remaining(result), do: max(result.total_results - length(result.networks), 0)

  def estimated_requests(%{complete?: true}), do: 0
  def estimated_requests(result), do: ceil(remaining(result) / max(result.page_size, 1))
end
