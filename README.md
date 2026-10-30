# VolunteerHQ by Educational Apps Lab

Live V1 volunteer management application. The React application includes organization management, opportunity creation, public registration, secure volunteer QR credentials, event-day attendance, volunteer records, and reporting. Supabase provides authentication, the tenant data model, storage, indexes, grants, RLS policies, and narrow public registration APIs.

Volunteer opportunities support three scheduling models: one-time events, multi-day events with explicit occurrences, and ongoing programs with repeated sign-in/sign-out sessions across a term. The creation wizard adapts its schedule and attendance settings to the selected type.

## Requirements

- Node.js 20.19+
- pnpm 10+
- Docker-compatible runtime for local Supabase
- HTTPS in production (required for camera access)

## Local setup

```bash
pnpm install
cp .env.example .env.local
pnpm dev
```

The application requires valid Supabase variables. Add the project URL and **publishable** key from Supabase's Connect dialog to enable authentication. Never place a secret/service-role key in a `VITE_` variable.

## Supabase

```bash
pnpm exec supabase start
pnpm exec supabase db reset
pnpm exec supabase test db
pnpm exec supabase gen types typescript --local > src/lib/database.types.ts
```

The baseline migration creates all V1 tables and enables RLS on every public table. Anonymous users can read only public event configuration and invoke `register_for_event`; they cannot query volunteer or registration tables. The registration function returns a one-time opaque token while storing only its SHA-256 hash. Authenticated tenant access is resolved from `organization_members`, never user-editable metadata.

Before production, run Supabase database advisors, review all policies against the final permission matrix, configure CAPTCHA/rate limiting for public registration, and test the full RLS suite against two seeded tenants. The local stack is development-only.

The `event-logos` bucket is public for event branding; uploads are restricted by organization membership and path. Generated private documents should use a separate private bucket and short-lived signed URLs when that integration is added.

## Email

The Edge Function at `supabase/functions/send-email` is the provider boundary and returns a clear unconfigured response. Set `EMAIL_PROVIDER`, `EMAIL_API_KEY`, and `EMAIL_FROM` as server-side Edge Function secrets. Implement the chosen provider adapter, update `communications` only after the provider response, and preserve failures for retry. No paid provider is selected by default.

## Documents

The frontend includes document eligibility and preview surfaces. For production PDF generation, implement a server-side function that uses finalized `service_awards`, versions output in `documents`, uploads to the private bucket, and records partial failures. Never trust browser-supplied awarded hours.

## Commands

```bash
pnpm dev        # Vite development server
pnpm test       # business-logic tests
pnpm build      # type-check and production build
pnpm preview    # preview built app
```

## Render deployment

Render is configured as a dashboard-managed static site (no Blueprint). It builds with `pnpm install --frozen-lockfile && pnpm build`, publishes `dist`, and rewrites routes to `index.html`. Set `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_APP_URL` in Render. Apply database migrations separately; never ship database passwords or service-role keys to the browser bundle.

## Important production checks

- Configure the production domain in Supabase Auth redirect URLs.
- Test registration, same-email duplicate detection, event capacity, wrong-event QR, and the 60-second scan guard.
- Verify multiple attendance sessions and timezone display.
- Ensure finalized events are immutable except through an authorized, reasoned reopen function.
- Add provider-backed document rendering/email and camera scanning before enabling those integration surfaces.
- Exercise keyboard, screen-reader, reduced-motion, phone, tablet, and kiosk flows.

© 2026 Educational Apps Lab. All rights reserved.
