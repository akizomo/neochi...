-- 文字起こしの保存。定義(採点基準)を変えたときに、音声の取得と文字起こしをやり直さず、判定だけやり直すため。
-- 番組の音声から作った文字なので、非公開にする(アプリにもサイトにも出さない)。
-- バッチが使う service_role キーは RLS をバイパスするので、書き込みと読み出しはそのまま動く。

create table if not exists transcript (
  episode_id uuid primary key references episode(id) on delete cascade,
  lang text not null default 'ja',
  minutes numeric(5,1),                  -- 文字起こしした分数
  spans jsonb not null default '[]',     -- [[開始秒, 終了秒, 文字], ...]。回の頭からの絶対時刻
  version text,                          -- 文字起こしのやり方の版(モデル・範囲)。変わったら取り直す
  created_at timestamptz not null default now()
);

alter table transcript enable row level security;
-- policy は作らない = anon・authenticated からは、読み書きともに拒否。
