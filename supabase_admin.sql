-- 전모알 사령탑 · 문의 + 관리자 기능 (Supabase SQL Editor에 통째로 붙여넣고 Run)
-- 관리자 비밀번호는 아래 '3490' 부분에서 바꿀 수 있어요. 비밀번호는 서버에만 저장돼요.

create table if not exists mgr_inquiry (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  pid text, kind text, body text, nick text, team text, ver text,
  status text not null default 'new'
);
alter table mgr_inquiry enable row level security;   -- 정책이 없으면 외부에서 직접 읽기/쓰기 불가

create table if not exists mgr_admin (k text primary key, v text);
alter table mgr_admin enable row level security;
insert into mgr_admin (k, v) values ('pw', '3490') on conflict (k) do update set v = excluded.v;

create table if not exists mgr_admin_try (id bigserial primary key, at timestamptz not null default now());
alter table mgr_admin_try enable row level security;

-- 이용자: 문의 접수 (1분에 1건, 하루 10건, 2~500자)
create or replace function mgr_inq_submit(p_pid text, p_kind text, p_body text, p_nick text, p_team text, p_ver text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if p_pid is null or length(coalesce(p_body, '')) < 2 or length(p_body) > 500 then return false; end if;
  if p_kind not in ('bug', 'idea', 'nick', 'etc') then return false; end if;
  if exists (select 1 from mgr_inquiry where pid = p_pid and created_at > now() - interval '60 seconds') then return false; end if;
  if (select count(*) from mgr_inquiry where pid = p_pid and created_at > now() - interval '1 day') >= 10 then return false; end if;
  insert into mgr_inquiry (pid, kind, body, nick, team, ver)
  values (left(p_pid, 80), p_kind, p_body, left(coalesce(p_nick, ''), 20), left(coalesce(p_team, ''), 20), left(coalesce(p_ver, ''), 10));
  return true;
end $$;

-- 비밀번호 확인 (10분 안에 5번 틀리면 잠금)
create or replace function mgr_admin_ok(p_pw text) returns text language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from mgr_admin_try where at > now() - interval '10 minutes') >= 5 then return 'locked'; end if;
  if p_pw is not null and p_pw = (select v from mgr_admin where k = 'pw') then return 'ok'; end if;
  insert into mgr_admin_try default values;
  return 'denied';
end $$;

create or replace function mgr_inq_list(p_pw text) returns jsonb language plpgsql security definer set search_path = public as $$
declare r text; rows jsonb;
begin
  r := mgr_admin_ok(p_pw); if r <> 'ok' then return jsonb_build_object('ok', false, 'err', r); end if;
  select coalesce(jsonb_agg(to_jsonb(t) order by t.id desc), '[]'::jsonb) into rows from (select * from mgr_inquiry order by id desc limit 500) t;
  return jsonb_build_object('ok', true, 'rows', rows);
end $$;

create or replace function mgr_inq_set(p_pw text, p_id bigint, p_status text) returns jsonb language plpgsql security definer set search_path = public as $$
declare r text;
begin
  r := mgr_admin_ok(p_pw); if r <> 'ok' then return jsonb_build_object('ok', false, 'err', r); end if;
  if p_status not in ('new', 'seen', 'done') then return jsonb_build_object('ok', false, 'err', 'bad'); end if;
  update mgr_inquiry set status = p_status where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function mgr_inq_del(p_pw text, p_id bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare r text;
begin
  r := mgr_admin_ok(p_pw); if r <> 'ok' then return jsonb_build_object('ok', false, 'err', r); end if;
  delete from mgr_inquiry where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- 랭킹에서 부적절한 닉네임 삭제
create or replace function mgr_board_del(p_pw text, p_id text) returns jsonb language plpgsql security definer set search_path = public as $$
declare r text;
begin
  r := mgr_admin_ok(p_pw); if r <> 'ok' then return jsonb_build_object('ok', false, 'err', r); end if;
  delete from mgr_board where id::text = p_id;
  return jsonb_build_object('ok', true);
end $$;

grant execute on function mgr_inq_submit(text, text, text, text, text, text) to anon, authenticated;
grant execute on function mgr_inq_list(text) to anon, authenticated;
grant execute on function mgr_inq_set(text, bigint, text) to anon, authenticated;
grant execute on function mgr_inq_del(text, bigint) to anon, authenticated;
grant execute on function mgr_board_del(text, text) to anon, authenticated;
revoke execute on function mgr_admin_ok(text) from anon, authenticated, public;
