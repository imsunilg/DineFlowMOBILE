# DineFlowMOBILE

Flutter (Material 3) client for the DineFlow bar & restaurant platform. It talks to the same REST API as the
Angular app (`DineFlowAPI`) and contains **no business rules**: prices, taxes, discounts, stock and totals are all
computed by the API. The app only shows what the API returns and sends the user's intent.

| Role | Bottom bar |
| --- | --- |
| Waiter | Tables, Orders, Customers, New order |
| Bartender | Bar orders, Bar stock, Orders |
| Manager / Owner | Dashboard, Orders, Inventory, Tables |
| Kitchen staff | Kitchen, Orders |
| Cashier, Receptionist, Accountant, Inventory manager, Supervisor | Their own short list (see `lib/core/nav.dart`) |
| Any custom role | Every screen the role is permitted to open |

Everything else the user may open is under **More**. A screen is only listed when the user holds its permission
*and* the tenant has that module switched on; opening a forbidden route redirects to the user's home screen. The API
enforces permissions independently.

## Prerequisites

- Flutter 3.47+ (Dart 3.13+), Android SDK for Android builds, Xcode for iOS builds
- A running `DineFlowAPI` reachable from the device (see that repository's README)

## Install

```bash
flutter pub get
```

## Configuration

Nothing about the environment or the customer is compiled in. Two values are needed:

| Value | `--dart-define` | Default | Notes |
| --- | --- | --- | --- |
| API address | `API_BASE_URL` | `http://10.0.2.2:5080/api/v1` | `10.0.2.2` is the host machine as seen from the Android emulator |
| Business code | `TENANT_CODE` | empty | Optional. Shows that tenant's logo/colours on the sign-in screen |

Users can change both at runtime from **Server settings** on the sign-in screen; the values are stored with
`shared_preferences`.

Branding (business name, colours, currency symbol, enabled modules) is fetched from `GET /api/v1/config/branding` and
applied to the theme, so a second tenant shows *its own* name and currency with no rebuild.

## Run

```bash
# Android emulator against an API on the same machine
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080/api/v1 --dart-define=TENANT_CODE=DINEFLOW

# Physical device on the same Wi-Fi
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5080/api/v1
```

Development sign-in (created by the API's dev seeder): `admin@dineflow.local` / `DineFlow@Dev1`.

Debug builds allow plain `http`; **release builds require `https`** (Android's default; iOS App Transport Security).

## Authentication

- Sign in with email + password (`POST /auth/login`); the API returns a short-lived JWT access token and a rotating refresh token.
- Tokens are kept in the platform keystore via `flutter_secure_storage` (Keychain / EncryptedSharedPreferences), never in plain preferences.
- A `401` triggers **one** shared refresh (`POST /auth/refresh`) and a retry of the failed request; if the refresh fails the user is signed out with a clear message.
- Sign-out revokes the refresh token on the server.
- The tenant is taken from the JWT on the server; the app never sends a tenant id.

## Screens

Login, Dashboard (KPIs, 7-day sales, top items, low stock), Tables (live floor plan), Orders (paged, filterable),
Order detail (edit, send to kitchen, serve, cancel, bill and split payment), POS (menu search, variants, add-ons, notes),
Kitchen (live tickets per station), Bar orders and Bar stock (bottles + loose ml), Customers (search, add, 360 profile),
Reservations (day view, book, status changes), Inventory (stock and alerts), Alerts (notifications), Profile, Server settings.

## Project layout

```text
lib/
  main.dart               bootstrap (config, tokens, providers)
  app.dart                go_router, auth + permission redirects, theme from branding
  core/                   api_client, auth_controller, branding_controller, nav (role profiles), models, config, token_store
  features/               one file per screen area
  ui/common.dart          AsyncBody (loading/error/empty/refresh), StatusChip, toasts
test/                     unit + widget tests (fake API), optional live contract test
```

State management is `provider` with two small `ChangeNotifier`s (auth and branding); screens load their own data
through `AsyncBody`, so there is no duplicated global cache to go stale.

## Tests

```bash
flutter analyze
flutter test                      # unit + widget tests, no server needed
```

Optional contract test against a running API (skipped unless `LIVE_API_URL` is set). It signs in, parses every screen's
real responses with the app's models and runs a full order: create, add item, send, bill, pay.

```bash
LIVE_API_URL=http://localhost:5080/api/v1 LIVE_EMAIL=admin@dineflow.local LIVE_PASSWORD='DineFlow@Dev1' \
  flutter test test/live_api_test.dart
```

## Build

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-server/api/v1
flutter build appbundle --release --dart-define=API_BASE_URL=https://your-server/api/v1
```

Configure release signing per the [Flutter deployment guide](https://docs.flutter.dev/deployment/android).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "Cannot reach the server" | Check the API address in *Server settings*. On the emulator use `10.0.2.2`, not `localhost`. On a phone use the PC's LAN IP and allow the port through the firewall. |
| Works in debug, fails in release | Release builds need `https`. Put the API behind a TLS reverse proxy. |
| Signed out unexpectedly | The refresh token expired or was revoked (password change, sign-out elsewhere). Sign in again. |
| A screen is missing | The role lacks the permission, or the tenant disabled that module (Business settings in the web app). |
| Prices look wrong | They never come from the app. Check taxes and billing rules in the web app (Finance). |
