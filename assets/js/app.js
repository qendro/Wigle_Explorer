import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import MapHook from "./hooks/map_hook"
import "maplibre-gl/dist/maplibre-gl.css"
import "../css/app.css"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {MapHook}
})

liveSocket.connect()
