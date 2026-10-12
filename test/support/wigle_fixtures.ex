defmodule WigleExplorer.WigleFixtures do
  def bounds, do: %{"south" => 41.87, "north" => 41.89, "west" => -87.65, "east" => -87.61}

  def network(id, ssid \\ "Cafe Wi-Fi", last_seen \\ "2026-10-10T12:30:00.000Z") do
    %{
      "netid" => id,
      "ssid" => ssid,
      "trilat" => 41.8781,
      "trilong" => -87.6298,
      "encryption" => "WPA2",
      "channel" => 6,
      "type" => "WIFI",
      "qos" => 4,
      "firsttime" => "2024-01-02T10:00:00.000Z",
      "lasttime" => last_seen,
      "lastupdt" => "2026-10-11T09:00:00.000Z",
      "city" => "Chicago",
      "region" => "IL",
      "country" => "US",
      "userfound" => false,
      "extra_field" => "Preserve me"
    }
  end

  def bluetooth(id, name \\ "Library beacon") do
    network(id)
    |> Map.drop(["ssid", "encryption", "channel"])
    |> Map.merge(%{
      "name" => name,
      "type" => "BLE",
      "capabilities" => ["LE", "Beacon"],
      "device" => 1024,
      "mfgrId" => 76
    })
  end

  def cellular(id, name \\ "Cell observation") do
    network(id, name)
    |> Map.drop(["netid", "type", "encryption", "userfound"])
    |> Map.merge(%{
      "id" => id,
      "gentype" => "LTE",
      "attributes" => "Example cellular attributes",
      "channel" => 1300
    })
  end

  def response(records, total, cursor \\ nil) do
    %{
      "success" => true,
      "totalResults" => total,
      "resultCount" => length(records),
      "searchAfter" => cursor,
      "results" => records
    }
  end
end
