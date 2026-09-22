# Jaldi

Flutter client for roadside assistance. Feature screens are intentionally kept
independent of the backend foundation in this repository.

## Local setup

1. Install Flutter (Dart 3.11 or newer) and run `flutter pub get`.
2. Copy `.env.example` to `.env` for reference. Do **not** commit secrets.
3. Pass configuration at build/run time (the app reads compile-time values):

```bash
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-anon-or-publishable-key
```

Use only Supabase's publishable/anon key in the mobile app. Never put a
`service_role` key, database password, or other privileged secret in Flutter,
`.env`, source control, or release artifacts. Configure CI secret variables for
the two `dart-define` values.

## Supabase backend

Create a Supabase project with PostGIS enabled, then run
[`supabase/schema.sql`](supabase/schema.sql) in the SQL editor (or use
`supabase db push` with the Supabase CLI). The script creates profiles,
provider onboarding/details and locations, requests, assignments, applications,
emergencies, ratings, indexes, RLS policies, and race-safe
`assign_request`/`accept_request` RPCs.

Authentication uses Supabase Auth. A trigger creates a `profiles` row for each
new user. Realtime can be enabled for `service_requests` and `assignments` in
the Supabase dashboard if live request updates are needed.

## Checks

Run `dart format lib` and `flutter analyze` before submitting client changes.
Validate SQL by running it against a disposable Supabase project or local
Supabase CLI instance; the schema uses PostGIS geography types and generated
columns.
