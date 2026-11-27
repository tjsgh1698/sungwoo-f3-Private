-- Supabase SQL Editor에 그대로 붙여넣고 Run
create table if not exists machines_live (
  no int primary key, ton int, status text, part text, mold text, cav int,
  std_ct numeric, ct numeric, target int, prod int, ng int, worker text, alarm text,
  since timestamptz, updated_at timestamptz default now()
);
create table if not exists condition_changes (
  id bigserial primary key, no int not null, param text not null, unit text,
  from_v numeric, to_v numeric, worker text, reason text, status text default '정상',
  memo text, part text, mold text, created_at timestamptz default now(),
  created_by uuid default auth.uid()
);
alter table machines_live enable row level security;
alter table condition_changes enable row level security;
-- 로그인한 사람: 설비 현황 읽기만, 조건변경은 읽기+등록만 (수정·삭제 불가)
create policy "read live" on machines_live for select to authenticated using (true);
create policy "read changes" on condition_changes for select to authenticated using (true);
create policy "add changes" on condition_changes for insert to authenticated with check (true);
-- machines_live 쓰기는 회사 PC 업로더(service_role 키)만 가능 (RLS 우회)

-- 2026-11-25: 로그인 없이 누구나 보기·등록 (수정·삭제는 여전히 불가)
create policy "anon read live" on machines_live for select to anon using (true);
create policy "anon read changes" on condition_changes for select to anon using (true);
create policy "anon add changes" on condition_changes for insert to anon with check (true);
-- 새 Supabase 프로젝트는 테이블 권한이 자동으로 안 붙음
grant select on public.machines_live to anon, authenticated;
grant select, insert on public.condition_changes to anon, authenticated;
grant usage, select on sequence public.condition_changes_id_seq to anon, authenticated;
grant select, insert, update on public.machines_live to service_role;

-- 사출 조건 일지 (기존 일지 사이트 기록 형식 그대로 data에 보관)
create table if not exists logbook (
  id text primary key default gen_random_uuid()::text,
  machine int, mold text, product text, technician text, status text, reason text,
  recorded_at timestamptz, created_at timestamptz default now(), updated_at timestamptz default now(),
  data jsonb not null);
create index if not exists logbook_recorded on logbook (recorded_at desc);
alter table logbook enable row level security;
create policy "all read logbook" on logbook for select to anon, authenticated using (true);
create policy "all add logbook" on logbook for insert to anon, authenticated with check (true);
grant select, insert on public.logbook to anon, authenticated;
-- 2026-11-27: 조건기록 수정·삭제 — 관리자(사이트 로그인 0121)만 UI 노출. 렌즈/정비와 동일 모델(anon도 DB 허용, 진짜 잠금은 추후 RLS). 사용자 요청: 전체 수정·삭제.
create policy "all upd logbook" on logbook for update to anon, authenticated using (true) with check (true);
create policy "all del logbook" on logbook for delete to anon, authenticated using (true);
grant update, delete on public.logbook to anon, authenticated;

-- 렌즈 한도기준 (기존 일지 사이트에서 15건 이전, 사진은 회전 반영 JPEG data URL)
create table if not exists lens_limits (
  id text primary key, product text, side text, defect text, status text, date text,
  data jsonb not null, img text, created_at timestamptz default now(), updated_at timestamptz default now());
alter table lens_limits enable row level security;
create policy "all read lens" on lens_limits for select to anon, authenticated using (true);
create policy "all add lens" on lens_limits for insert to anon, authenticated with check (true);
grant select, insert on public.lens_limits to anon, authenticated;
-- 2026-11-27: 렌즈 한도기준 수정·삭제 — 렌즈 PIN(사이트 UI 잠금)으로 보호. anon도 수정/삭제 허용(정비 이력과 동일 모델). 사용자 요청.
drop policy if exists "auth upd lens" on lens_limits;
drop policy if exists "auth del lens" on lens_limits;
create policy "all upd lens" on lens_limits for update to anon, authenticated using (true) with check (true);
create policy "all del lens" on lens_limits for delete to anon, authenticated using (true);
grant update, delete on public.lens_limits to anon, authenticated;

-- 정비 이력 (흡착패드 교체·금형 세척 등, 기사 입력)
create table if not exists maintenance (
  id text primary key, machine int, mold text, kind text, at timestamptz,
  worker text, note text, data jsonb, created_at timestamptz default now());
create index if not exists maintenance_m on maintenance (machine, at desc);
alter table maintenance enable row level security;
create policy "all read maint" on maintenance for select to anon, authenticated using (true);
create policy "all add maint" on maintenance for insert to anon, authenticated with check (true);
create policy "all del maint" on maintenance for delete to anon, authenticated using (true);
grant select, insert, delete on public.maintenance to anon, authenticated;

-- 제품 사진 (MES TB_BASE_FILE FILE_GBN='ITEM', FILE_ID=품번). 회사 PC가 품목당 1회 업로드
alter table machines_live add column if not exists item_code text;
create table if not exists item_photos (
  item_code text primary key, img text, ext text, updated_at timestamptz default now());
alter table item_photos enable row level security;
create policy "all read itemph" on item_photos for select to anon, authenticated using (true);
create policy "all add itemph" on item_photos for insert to anon, authenticated with check (true);
create policy "all upd itemph" on item_photos for update to anon, authenticated using (true) with check (true);
grant select, insert, update on public.item_photos to anon, authenticated;

-- 2026-11-27: 생산 이력(기간별 생산·불량). PC 업로더가 MES TB_PROD_RESULT 최근 N일치를 10분마다 upsert.
-- 목적: 각 조건기록이 돌아간 기간의 실제 불량률을 계산 → 제품(금형)별 최저불량 조건을 '표준'으로 자동 선정.
-- id = machine|item_code|mold|work_date (중복 방지, 재업로드 시 갱신). 숫자 위주라 용량 거의 안 먹음(egress 안전).
create table if not exists prod_history (
  id text primary key,
  machine int, item_code text, mold text, cav int,
  work_date date,
  prod_qty int default 0, bad_qty int default 0,
  start_dtm timestamptz, end_dtm timestamptz,
  updated_at timestamptz default now());
create index if not exists prod_history_md on prod_history (mold, work_date desc);
create index if not exists prod_history_up on prod_history (updated_at desc);
alter table prod_history enable row level security;
create policy "all read prod" on prod_history for select to anon, authenticated using (true);
create policy "all add prod" on prod_history for insert to anon, authenticated with check (true);
create policy "all upd prod" on prod_history for update to anon, authenticated using (true) with check (true);
grant select, insert, update on public.prod_history to anon, authenticated;
grant select, insert, update on public.prod_history to service_role;

-- 2026-11-27: 금형별 표준조건 지정(관리자 확정). logbook.id를 가리켜 "이 기록이 이 금형의 표준".
create table if not exists mold_standard (
  mold text primary key, logbook_id text, product text,
  set_by text, note text, updated_at timestamptz default now());
alter table mold_standard enable row level security;
create policy "all read std" on mold_standard for select to anon, authenticated using (true);
create policy "all add std" on mold_standard for insert to anon, authenticated with check (true);
create policy "all upd std" on mold_standard for update to anon, authenticated using (true) with check (true);
create policy "all del std" on mold_standard for delete to anon, authenticated using (true);
grant select, insert, update, delete on public.mold_standard to anon, authenticated;
