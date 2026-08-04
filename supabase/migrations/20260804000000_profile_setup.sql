-- Profile setup screen (post Google sign-in): username + completion flag,
-- plus a Storage bucket so a real profile photo can back `profiles.avatar_url`.

alter table public.profiles add column if not exists username text;
alter table public.profiles
  add column if not exists profile_setup_complete boolean not null default false;

create unique index if not exists profiles_username_unique_idx
  on public.profiles (lower(username))
  where username is not null;

-- Lets the client check availability without widening the profiles select
-- policy (profiles_select_own only exposes the caller's own row).
create or replace function public.is_username_available(candidate text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles where lower(username) = lower(candidate)
  );
$$;

grant execute on function public.is_username_available(text) to authenticated;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "avatars_insert_own"
on storage.objects for insert to authenticated
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_update_own"
on storage.objects for update to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_delete_own"
on storage.objects for delete to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_public_read"
on storage.objects for select to anon, authenticated
using (bucket_id = 'avatars');
