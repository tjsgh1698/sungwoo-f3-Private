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
