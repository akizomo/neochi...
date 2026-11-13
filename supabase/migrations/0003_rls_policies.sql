-- アプリ(anon key)から安全に使うための設定。
-- 番組・回・解析は「誰でも読めるが、書けない」。寝落ちログは「本人だけが読み書きできる」。
-- 解析パイプラインが使う service_role key は RLS を無視するので、書き込みはこれまで通り動く。
-- 前提: ダッシュボードで Authentication > Sign In / Providers > Anonymous sign-ins を有効にする。

alter table show enable row level security;
alter table episode enable row level security;
alter table analysis enable row level security;
alter table sleep_log enable row level security;

-- 公開データ: 読み取りのみ。
drop policy if exists show_read on show;
create policy show_read on show for select to anon, authenticated using (true);

drop policy if exists episode_read on episode;
create policy episode_read on episode for select to anon, authenticated using (true);

drop policy if exists analysis_read on analysis;
create policy analysis_read on analysis for select to anon, authenticated using (true);

-- 寝落ちログ: 端末ごと(匿名サインインのユーザー)に分ける。
alter table sleep_log
  add column if not exists user_id uuid default auth.uid() references auth.users(id) on delete cascade;
create index if not exists sleep_log_user_idx on sleep_log(user_id);

drop policy if exists sleep_log_select_own on sleep_log;
create policy sleep_log_select_own on sleep_log for select to authenticated
  using (user_id = auth.uid());

drop policy if exists sleep_log_insert_own on sleep_log;
create policy sleep_log_insert_own on sleep_log for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists sleep_log_update_own on sleep_log;
create policy sleep_log_update_own on sleep_log for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists sleep_log_delete_own on sleep_log;
create policy sleep_log_delete_own on sleep_log for delete to authenticated
  using (user_id = auth.uid());
