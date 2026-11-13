-- 行レベルセキュリティ。匿名ログイン(Supabase の Anonymous sign-ins)の端末ごとに、自分の記録だけを読み書きできる。
-- show / episode / analysis は、匿名を含む全員が読み取りだけできる。書き込みは service_role(解析バッチ)だけ。
-- service_role は RLS を通らないので、番組ごとの実績(Zランク)の集計は、全員の sleep_log を読める。

-- ---- アプリの現行の仕様に合わせた列の調整 ------------------------------------
-- 興味はスライダー(0〜100、10刻み)。0001 の -1/0/1 の制約を外して置き換える。
alter table sleep_log drop constraint if exists sleep_log_interest_vote_check;
alter table sleep_log add constraint sleep_log_interest_vote_check
  check (interest_vote is null or (interest_vote between 0 and 100 and interest_vote % 10 = 0));
alter table sleep_log add column if not exists note text;                          -- 任意のメモ
alter table sleep_log add column if not exists listen_no int not null default 1;   -- その回を何回目に聴いたか(実績は1回目だけで集計する)

-- ---- 端末ごとの持ち主 ----------------------------------------------------------
alter table sleep_log add column if not exists user_id uuid default auth.uid();
create index if not exists sleep_log_user_idx on sleep_log(user_id);

-- 再生の記録(端末内の記録を同期するときに使う)。回ごとの再生回数と「いまの番組」の判断に使う。
create table if not exists play_record (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  episode_id uuid not null references episode(id) on delete cascade,
  show_id uuid not null references show(id) on delete cascade,
  played_at timestamptz not null default now()
);
create index if not exists play_record_user_idx on play_record(user_id, played_at desc);

-- ---- RLS を有効にする -----------------------------------------------------------
alter table show enable row level security;
alter table episode enable row level security;
alter table analysis enable row level security;
alter table sleep_log enable row level security;
alter table play_record enable row level security;

-- 解析結果は、匿名を含む全員が読み取りだけ。書き込みのポリシーは作らない(service_role だけが書ける)。
drop policy if exists show_read on show;
create policy show_read on show for select to anon, authenticated using (true);
drop policy if exists episode_read on episode;
create policy episode_read on episode for select to anon, authenticated using (true);
drop policy if exists analysis_read on analysis;
create policy analysis_read on analysis for select to anon, authenticated using (true);

-- 自分の記録だけ。匿名ログインのユーザーは authenticated ロールで、auth.uid() が端末ごとの ID になる。
drop policy if exists sleep_log_own on sleep_log;
create policy sleep_log_own on sleep_log for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists play_record_own on play_record;
create policy play_record_own on play_record for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---- 権限 -------------------------------------------------------------------------
revoke all on show, episode, analysis, sleep_log, play_record from anon, authenticated;
grant select on show, episode, analysis to anon, authenticated;
grant select, insert, update, delete on sleep_log, play_record to authenticated;
