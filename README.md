# Kapan Service Plumbers

SwiftUI iOS field app for Kapan Plumbing Service dispatchers and plumbers.

**Stack:** SwiftUI, iOS 17+  
**API:** `https://kapanservice.com/api/mobile/*` (same Neon DB via website API only)  
**Decisions:** see Project Context — SwiftUI, iOS-only MVP, approach SMS at 3 miles, locale from booking, start with 2 plumbers + add-more.

## Open in Xcode

1. Open `KapanServicePlumbers.xcodeproj` in Xcode 15+
2. Select a simulator or device
3. Update `APIClient.baseURL` if pointing at a staging host
4. Run (⌘R)

Requires an **Apple Developer** account for device / TestFlight builds.

## Features (Phase 1 scaffold)

- Login (admin or plumber) → Bearer token
- Bookings list (today / upcoming / completed)
- Booking detail: notes, call, Apple Maps, status
- Admin: assign plumber, add plumber
- Chat → outbound SMS
- En route location posts (approach SMS handled by API at 3 miles)

## Repo note

Preferred GitHub remote: `norik8980-ux/kapan-field-app` (create empty repo if missing, then):

```bash
git remote add origin https://github.com/norik8980-ux/kapan-field-app.git
git push -u origin main
```
