# WiGLE Explorer

A small Phoenix LiveView app for exploring WiGLE Wi-Fi, Bluetooth, and cellular observations on a MapLibre map, with a searchable table and full returned details. Searches and pagination are explicit; moving the map never queries WiGLE.

## Setup

Only Docker and Docker Compose are required.

```sh
cp .env.example .env
```

Add your WiGLE API name and token to `.env`. The default map style needs no key; replace `MAP_STYLE_URL` if desired.

## Run

```sh
docker compose up --build
```

Open http://localhost:4100. Change `APP_PORT` in `.env` to use another host port. For a second independent copy, also set a different `COMPOSE_PROJECT_NAME`.

Choose **Network type**, then search the visible map or click **Draw area** and drag a rectangle. Draw again to replace it; **Clear area** restores viewport search. Drawing and changing type never query WiGLE. Loaded results keep their original type and pagination until a new search succeeds.

Open **Advanced search** to search Wi-Fi SSIDs or Bluetooth names and MAC addresses. Name matching supports Contains (default), Exact, and Starts With. WiGLE's name patterns treat `%` and `_` as wildcards; Exact matches them literally. MAC searches support Exact (six octets) or Starts With (at least three complete octets). Encryption applies to Wi-Fi only.

Choose **Anywhere** or **Current Map Area**, which uses the drawn boundary when present. Seen-within presets filter WiGLE's last submitted observation time; **Custom Date** means on or after midnight UTC. Press **Search** to get a total and the first batch of up to 100 records in one request. Pagination keeps the original filters and date cutoff; form edits never query WiGLE.

After editing credentials, run `docker compose up -d --force-recreate`.

## Stop

```sh
docker compose down
```

## Architecture

- LiveView owns loaded records, filtering, sorting, selection, and pagination.
- One MapLibre hook renders a clustered GeoJSON source and sends bounds only on search.
- `Wigle.Client` authenticates server-side with Req and follows WiGLE's `searchAfter` cursor.
- Network structs retain all raw fields; opening details makes no API call.
- Load all estimates requests from the returned batch size and stops after at most 10 calls.
- No database, cache, accounts, or background polling. Build and dependency directories live in Compose volumes.

Run the focused tests with `docker compose run --rm app mix test`.
