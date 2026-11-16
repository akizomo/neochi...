-- 本編が始まる位置(冒頭のジングル・告知・広告を飛ばして、静かに始めるため)。古い回は null のまま(アプリは飛ばさない)。

-- 解析した音声での、本編の最初の一言の秒(0〜300)。0 = 冒頭から本編。
-- 再生する音声は広告が差し替わって秒がずれるので、秒は目安。アプリは anchor の一言で、位置を合わせ直す。
alter table analysis add column if not exists content_start_sec int
  check (content_start_sec is null or content_start_sec between 0 and 300);

-- 本編の最初の一言(文字起こしのまま、40字以内)。content_start_sec が 0 のときは null でよい。
alter table analysis add column if not exists content_start_anchor text
  check (content_start_anchor is null or char_length(content_start_anchor) <= 40);

alter table analysis drop constraint if exists content_start_anchor_needed;
alter table analysis add constraint content_start_anchor_needed
  check (content_start_sec is null or content_start_sec = 0 or content_start_anchor is not null);
