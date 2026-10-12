defmodule WigleExplorer.Wigle.Network do
  defstruct [
    :id,
    :kind,
    :name,
    :identifier,
    :ssid,
    :bssid,
    :latitude,
    :longitude,
    :encryption,
    :channel,
    :type,
    :capabilities,
    :device_class,
    :manufacturer_id,
    :attributes,
    :qos,
    :first_seen,
    :last_seen,
    :last_updated,
    :country,
    :region,
    :city,
    :road,
    :house_number,
    :postal_code,
    :user_found,
    :raw
  ]

  def from_raw(raw, kind \\ "wifi") do
    bssid = raw["netid"] || raw["bssid"]
    identifier = bssid || raw["id"]
    identifier = if identifier, do: to_string(identifier)

    name =
      if kind == "bluetooth", do: raw["name"] || raw["ssid"], else: raw["ssid"] || raw["name"]

    %__MODULE__{
      id: identifier || Base.encode16(:crypto.hash(:sha256, Jason.encode!(raw))),
      kind: kind,
      name: name,
      identifier: identifier,
      ssid: raw["ssid"],
      bssid: bssid,
      latitude: raw["trilat"] || raw["latitude"],
      longitude: raw["trilong"] || raw["longitude"],
      encryption: raw["encryption"],
      channel: raw["channel"],
      type: raw["gentype"] || raw["type"],
      capabilities: raw["capabilities"],
      device_class: raw["device"],
      manufacturer_id: raw["mfgrId"],
      attributes: raw["attributes"],
      qos: raw["qos"],
      first_seen: raw["firsttime"],
      last_seen: raw["lasttime"],
      last_updated: raw["lastupdt"],
      country: raw["country"],
      region: raw["region"],
      city: raw["city"],
      road: raw["road"],
      house_number: raw["housenumber"],
      postal_code: raw["postalcode"],
      user_found: raw["userfound"],
      raw: raw
    }
  end

  def feature_collection(networks) do
    features =
      for network <- networks, valid_coordinates?(network) do
        %{
          type: "Feature",
          id: network.id,
          geometry: %{type: "Point", coordinates: [network.longitude, network.latitude]},
          properties: %{id: network.id, name: network.name, last_seen: network.last_seen}
        }
      end

    %{type: "FeatureCollection", features: features}
  end

  def valid_coordinates?(%{latitude: lat, longitude: lon}) do
    is_number(lat) and is_number(lon) and lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180
  end
end
