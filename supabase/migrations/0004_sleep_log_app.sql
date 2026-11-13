-- アプリの「記録する」(匿名ログイン)から sleep_log に送れるようにする。
-- アプリが送る note / listen_no の列を足し、書いた本人(auth.uid())の行だけを読み書きできるようにする。
-- 前提: Authentication の設定で「Allow anonymous sign-ins」をオンにしておく。

alter table sleep_log add column if not exists note text;
alter table sleep_log add column if not exists listen_no int not null default 1;
alter table sleep_log add column if not exists user_id uuid default auth.uid();
create index if not exists sleep_log_user_idx on sleep_log(user_id);

drop policy if exists sleep_log_own_select on sleep_log;
create policy sleep_log_own_select on sleep_log for select to authenticated using (user_id = auth.uid());

drop policy if exists sleep_log_own_insert on sleep_log;
create policy sleep_log_own_insert on sleep_log for insert to authenticated with check (user_id = auth.uid());

drop policy if exists sleep_log_own_update on sleep_log;
create policy sleep_log_own_update on sleep_log for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 削除の policy は作らない。集計(Zランク・みんなの★)はバッチの service_role が全行を読んで行う。
