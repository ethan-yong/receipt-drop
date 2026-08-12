-- Cache for Google Places photos of a venue, keyed by google_place_id and
-- shared across every user who visits that place — not a per-user table.
-- Populated only by the places-proxy Edge Function's `place_photos` mode
-- (service role, bypasses RLS), which re-hosts fetched Places photos into
-- the `place-photos` Storage bucket below so repeat sheet-opens for the same
-- place never re-hit Google's (billed) Photo Media endpoint. See
-- pending-tasks.md's existing Places-API cost-consciousness note.
create table public.place_photos_cache (
  google_place_id text primary key
    constraint place_photos_cache_google_place_id_not_blank
    check (btrim(google_place_id) <> ''),
  photo_urls text[] not null,
  fetched_at timestamptz not null default now()
);

-- Global cache table is server-only, same zero-policy pattern as
-- merchant_locations (20260724020000_merchant_intelligence_foundation.sql).
alter table public.place_photos_cache enable row level security;
revoke all on table public.place_photos_cache from anon, authenticated;

insert into storage.buckets (id, name, public)
values ('place-photos', 'place-photos', true)
on conflict (id) do nothing;

-- No insert/update/delete policies: only the places-proxy Edge Function
-- (service role, bypasses RLS) ever writes here — mirrors avatars_public_read
-- in 20260804000000_profile_setup.sql, minus the user-scoped write policies
-- since there's no client-side upload path for place photos.
create policy "place_photos_public_read"
on storage.objects for select to anon, authenticated
using (bucket_id = 'place-photos');
