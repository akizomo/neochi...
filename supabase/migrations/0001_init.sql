-- neochi… 初期スキーマ。要因(analysis)と結果(sleep_log)は別テーブルのまま混ぜない。
create table if not exists show (
  id uuid primary key,
  title text not null,
  publisher text,
  rss_url text not null unique,
  genre text,
  lang text not null default 'ja',
  show_star numeric(2,1),
  z_rank text check (z_rank in ('Z','ZZ','ZZZ')),
  listing_status text not null default 'researching' check (listing_status in ('listed','researching'))
);

create table if not exists episode (
  id uuid primary key,
  show_id uuid not null references show(id) on delete cascade,
  title text,
  audio_url text,
  duration_sec int,
  published_at timestamptz
);
create index if not exists episode_show_idx on episode(show_id);

create table if not exists analysis (
  episode_id uuid primary key references episode(id) on delete cascade,
  input_depth text not null check (input_depth in ('meta','transcript','audio')),
  interest_level text check (interest_level in ('low','mid','high')),
  calm_star numeric(2,1),
  ear_star numeric(2,1),
  total_star numeric(2,1),
  final_star numeric(2,1),
  final_reason text,
  reasons jsonb not null default '{}',
  features jsonb not null default '{}',
  analyzed_at timestamptz not null default now()
);

-- 実測(watch)と自己申告(self)は別々の行で保存する。Zランクは source='watch' だけで集計。
create table if not exists sleep_log (
  id uuid primary key default gen_random_uuid(),
  episode_id uuid not null references episode(id) on delete cascade,
  started_at timestamptz,
  sleep_onset_at timestamptz,
  latency_min int,
  source text not null check (source in ('watch','self')),
  interest_vote int check (interest_vote in (-1,0,1)),
  calm_vote int check (calm_vote between 1 and 5),
  voice_like boolean
);
create index if not exists sleep_log_episode_idx on sleep_log(episode_id);
