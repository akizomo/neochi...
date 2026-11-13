-- 行レベルセキュリティ(RLS)。アプリに埋め込む公開キー(anon)で書き換えられないようにする。
-- バッチが使う service_role キーは RLS をバイパスするので、解析の書き込みはそのまま動く。

alter table show enable row level security;
alter table episode enable row level security;
alter table analysis enable row level security;
alter table sleep_log enable row level security;

-- 番組・回・解析結果は、誰でも読めるが書けない(書き込みの policy を作らない = 拒否)。
drop policy if exists show_read on show;
create policy show_read on show for select to anon, authenticated using (true);

drop policy if exists episode_read on episode;
create policy episode_read on episode for select to anon, authenticated using (true);

drop policy if exists analysis_read on analysis;
create policy analysis_read on analysis for select to anon, authenticated using (true);

-- sleep_log の policy は 0004 で追加する(それまでは、公開キーからは読み書きともにできない)。
