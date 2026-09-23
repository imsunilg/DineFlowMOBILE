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
| API address | `API_BASE_URL` | `http://<apiHost>:5100/api/v1` | `apiHost` is a constant in `lib/core/config.dart` (the PC's LAN IP, e.g. `192.168.1.6`); change it when the PC's IP changes. On the Android emulator use `10.0.2.2` |
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

Development sign-in (created by the API's dev seeder): `admin@dineflow.local` / `DineFlow@123`, or the login ID `admin`.

Debug builds allow plain `http`; **release builds require `https`** (Android's default; iOS App Transport Security).

### DineFlow Demo Credentials — DEVELOPMENT / DEMO ONLY

Debug builds of the sign-in screen show **Login as Admin** / **Login as Manager** buttons (gated by `kDebugMode`, so they never
appear in a release build) that fill the form and sign in through the normal `/auth/login` call:

| Role | Login ID | Email | Password |
| --- | --- | --- | --- |
| Tenant Admin / Owner | `admin` | `admin@dineflow.local` | `DineFlow@123` |
| Manager | `manager` | `demo@dineflow.local` | `Demo@123` |

The API must have `Seed:Enabled` and `Seed:Demo:Enabled` on (both default on in `appsettings.Development.json`); see
[DineFlowAPI/README.md](../DineFlowAPI/README.md#dineflow-demo-credentials--development--demo-only). Change or disable these
before any deployment that is reachable by anyone but you.

## Authentication

- Sign in with email + password (`POST /auth/login`); the API returns a short-lived JWT access token and a rotating refresh token.
- Tokens are kept in the platform keystore via `flutter_secure_storage` (Keychain / EncryptedSharedPreferences), never in plain preferences.
- A `401` triggers **one** shared refresh (`POST /auth/refresh`) and a retry of the failed request; if the refresh fails the user is signed out with a clear message.
- Sign-out revokes the refresh token on the server.
- The tenant is taken from the JWT on the server; the app never sends a tenant id.

## Real-time

`lib/core/services/signalr_service.dart` keeps one [signalr_netcore](https://pub.dev/packages/signalr_netcore) connection for the session: it
connects after sign-in, disconnects on sign-out, reconnects automatically, and checks the connection on app resume (a backgrounded app's socket
may have been suspended by the OS). Orders, the kitchen board and the floor plan update as events arrive — no pull-to-refresh needed, though it
still works. Mirrors [DineFlowWEB](../DineFlowWEB)'s real-time service; see the API's
[docs/ARCHITECTURE.md](../DineFlowAPI/docs/ARCHITECTURE.md#real-time-signalr) for the event list.

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
LIVE_API_URL=http://localhost:5080/api/v1 LIVE_EMAIL=admin@dineflow.local LIVE_PASSWORD='DineFlow@123' \
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
| Android build fails with "Could not close incremental caches" (Windows) | The project and the pub cache are on different drives. `android/gradle.properties` already sets `kotlin.incremental=false`; do not remove it. |

## Environment variables, seed data, migration

- **Environment:** only the two `--dart-define` values above (`API_BASE_URL`, `TENANT_CODE`); nothing else is environment-specific.
- **Seed data / database setup:** none in the app. Use [DineFlowDB](../DineFlowDB/README.md) and the API's development seed
  (`admin@dineflow.local` / `DineFlow@123`); see [DineFlowAPI](../DineFlowAPI/README.md).
- **Running the API and Angular** for a complete environment: the API README (`dotnet run`) and [DineFlowWEB](../DineFlowWEB/README.md) (`npm start`).
- **Migration:** the app keeps only the server address, business code and tokens; a new version simply replaces the old one.

## Documentation

Platform documentation lives with the API: [ARCHITECTURE](../DineFlowAPI/docs/ARCHITECTURE.md), [API](../DineFlowAPI/docs/API.md),
[MULTI_TENANCY](../DineFlowAPI/docs/MULTI_TENANCY.md), [WHITE_LABEL](../DineFlowAPI/docs/WHITE_LABEL.md), [DEPLOYMENT](../DineFlowAPI/docs/DEPLOYMENT.md);
the schema is in [DineFlowDB/DATABASE.md](../DineFlowDB/DATABASE.md). CI (`.github/workflows/ci.yml`) runs `flutter analyze`, `flutter test` and a debug APK build.
