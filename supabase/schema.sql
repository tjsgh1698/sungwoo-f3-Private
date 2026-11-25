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
