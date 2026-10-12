defmodule WigleExplorer.Wigle.Search do
  @defaults %{
    "type" => "wifi",
    "search_by" => "name",
    "value" => "",
    "match" => "contains",
    "encryption" => "any",
    "location" => "anywhere",
    "seen_within" => "any",
    "custom_date" => ""
  }

  @seen_options [
    {"Any Time", "any"},
    {"Last 24 Hours", "24h"},
    {"Last 7 Days", "7d"},
    {"Last 30 Days", "30d"},
    {"Last 90 Days", "90d"},
    {"Last 1 Year", "1y"},
    {"Last 5 Years", "5y"},
    {"Custom Date", "custom"}
  ]

  def defaults, do: @defaults
  def seen_options, do: @seen_options

  # Keep form controls compatible when the user changes type or search field.
  def form_values(params) do
    text_params =
      params
      |> Map.take(Map.keys(@defaults))
      |> Enum.filter(fn {_key, value} -> is_binary(value) end)
      |> Map.new()

    values = Map.merge(@defaults, text_params)

    values =
      if values["type"] == "bluetooth", do: Map.put(values, "encryption", "any"), else: values

    if values["search_by"] == "mac" and values["match"] == "contains",
      do: Map.put(values, "match", "exact"),
      else: values
  end

  def prepare(params, bounds, now \\ DateTime.utc_now()) do
    values = Map.merge(@defaults, Map.take(params, Map.keys(@defaults)))

    with :ok <- validate_choices(values),
         :ok <- location_bounds(values, bounds),
         {:ok, name_filter} <- name_filter(values),
         {:ok, cutoff} <- cutoff(values, now) do
      filters = Map.new([name_filter])
      filters = if cutoff, do: Map.put(filters, :lasttime, cutoff), else: filters

      filters =
        if values["encryption"] != "any",
          do: Map.put(filters, :encryption, values["encryption"]),
          else: filters

      {:ok,
       %{
         bounds: if(values["location"] == "map", do: bounds),
         network_type: values["type"],
         filters: filters,
         description: description(values)
       }}
    end
  end

  defp validate_choices(v) do
    valid? =
      v["type"] in ["wifi", "bluetooth"] and v["search_by"] in ["name", "mac"] and
        v["match"] in ["contains", "exact", "starts_with"] and
        v["encryption"] in ["any", "None", "WEP", "WPA", "WPA2", "WPA3", "Unknown"] and
        v["location"] in ["anywhere", "map"] and
        v["seen_within"] in Enum.map(@seen_options, &elem(&1, 1))

    cond do
      not valid? ->
        invalid("Choose valid search options.")

      v["type"] == "bluetooth" and v["encryption"] != "any" ->
        invalid("Encryption filtering is available for Wi-Fi only.")

      true ->
        :ok
    end
  end

  defp name_filter(%{"value" => value} = v) when is_binary(value) do
    cond do
      String.trim(value) == "" ->
        invalid("Enter an SSID, name, or MAC address to search.")

      String.length(value) > 256 ->
        invalid("Keep the search value to 256 characters or fewer.")

      v["search_by"] == "mac" ->
        mac_filter(String.trim(value), v["match"])

      true ->
        key = if v["type"] == "wifi", do: :ssid, else: :name

        case v["match"] do
          "exact" -> {:ok, {key, value}}
          "contains" -> {:ok, {like_key(key), "%" <> value <> "%"}}
          "starts_with" -> {:ok, {like_key(key), value <> "%"}}
        end
    end
  end

  defp name_filter(_), do: invalid("Enter a text value to search.")
  defp like_key(:ssid), do: :ssidlike
  defp like_key(:name), do: :namelike

  defp mac_filter(value, match) do
    value = value |> String.replace("-", ":") |> String.upcase()
    valid? = Regex.match?(~r/\A[0-9A-F]{2}(?::[0-9A-F]{2}){2,5}\z/, value)

    cond do
      match not in ["exact", "starts_with"] or not valid? ->
        invalid(
          "MAC searches support Exact or Starts With, using at least three complete octets (AA:BB:CC)."
        )

      match == "exact" and length(String.split(value, ":")) != 6 ->
        invalid("Exact MAC searches need all six octets, for example AA:BB:CC:DD:EE:FF.")

      true ->
        {:ok, {:netid, value}}
    end
  end

  defp location_bounds(%{"location" => "map"}, bounds) when not is_map(bounds),
    do: {:error, :invalid_bounds}

  defp location_bounds(_, _), do: :ok

  defp cutoff(%{"seen_within" => "any"}, _now), do: {:ok, nil}

  defp cutoff(%{"seen_within" => "custom", "custom_date" => value}, now) do
    with true <- is_binary(value),
         {:ok, date} <- Date.from_iso8601(value),
         true <- Date.compare(date, DateTime.to_date(now)) != :gt do
      {:ok, Calendar.strftime(date, "%Y%m%d") <> "000000"}
    else
      _ -> invalid("Choose a valid custom date on or before today (UTC).")
    end
  end

  defp cutoff(%{"seen_within" => period}, now) do
    time =
      case period do
        "24h" -> DateTime.add(now, -86_400, :second)
        "7d" -> DateTime.add(now, -7 * 86_400, :second)
        "30d" -> DateTime.add(now, -30 * 86_400, :second)
        "90d" -> DateTime.add(now, -90 * 86_400, :second)
        "1y" -> DateTime.shift(now, year: -1)
        "5y" -> DateTime.shift(now, year: -5)
      end

    {:ok, Calendar.strftime(time, "%Y%m%d%H%M%S")}
  end

  defp description(v) do
    field =
      if v["search_by"] == "mac",
        do: "MAC",
        else: if(v["type"] == "wifi", do: "SSID", else: "Name")

    match =
      %{"contains" => "contains", "exact" => "equals", "starts_with" => "starts with"}[v["match"]]

    location = if v["location"] == "map", do: "Current Map Area", else: "Anywhere"

    seen =
      if v["seen_within"] == "custom",
        do: "Since #{v["custom_date"]} (UTC)",
        else:
          Enum.find_value(@seen_options, fn {label, value} ->
            if value == v["seen_within"], do: label
          end)

    [
      "#{field} #{match} “#{v["value"]}”",
      if(v["encryption"] != "any", do: v["encryption"]),
      location,
      seen
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp invalid(message), do: {:error, {:invalid_search, message}}
end
