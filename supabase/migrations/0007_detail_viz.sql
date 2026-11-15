-- 番組詳細の図のための出力。古い回は null のまま(アプリは、出せる図と箱だけを出す)。

-- 冒頭20分の、1分ごとの起伏の強さ(0〜2、小数1桁)。起伏の山(reasons.moments)はこの山から作る。
alter table analysis add column if not exists calm_per_min numeric(2,1)[]
  check (calm_per_min is null
         or (array_length(calm_per_min, 1) between 1 and 20
             and 0 <= all(calm_per_min) and 2 >= all(calm_per_min)));

-- 内容の要約(2〜3文、120字以内。結末や謎解きの答えは書かない)。
alter table analysis add column if not exists content_summary text
  check (content_summary is null or char_length(content_summary) <= 120);

-- reasons.moments の形: [{min, note, level}]。level は 1 = 少し、2 = 多い(列は増やさない)。

-- 番組の「寝落ちの実績」の点(夜ごとの分数)。show_stats と同じく、実測(watch)の1回目に聴いた記録だけ。
-- sleep_log は RLS で本人の行しか読めないので、view で返す。返すのは日付と分数だけで、user_id・回・時刻は出さない。
-- 日付は日本時間の再生開始日。番組ごとに新しい60件まで。
create or replace view show_sleep_points as
select show_id, night, latency_min
from (
  select
    e.show_id,
    (l.started_at at time zone 'Asia/Tokyo')::date                                   as night,
    l.latency_min::int                                                                as latency_min,
    row_number() over (partition by e.show_id order by l.started_at desc)            as rn
  from sleep_log l
  join episode e on e.id = l.episode_id
  where l.source = 'watch' and l.listen_no = 1 and l.latency_min is not null and l.started_at is not null
) t
where rn <= 60;

revoke all on show_sleep_points from anon, authenticated;
grant select on show_sleep_points to anon, authenticated;
