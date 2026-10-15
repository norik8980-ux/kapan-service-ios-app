# Kapan Service Plumbers

SwiftUI iOS field app for Kapan Plumbing Service (**Admin / dispatch** + **plumbers**).

**Stack:** SwiftUI, iOS 17+  
**API:** `https://kapanservice.com/api/mobile/*` (same Neon DB via website API only)  
**Decisions:** SwiftUI, iOS-only MVP, approach SMS at **3 miles**, locale from booking, start with **2 plumbers** + add-more UI.

> Parked on website repo branch `cursor/ios-scaffold-transfer` until transferred to [`norik8980-ux/kapan-service-ios-app`](https://github.com/norik8980-ux/kapan-service-ios-app). **Do not merge into website `main`.**

## Open in Xcode

1. Open `KapanServicePlumbers.xcodeproj` in Xcode 15+
2. Select your Development Team (Signing)
3. Select a simulator or device
4. API host defaults to **https://kapanservice.com** — override under **Account → Change API base URL** (or on the login screen) for local/staging
5. Run (⌘R)

Requires an **Apple Developer** account for device / TestFlight builds.

## Mobile API (must be deployed)

| Method | Path | Role |
| --- | --- | --- |
| POST | `/api/mobile/auth/login` | admin, plumber |
| GET | `/api/mobile/auth/me` | session |
| GET | `/api/mobile/bookings?tab=today\|upcoming\|completed` | admin: all; plumber: assigned |
| GET/PATCH | `/api/mobile/bookings/:id` | status: `en_route` / `arrived` / `completed` |
| PATCH | `/api/mobile/bookings/:id/assign` | admin — `{ "plumberId": "…" \| null }` |
| POST | `/api/mobile/bookings/:id/location` | GPS while en_route → approach SMS @ 3 mi |
| GET/POST | `/api/mobile/bookings/:id/messages` | chat → outbound Twilio SMS |
| GET/POST | `/api/mobile/plumbers` | admin — list / add plumber |

## Features in this tree

- Login (Bearer token, restore session) + confirm sign-out
- Configurable API base URL (prod default; easy local override; changing host clears session)
- Jobs list: Today / Upcoming / Done; role-aware titles / copy; pull-to-refresh; loading / empty / retry
- Job detail: full customer notes, call, Apple Maps, payment, locale
- Admin: assign / transfer / unassign plumber sheet (Plumbers tab)
- Plumber + admin: On my way → Arrived → Complete (GPS only on plumber after successful status)
- Location sharing while En route (throttled posts; distance + approach SMS feedback; 401 → sign out)
- Chat → outbound SMS (loading / empty / retry)
- Admin Plumbers tab: list + add (temporary password once)
- Info.plist location purpose strings

## Out of MVP (later)

Inbound SMS into chat, live admin map, Android, in-app turn-by-turn nav, APNs push.

## Transfer

See Project doc `ios-repo-transfer.md` — push this branch tip into `kapan-service-ios-app`.
