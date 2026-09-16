# VolunteerHQ by Educational Apps Lab

Production-oriented V1 foundation for a multi-tenant volunteer management platform. The React application includes management, public registration, event-day, attendance/service-credit, document, reporting, and platform-admin experiences. A Supabase migration provides the tenant data model, indexes, grants, RLS policies, narrow public registration RPC, and append-only audit protection.

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

Without valid Supabase variables the interface runs in a clearly labeled demo workspace using fictional data. Add the project URL and **publishable** key from Supabase's Connect dialog to enable authentication. Never place a secret/service-role key in a `VITE_` variable.

## Supabase

```bash
pnpm exec supabase start
pnpm exec supabase db reset
pnpm exec supabase test db
pnpm exec supabase gen types typescript --local > src/lib/database.types.ts
```

The baseline migration creates all V1 tables and enables RLS on every public table. Anonymous users can read only public event configuration and invoke `register_for_event`; they cannot query volunteer or registration tables. The registration function returns a one-time opaque token while storing only its SHA-256 hash. Authenticated tenant access is resolved from `organization_members`, never user-editable metadata.

Before production, run Supabase database advisors, review all policies against the final permission matrix, configure CAPTCHA/rate limiting for public registration, and test the full RLS suite against two seeded tenants. The local stack is development-only.

### Storage buckets

Create private buckets named `organization-assets` and `generated-documents`. Policies should scope paths as `<organization_id>/...` and check active membership with the same organization predicate used by the database migration. Certificate/letter downloads should use short-lived signed URLs.

### First platform administrator

1. Create the first user through Supabase Auth.
2. Insert its profile with the matching `auth.users.id`.
3. In the SQL editor, update that profile's `platform_role` to `platform_admin` while operating as the project administrator.
4. Sign out and back in, then verify `/platform` access. Do not expose this bootstrap as a public UI action.

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

`render.yaml` defines a static site, SPA rewrite, and security headers. Connect the repository in Render, set `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_APP_URL`, then deploy. Apply database migrations separately with a protected CI/CD environment using `supabase db push`; never ship database passwords or service-role keys to Render's browser bundle.

## Important production checks

- Configure the production domain in Supabase Auth redirect URLs.
- Test registration, same-email duplicate detection, event capacity, wrong-event QR, and the 60-second scan guard.
- Verify multiple attendance sessions and timezone display.
- Ensure finalized events are immutable except through an authorized, reasoned reopen function.
- Add provider-backed document rendering/email and camera scanning before treating those integration surfaces as production-complete.
- Exercise keyboard, screen-reader, reduced-motion, phone, tablet, and kiosk flows.

© 2026 Educational Apps Lab. All rights reserved.
