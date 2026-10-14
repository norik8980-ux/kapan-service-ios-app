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
4. Optionally point `APIClient.baseURL` at a staging host
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
| POST | `/api/mobile/bookings/:id/location` | GPS while assigned/en_route → approach SMS @ 3 mi |
| GET/POST | `/api/mobile/bookings/:id/messages` | chat → outbound Twilio SMS |
| GET/POST | `/api/mobile/plumbers` | admin — list / add plumber |

## Features in this tree

- Login (Bearer token, restore session)
- Jobs list: Today / Upcoming / Done; role-aware titles; status chips
- Job detail: full customer notes, call, Apple Maps, payment, locale
- Admin: assign / transfer / unassign plumber sheet
- Plumber + admin: On my way → Arrived → Complete
- Location sharing while En route (distance + approach SMS feedback)
- Chat → outbound SMS
- Admin Plumbers tab: list + add (temporary password once)
- Info.plist location purpose strings

## Out of MVP (later)

Inbound SMS into chat, live admin map, Android, in-app turn-by-turn nav, APNs push.

## Transfer

See Project doc `ios-repo-transfer.md` — push this branch tip into `kapan-service-ios-app`.
