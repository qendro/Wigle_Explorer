defmodule WigleExplorerWeb.CoreComponents do
  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(assigns) do
    paths = %{
      "bluetooth" => ["M12 3l6 6-12 6", "M6 9l12 6-6 6V3"],
      "cellular" => [
        "M12 12v9",
        "M8 21h8",
        "M8 8a6 6 0 0 0 0 8",
        "M16 8a6 6 0 0 1 0 8",
        "M5 5a10 10 0 0 0 0 14",
        "M19 5a10 10 0 0 1 0 14"
      ],
      "wifi" => [
        "M2 8.5a16 16 0 0 1 20 0",
        "M5 12a11 11 0 0 1 14 0",
        "M8.5 15.5a5.5 5.5 0 0 1 7 0",
        "M12 19h.01"
      ],
      "search" => ["M21 21l-4.5-4.5", "M19 11a8 8 0 1 1-16 0 8 8 0 0 1 16 0"],
      "area" => [
        "M9 3H5a2 2 0 0 0-2 2v4",
        "M15 3h4a2 2 0 0 1 2 2v4",
        "M21 15v4a2 2 0 0 1-2 2h-4",
        "M3 15v4a2 2 0 0 0 2 2h4",
        "M12 8v8",
        "M8 12h8"
      ],
      "arrow" => ["M7 17L17 7", "M7 7h10v10"],
      "close" => ["M6 6l12 12", "M18 6L6 18"],
      "pin" => [
        "M20 10c0 6-8 11-8 11S4 16 4 10a8 8 0 1 1 16 0",
        "M15 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0"
      ],
      "info" => ["M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0", "M12 11v6", "M12 7h.01"],
      "chevron" => ["M9 5l7 7-7 7"],
      "layers" => ["M12 3L2 8l10 5 10-5-10-5", "M2 12l10 5 10-5", "M2 16l10 5 10-5"]
    }

    assigns = assign(assigns, :paths, Map.fetch!(paths, assigns.name))

    ~H"""
    <svg
      class={["icon", @class]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path :for={path <- @paths} d={path} />
    </svg>
    """
  end
end
