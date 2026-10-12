defmodule WigleExplorerWeb.ExplorerComponents do
  use WigleExplorerWeb, :html

  def display(nil), do: "—"
  def display(""), do: "—"
  def display(true), do: "Yes"
  def display(false), do: "No"
  def display([]), do: "—"
  def display(value) when is_list(value), do: Enum.map_join(value, ", ", &display/1)
  def display(value) when is_map(value), do: Jason.encode!(value)
  def display(value), do: to_string(value)

  def network_name(%{kind: "wifi", name: name}) when name in [nil, ""], do: "Hidden network"
  def network_name(%{kind: "bluetooth", name: name}) when name in [nil, ""], do: "Unnamed device"
  def network_name(%{name: name}) when name in [nil, ""], do: "Unnamed network"
  def network_name(network), do: network.name

  def type_label("wifi"), do: "Wi-Fi"
  def type_label("bluetooth"), do: "Bluetooth"
  def type_label("cellular"), do: "Cellular"

  def name_label("wifi"), do: "SSID"
  def name_label(_), do: "Name"
  def identifier_label("wifi"), do: "BSSID"
  def identifier_label("bluetooth"), do: "Device address"
  def identifier_label("cellular"), do: "Network ID"
  def record_label("bluetooth"), do: "devices"
  def record_label(_), do: "networks"

  def filter_placeholder("wifi"), do: "Filter by SSID or BSSID…"

  def filter_placeholder(kind),
    do:
      "Filter by #{String.downcase(name_label(kind))} or #{String.downcase(identifier_label(kind))}…"

  def type_column("wifi"), do: "Encryption"
  def type_column("bluetooth"), do: "Type"
  def type_column("cellular"), do: "Radio type"
  def extra_column("bluetooth"), do: "Capabilities"
  def extra_column(_), do: "Channel"
  def extra_value(%{kind: "bluetooth"} = network), do: display(network.capabilities)
  def extra_value(network), do: display(network.channel)
  def badge_value(%{kind: "wifi"} = network), do: display(network.encryption)
  def badge_value(network), do: display(network.type)
  def badge_class(%{kind: "wifi"} = network), do: encryption_class(network.encryption)
  def badge_class(_), do: "badge-neutral"
  def type_icon("wifi"), do: "wifi"
  def type_icon("bluetooth"), do: "bluetooth"
  def type_icon("cellular"), do: "cellular"

  def date(nil), do: "—"

  def date(value) do
    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, date} -> Calendar.strftime(date, "%b %-d, %Y")
      _ -> value
    end
  end

  def number(nil), do: "—"

  def number(value) do
    value
    |> to_string()
    |> String.reverse()
    |> String.replace(~r/\d{3}(?=\d)/, "\\0,")
    |> String.reverse()
  end

  def location(network) do
    [network.city, network.region, network.country]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
    |> display()
  end

  def encryption_class(value) when value in ["None", "NONE", "none", "Open", "OPEN"],
    do: "badge-open"

  def encryption_class(_), do: "badge-secure"

  attr :values, :map, required: true
  attr :loading, :atom, default: nil
  attr :configured?, :boolean, required: true
  attr :drawing?, :boolean, required: true

  def advanced_search_form(assigns) do
    ~H"""
    <form
      id="advanced-search-form"
      phx-change="advanced_change"
      phx-submit={JS.dispatch("wigle:advanced-search", to: "#map-shell")}
    >
      <h2>Search WiGLE</h2>
      <fieldset disabled={@loading != nil}>
        <div class="advanced-fields">
          <label>
            Type
            <select id="advanced-type" name="search[type]">
              <option value="wifi" selected={@values["type"] == "wifi"}>Wi-Fi</option>
              <option value="bluetooth" selected={@values["type"] == "bluetooth"}>Bluetooth</option>
            </select>
          </label>
          <label>
            Search by
            <select id="advanced-search-by" name="search[search_by]">
              <option value="name" selected={@values["search_by"] == "name"}>SSID / Name</option>
              <option value="mac" selected={@values["search_by"] == "mac"}>BSSID / MAC</option>
            </select>
          </label>
          <label class="advanced-value-field">
            Value
            <input
              id="advanced-value"
              name="search[value]"
              value={@values["value"]}
              type="text"
              required
              maxlength="256"
              autocomplete="off"
              placeholder={
                if @values["search_by"] == "mac",
                  do: "AA:BB:CC:DD:EE:FF",
                  else: "Network or device name"
              }
              phx-debounce="200"
            />
          </label>
          <label>
            Match
            <select
              id="advanced-match"
              name="search[match]"
              aria-describedby={if @values["search_by"] == "mac", do: "mac-search-hint"}
            >
              <option
                value="contains"
                selected={@values["match"] == "contains"}
                disabled={@values["search_by"] == "mac"}
              >
                Contains
              </option>
              <option value="exact" selected={@values["match"] == "exact"}>Exact</option>
              <option value="starts_with" selected={@values["match"] == "starts_with"}>
                Starts With
              </option>
            </select>
          </label>
        </div>
        <p :if={@values["search_by"] == "mac"} id="mac-search-hint" class="advanced-hint">
          MAC searches support exact addresses or prefixes of at least three complete octets, such as AA:BB:CC.
        </p>
        <p
          :if={
            @values["search_by"] == "name" && @values["match"] != "exact" &&
              String.contains?(@values["value"], ["%", "_"])
          }
          class="advanced-hint"
        >
          WiGLE treats % as any text and _ as one character. Choose Exact to match these characters literally.
        </p>
        <span class="optional-label">Optional filters</span>
        <div class="advanced-filters">
          <label>
            Encryption <span :if={@values["type"] == "bluetooth"} class="field-note">Wi-Fi only</span>
            <select
              id="advanced-encryption"
              name="search[encryption]"
              disabled={@values["type"] == "bluetooth"}
            >
              <option
                :for={
                  {label, value} <- [
                    {"Any", "any"},
                    {"Open/None", "None"},
                    {"WEP", "WEP"},
                    {"WPA", "WPA"},
                    {"WPA2", "WPA2"},
                    {"WPA3", "WPA3"},
                    {"Unknown", "Unknown"}
                  ]
                }
                value={value}
                selected={@values["encryption"] == value}
              >
                {label}
              </option>
            </select>
          </label>
          <label>
            Location
            <select id="advanced-location" name="search[location]">
              <option value="anywhere" selected={@values["location"] == "anywhere"}>Anywhere</option>
              <option value="map" selected={@values["location"] == "map"}>Current Map Area</option>
            </select>
          </label>
          <label>
            Seen within
            <select id="advanced-seen" name="search[seen_within]">
              <option
                :for={{label, value} <- WigleExplorer.Wigle.Search.seen_options()}
                value={value}
                selected={@values["seen_within"] == value}
              >
                {label}
              </option>
            </select>
          </label>
          <label :if={@values["seen_within"] == "custom"}>
            Seen on or after (UTC)
            <input
              id="advanced-date"
              type="date"
              name="search[custom_date]"
              value={@values["custom_date"]}
              max={Date.to_iso8601(Date.utc_today())}
              required
            />
          </label>
        </div>
      </fieldset>
      <div class="advanced-footer">
        <p>Current Map Area uses your drawn boundary, if selected. Dates use UTC.</p>
        <button
          id="advanced-submit"
          class="button button-primary"
          type="submit"
          disabled={!@configured? or @loading != nil or @drawing?}
        >
          <span :if={@loading == :search} class="spinner"></span>
          <.icon :if={@loading != :search} name="search" />
          {if @loading == :search, do: "Searching…", else: "Search"}
        </button>
      </div>
    </form>
    """
  end

  attr :network, :map, required: true

  def detail_drawer(assigns) do
    fields =
      [
        {identifier_label(assigns.network.kind), assigns.network.identifier},
        {"Coordinates", coordinates(assigns.network)}
      ] ++
        specific_fields(assigns.network) ++
        [
          {"First seen", assigns.network.first_seen},
          {"Last seen", assigns.network.last_seen},
          {"Last updated", assigns.network.last_updated},
          {"QoS", assigns.network.qos},
          {"Country", assigns.network.country},
          {"Region", assigns.network.region},
          {"City", assigns.network.city},
          {"Road", assigns.network.road},
          {"House number", assigns.network.house_number},
          {"Postal code", assigns.network.postal_code},
          {"Found by you", assigns.network.user_found}
        ]

    assigns = assign(assigns, :fields, fields)

    ~H"""
    <div class="drawer-backdrop" phx-click="close_details" aria-hidden="true"></div>
    <aside
      id="network-details"
      class="drawer"
      role="dialog"
      aria-modal="true"
      aria-labelledby="detail-title"
      phx-window-keydown="close_details"
      phx-key="Escape"
    >
      <.focus_wrap id="detail-focus">
        <div class="drawer-header">
          <span class="eyebrow">NETWORK DETAILS</span>
          <button
            class="icon-button"
            phx-click="close_details"
            aria-label="Close network details"
            autofocus
          ><.icon name="close" /></button>
        </div>
        <div class="drawer-title">
          <div class="network-symbol"><.icon name={type_icon(@network.kind)} /></div>
          <h2 id="detail-title">{network_name(@network)}</h2>
          <span class={["badge", badge_class(@network)]}>{badge_value(@network)}</span>
        </div>
        <p class="drawer-note">Details from the loaded search result.</p>
        <dl class="detail-fields">
          <div :for={{label, value} <- @fields}>
            <dt>{label}</dt><dd>{display(value)}</dd>
          </div>
        </dl>
        <details class="raw-data">
          <summary>All WiGLE fields <.icon name="chevron" /></summary>
          <pre>{Jason.encode!(@network.raw, pretty: true)}</pre>
        </details>
      </.focus_wrap>
    </aside>
    """
  end

  defp specific_fields(%{kind: "wifi"} = network) do
    [
      {"Encryption", network.encryption},
      {"Channel", network.channel},
      {"Network type", network.type}
    ]
  end

  defp specific_fields(%{kind: "bluetooth"} = network) do
    [
      {"Bluetooth type", network.type},
      {"Capabilities", network.capabilities},
      {"Device class", network.device_class},
      {"Manufacturer ID", network.manufacturer_id}
    ]
  end

  defp specific_fields(%{kind: "cellular"} = network) do
    [
      {"Radio type", network.type},
      {"Channel", network.channel},
      {"Attributes", network.attributes}
    ]
  end

  defp coordinates(network) do
    if WigleExplorer.Wigle.Network.valid_coordinates?(network) do
      "#{Float.round(network.latitude / 1, 6)}, #{Float.round(network.longitude / 1, 6)}"
    end
  end
end
