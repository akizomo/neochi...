-- 番組ごとの「寝落ちの実績」(みんなの実測の集計)。アプリの番組の詳細で見せる。
-- 実測(source='watch')の、1回目に聴いた記録(listen_no=1)だけで数える。
-- sleep_log は RLS で本人の行しか読めないので、集計だけを返す view を作る。
-- view は所有者の権限で動き、RLS を通る。返すのは集計値(件数・分)だけで、個々の記録や user_id は出さない。

create or replace view show_stats as
select
  e.show_id,
  count(*)::int                                        as n,
  round(avg(l.latency_min))::int                       as avg_min,
  min(l.latency_min)::int                              as min_min,
  max(l.latency_min)::int                              as max_min,
  (count(*) filter (where l.latency_min < 30))::int    as under30
from sleep_log l
join episode e on e.id = l.episode_id
where l.source = 'watch' and l.listen_no = 1 and l.latency_min is not null
group by e.show_id;

revoke all on show_stats from anon, authenticated;
grant select on show_stats to anon, authenticated;
