-- 삼슐랭 가이드 · Supabase 저장소 v1 (2026-10-06)
-- 표 2개: restaurants(사용자가 등록한 식당), events(추천·방문 팁)
-- 샘플 가상 식당 58곳은 앱 안에 들어 있어서 여기엔 없어요.
-- 규칙: 누구나 읽기·추가만 가능, 수정·삭제는 불가. 시각은 서버가 정해요.
-- 여러 번 실행해도 안전해요.

-- 1) 식당 표
create table if not exists public.restaurants (
  id             text primary key default ('r-' || replace(gen_random_uuid()::text, '-', '')),
  region_id      text not null check (region_id in ('DEMO_YONGSAN', 'DEMO_YANGPYEONG_A', 'DEMO_YEOUIDO')),
  name           text not null check (char_length(btrim(name)) between 1 and 30),
  category_label text check (char_length(category_label) <= 20),
  address        text check (char_length(address) <= 100),
  time_slots     text not null check (time_slots ~ '^(LUNCH|DINNER|LATE)(,(LUNCH|DINNER|LATE))*$'),
  max_party      int  not null check (max_party in (1, 2, 4, 6, 7)),
  price_band     text not null check (price_band in ('B0', 'B1', 'B2', 'B3')),
  menu           text check (char_length(menu) <= 30),
  tags           text check (tags ~ '^((FAST|SOLO|GROUP|DINING|TAKEOUT|BOOKING)(,(FAST|SOLO|GROUP|DINING|TAKEOUT|BOOKING))*)?$'),
  tip            text check (char_length(tip) <= 100),
  provider       text check (provider = 'kakao'),
  place_id       text check (char_length(place_id) <= 40),
  map_link       text check (map_link like 'https://place.map.kakao.com/%' or map_link like 'http://place.map.kakao.com/%'),
  lat            double precision,
  lng            double precision,
  created_by     text not null check (char_length(created_by) between 8 and 80),
  created_at     timestamptz not null default now()
);
-- 같은 지역에 같은 카카오 장소는 한 번만 등록
create unique index if not exists restaurants_place_once
  on public.restaurants (region_id, provider, place_id) where place_id is not null;

-- 2) 추천·방문 팁 표
create table if not exists public.events (
  id            text primary key default ('e-' || replace(gen_random_uuid()::text, '-', '')),
  restaurant_id text not null check (char_length(restaurant_id) <= 60),
  type          text not null check (type in ('rec', 'tip')),
  user_id       text not null check (char_length(user_id) between 8 and 80),
  alias         text check (char_length(alias) <= 20),
  body          text,
  day_kst       text,
  created_at    timestamptz not null default now(),
  check ((type = 'rec' and body is null) or (type = 'tip' and char_length(btrim(body)) between 1 and 200))
);
-- 같은 사람·같은 식당·같은 날(KST) 추천은 1회
create unique index if not exists events_rec_once_per_day
  on public.events (restaurant_id, user_id, day_kst) where type = 'rec';
create index if not exists events_restaurant_idx on public.events (restaurant_id, created_at desc);
create index if not exists events_recent_rec_idx on public.events (created_at) where type = 'rec';

-- 3) 시각은 서버가 정하기 (휴대폰 시계를 바꿔도 조작 불가)
create or replace function public.set_server_time() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.created_at := now();
  if tg_table_name = 'events' then
    new.day_kst := to_char(now() at time zone 'Asia/Seoul', 'YYYYMMDD');
  end if;
  return new;
end $$;

drop trigger if exists restaurants_server_time on public.restaurants;
create trigger restaurants_server_time before insert on public.restaurants
  for each row execute function public.set_server_time();
drop trigger if exists events_server_time on public.events;
create trigger events_server_time before insert on public.events
  for each row execute function public.set_server_time();

-- 4) 식당별 누적 추천 수·방문 팁 수 (앱이 한 번에 불러가는 요약표)
create or replace view public.event_counts with (security_invoker = true) as
  select restaurant_id,
         count(*) filter (where type = 'rec') as rec_total,
         count(*) filter (where type = 'tip') as tip_total
  from public.events
  group by restaurant_id;

-- 5) 권한: 읽기·추가만 허용
alter table public.restaurants enable row level security;
alter table public.events      enable row level security;

drop policy if exists "read_all"   on public.restaurants;
drop policy if exists "insert_all" on public.restaurants;
drop policy if exists "read_all"   on public.events;
drop policy if exists "insert_all" on public.events;
create policy "read_all"   on public.restaurants for select to anon, authenticated using (true);
create policy "insert_all" on public.restaurants for insert to anon, authenticated with check (true);
create policy "read_all"   on public.events      for select to anon, authenticated using (true);
create policy "insert_all" on public.events      for insert to anon, authenticated with check (true);

revoke update, delete, truncate on public.restaurants, public.events from anon, authenticated;
grant select, insert on public.restaurants, public.events to anon, authenticated;
grant select on public.event_counts to anon, authenticated;

-- 6) 대표 사진 (2026-10-07 추가, 팀 회의 확정) — 여러 번 실행해도 안전해요.
--    사진 파일은 Storage 버킷 restaurant-photos 에, 식당 표에는 저장 경로만 넣어요.
--    누구나 보기·올리기만 가능, 덮어쓰기·삭제는 불가 (식당 표와 같은 원칙).
alter table public.restaurants add column if not exists photo_path text;
alter table public.restaurants drop constraint if exists restaurants_photo_path_check;
alter table public.restaurants add constraint restaurants_photo_path_check
  check (photo_path ~ '^(DEMO_YONGSAN|DEMO_YANGPYEONG_A|DEMO_YEOUIDO)/[0-9a-f-]{36}\.jpg$');

-- 공개 버킷: 사진 주소로 바로 볼 수 있음. 2MB 이하 JPEG만
-- 앱이 올리기 전에 줄여서 사진 1장당 두 파일: 큰 사진 <uuid>.jpg(보통 150KB 안팎) + 썸네일 <uuid>_t.jpg(20KB 안팎)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('restaurant-photos', 'restaurant-photos', true, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "photos_insert" on storage.objects;
create policy "photos_insert" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'restaurant-photos'
              and name ~ '^(DEMO_YONGSAN|DEMO_YANGPYEONG_A|DEMO_YEOUIDO)/[0-9a-f-]{36}(_t)?\.jpg$');

-- 7) 지역 3곳 + 지역 검증 (2026-10-07 추가) — 여러 번 실행해도 안전해요.
--    지역: DEMO_YONGSAN 용산·신용산 / DEMO_YANGPYEONG_A 양평 블룸비스타(기존 양평 A 현장 자리) / DEMO_YEOUIDO 여의도
--    검증: 좌표가 있는 식당(카카오에서 고른 곳)은 지역 기준점 반경 안이어야 등록돼요. 좌표가 없으면(직접 입력) 통과.
--    기준점·반경은 앱(index.html BASE_PT)과 같아요. 바꿀 때는 두 곳을 함께 바꿔요.
alter table public.restaurants drop constraint if exists restaurants_region_id_check;
alter table public.restaurants add constraint restaurants_region_id_check
  check (region_id in ('DEMO_YONGSAN', 'DEMO_YANGPYEONG_A', 'DEMO_YEOUIDO'));

create or replace function public.region_ok(rg text, la double precision, ln double precision)
returns boolean language sql immutable set search_path = '' as $$
  with base(lat0, lng0, radius) as (
    select v.lat0::float8, v.lng0::float8, v.radius::float8 from (values
      ('DEMO_YONGSAN',      37.52879, 126.96867, 2000),
      ('DEMO_YANGPYEONG_A', 37.50037, 127.42192, 5000),
      ('DEMO_YEOUIDO',    37.52178, 126.92440, 1500)
    ) v(id, lat0, lng0, radius) where v.id = rg
  )
  select coalesce((
    select 2 * 6371000 * asin(sqrt(
             power(sin(radians(la - lat0) / 2), 2)
           + cos(radians(lat0)) * cos(radians(la)) * power(sin(radians(ln - lng0) / 2), 2)
           )) <= radius
    from base), false)
$$;

alter table public.restaurants drop constraint if exists restaurants_in_region;
-- not valid: 이미 등록된 식당은 검사하지 않고, 앞으로 등록되는 식당만 검사해요
alter table public.restaurants add constraint restaurants_in_region
  check (lat is null or lng is null or public.region_ok(region_id, lat, lng)) not valid;
