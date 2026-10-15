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
4. API host defaults to **https://kapanservice.com**. To override for local/staging: **long-press the logo** on Login, or **long-press the display name** on Account (Developer section appears).
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
| POST/DELETE | `/api/mobile/devices` | register / unregister APNs device token |

## Features in this tree

- Login (Bearer token, restore session) + confirm sign-out
- Brand UI tokens (`KapanTheme`) matching kapanservice.com (orange / blue / light canvas)
- Configurable API base URL (prod default; hidden long-press controls; changing host clears session)
- Jobs list: Today / Upcoming / Done; pull-to-refresh; loading / empty / retry
- Job detail: notes, call, Apple Maps, payment, assign, field status
- Admin: assign / transfer / unassign plumber sheet (Plumbers tab)
- Plumber + admin: Slide to start → Arrived → Complete (GPS only on plumber after successful status)
- Location sharing while En route (throttled posts; approach SMS feedback; 401 → sign out)
- Chat → outbound SMS; Message + Call stay for **1 hour** after completed, then hide
- Full phone / email / street visible as soon as the job is assigned (no mask-until-start)
- APNs: permission + device token → `/api/mobile/devices`; tap notification opens job when `bookingId` present
- Admin Plumbers tab: list + add (temporary password once)
- Info.plist location purpose strings + remote-notification background mode

## Out of MVP (later)

Inbound SMS into chat, live admin map, Android, in-app turn-by-turn nav.

## Transfer

See Project doc `ios-repo-transfer.md` — push this branch tip into `kapan-service-ios-app`.
