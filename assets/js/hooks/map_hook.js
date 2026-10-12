import {Map, NavigationControl, ScaleControl, setWorkerUrl, getVersion} from "maplibre-gl"

setWorkerUrl(`/assets/js/maplibre-gl-worker.js?v=${getVersion()}`)

const emptyCollection = () => ({type: "FeatureCollection", features: []})

export default {
  mounted() {
    this.data = emptyCollection()
    this.searchBounds = null
    this.selectedId = null
    this.areaBounds = null
    this.drawing = false
    this.drawStart = null
    this.events = new AbortController()
    this.drawingSurface = this.el.querySelector("#area-drawing-surface")
    this.ready = false
    this.search = () => {
      if (!this.ready || this.drawing) return
      this.pushEvent("search_area", {bounds: this.areaBounds || this.bounds()})
    }
    const options = {signal: this.events.signal}
    this.el.addEventListener("wigle:search", this.search, options)
    this.el.addEventListener("wigle:advanced-search", () => {
      if (this.drawing) return
      const form = document.getElementById("advanced-search-form")
      const criteria = Object.fromEntries(Array.from(new FormData(form), ([name, value]) => [
        name.replace(/^search\[(.+)\]$/, "$1"), value
      ]))
      // A missing map sends null, which the server rejects for Current Map Area.
      const bounds = criteria.location === "map" && this.ready ? this.areaBounds || this.bounds() : null
      this.pushEvent("advanced_search", {criteria, bounds})
    }, options)
    this.el.addEventListener("wigle:draw", () => this.setDrawing(!this.drawing), options)
    this.el.addEventListener("wigle:clear-area", () => {
      this.areaBounds = null
      this.setDrawing(false)
    }, options)
    this.drawingSurface.addEventListener("pointerdown", event => {
      if (!event.isPrimary || event.button !== 0) return
      event.preventDefault()
      this.drawStart = this.drawPoint(event)
      this.drawingSurface.setPointerCapture(event.pointerId)
      this.renderArea(null)
    }, options)
    this.drawingSurface.addEventListener("pointermove", event => {
      if (this.drawStart) this.renderArea(this.boxBounds(this.drawStart, this.drawPoint(event)))
    }, options)
    this.drawingSurface.addEventListener("pointerup", event => this.finishDrawing(event), options)
    this.drawingSurface.addEventListener("pointercancel", () => this.setDrawing(false), options)
    document.addEventListener("keydown", event => {
      if (event.key === "Escape" && this.drawing) {
        event.preventDefault()
        this.setDrawing(false)
      }
    }, options)

    this.handleEvent("networks_updated", ({geojson, bounds}) => {
      this.data = geojson
      this.searchBounds = bounds
      if (this.ready) this.map.getSource("networks").setData(geojson)
      this.updateViewport()
    })
    this.handleEvent("network_selected", ({id, coordinates}) => {
      this.selectedId = id
      this.highlight()
      if (coordinates && this.ready) {
        this.map.easeTo({center: coordinates, zoom: Math.max(this.map.getZoom(), 16), duration: 350})
      }
    })

    try {
      this.map = new Map({
        container: this.el.querySelector("#map-canvas"),
        style: this.el.dataset.style,
        center: [-87.6298, 41.8781],
        zoom: 13,
        minZoom: 2,
        dragRotate: false,
        renderWorldCopies: false,
        attributionControl: {compact: true}
      })
      this.map.touchZoomRotate.disableRotation()
      this.map.addControl(new NavigationControl({showCompass: false}), "top-right")
      this.map.addControl(new ScaleControl({maxWidth: 100}), "bottom-left")
      this.map.on("load", () => {
        this.addNetworks()
        this.ready = true
        this.el.dataset.ready = "true"
        this.updateViewport()
        this.pushEvent("map_sync", {})
      })
      this.map.on("moveend", () => this.updateViewport())
      this.map.on("error", () => {
        const error = this.el.querySelector("#map-error")
        error.textContent = "Some map resources could not load. Check MAP_STYLE_URL and your connection."
        error.hidden = false
      })
      this.resizeObserver = new ResizeObserver(() => this.map.resize())
      this.resizeObserver.observe(this.el)
    } catch (_) {
      const error = this.el.querySelector("#map-error")
      error.textContent = "The map could not start. This browser needs WebGL support."
      error.hidden = false
    }
  },

  addNetworks() {
    this.map.addSource("search-area", {type: "geojson", data: emptyCollection()})
    this.map.addLayer({
      id: "search-area-fill", type: "fill", source: "search-area",
      paint: {"fill-color": "#2f7163", "fill-opacity": 0.08}
    })
    this.map.addLayer({
      id: "search-area-outline", type: "line", source: "search-area",
      paint: {"line-color": "#2f7163", "line-width": 2}
    })
    this.map.addSource("networks", {
      type: "geojson", data: this.data,
      cluster: true, clusterMaxZoom: 14, clusterRadius: 42
    })
    this.map.addLayer({
      id: "clusters", type: "circle", source: "networks", filter: ["has", "point_count"],
      paint: {
        "circle-color": "#2f7163", "circle-opacity": 0.94,
        "circle-radius": ["step", ["get", "point_count"], 19, 100, 25, 500, 30],
        "circle-stroke-width": 5, "circle-stroke-color": "#2f7163", "circle-stroke-opacity": 0.16
      }
    })
    this.map.addLayer({
      id: "cluster-count", type: "symbol", source: "networks", filter: ["has", "point_count"],
      layout: {"text-field": "{point_count_abbreviated}", "text-font": ["Noto Sans Regular"], "text-size": 12},
      paint: {"text-color": "#fff"}
    })
    this.map.addLayer({
      id: "network-points", type: "circle", source: "networks", filter: ["!", ["has", "point_count"]],
      paint: {"circle-color": "#388a75", "circle-radius": 5, "circle-stroke-width": 2, "circle-stroke-color": "#fff"}
    })
    this.map.addLayer({
      id: "selected-network", type: "circle", source: "networks",
      filter: ["==", ["get", "id"], ""],
      paint: {"circle-color": "#c4792e", "circle-radius": 9, "circle-stroke-width": 3, "circle-stroke-color": "#fff"}
    })
    this.map.on("click", "clusters", async event => {
      const feature = event.features[0]
      const zoom = await this.map.getSource("networks").getClusterExpansionZoom(feature.properties.cluster_id)
      this.map.easeTo({center: feature.geometry.coordinates, zoom})
    })
    for (const layer of ["network-points", "selected-network"]) {
      this.map.on("click", layer, event => {
        this.pushEvent("select_network", {id: event.features[0].properties.id})
      })
    }
    for (const layer of ["clusters", "network-points", "selected-network"]) {
      this.map.on("mouseenter", layer, () => { this.map.getCanvas().style.cursor = "pointer" })
      this.map.on("mouseleave", layer, () => { this.map.getCanvas().style.cursor = "" })
    }
  },

  highlight() {
    if (this.ready) this.map.setFilter("selected-network", ["==", ["get", "id"], this.selectedId || ""])
  },

  setDrawing(enabled) {
    if (!this.ready) return
    this.map.stop()
    this.drawing = enabled
    this.drawStart = null
    this.drawingSurface.hidden = !enabled
    this.el.querySelector("#area-draw-hint").hidden = !enabled
    this.renderArea(this.areaBounds)
    this.pushEvent("area_selection", {selected: !!this.areaBounds, drawing: enabled})
    this.updateViewport()
    if (enabled) this.drawingSurface.focus({preventScroll: true})
    else document.getElementById("draw-area").focus({preventScroll: true})
  },

  drawPoint(event) {
    const rect = this.map.getCanvas().getBoundingClientRect()
    return [
      Math.max(0, Math.min(rect.width, event.clientX - rect.left)),
      Math.max(0, Math.min(rect.height, event.clientY - rect.top))
    ]
  },

  boxBounds(start, end) {
    const a = this.map.unproject(start)
    const b = this.map.unproject(end)
    return {
      south: Math.max(-90, Math.min(a.lat, b.lat)), north: Math.min(90, Math.max(a.lat, b.lat)),
      west: Math.max(-180, Math.min(a.lng, b.lng)), east: Math.min(180, Math.max(a.lng, b.lng))
    }
  },

  finishDrawing(event) {
    if (!this.drawStart) return
    const end = this.drawPoint(event)
    if (Math.abs(end[0] - this.drawStart[0]) < 8 || Math.abs(end[1] - this.drawStart[1]) < 8) {
      this.drawStart = null
      this.renderArea(this.areaBounds)
      return
    }
    this.areaBounds = this.boxBounds(this.drawStart, end)
    this.setDrawing(false)
  },

  renderArea(bounds) {
    const data = emptyCollection()
    if (bounds) {
      const {west, east, south, north} = bounds
      data.features.push({
        type: "Feature", properties: {},
        geometry: {type: "Polygon", coordinates: [[[west, south], [east, south], [east, north], [west, north], [west, south]]]}
      })
    }
    this.map.getSource("search-area").setData(data)
  },

  bounds() {
    const bounds = this.map.getBounds()
    return {
      south: Math.max(-90, bounds.getSouth()), north: Math.min(90, bounds.getNorth()),
      west: Math.max(-180, bounds.getWest()), east: Math.min(180, bounds.getEast())
    }
  },

  updateViewport() {
    if (!this.map) return
    const center = this.map.getCenter()
    this.el.querySelector("#map-coordinates").textContent = `${center.lat.toFixed(4)}, ${center.lng.toFixed(4)}`
    this.el.querySelector("#map-area-label").textContent = this.areaBounds ? "SELECTED AREA" : "VISIBLE AREA"
    const bounds = this.areaBounds || this.bounds()
    const moved = this.searchBounds && Object.keys(bounds).some(key => Math.abs(bounds[key] - this.searchBounds[key]) > 0.00001)
    this.el.querySelector("#map-moved").hidden = !moved || this.drawing
  },

  reconnected() {
    this.pushEvent("map_sync", {})
    this.pushEvent("area_selection", {selected: !!this.areaBounds, drawing: this.drawing})
  },

  destroyed() {
    this.events.abort()
    this.resizeObserver?.disconnect()
    this.map?.remove()
  }
}
