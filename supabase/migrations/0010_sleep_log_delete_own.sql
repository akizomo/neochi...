-- 利用者が、自分の記録をアプリから削除できるようにする(ヘルスケアの睡眠データを扱うため。プライバシーポリシーの「削除」)。
-- 消せるのは、書いた本人(auth.uid())の行だけ。集計(Zランク・みんなの★)は、バッチが service_role で行うので影響しない。
drop policy if exists sleep_log_own_delete on sleep_log;
create policy sleep_log_own_delete on sleep_log for delete to authenticated using (user_id = auth.uid());
