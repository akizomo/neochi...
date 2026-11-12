-- 番組のカバー画像と、元の番組への動線。画像は複製せず、URL だけ持つ。
alter table show add column if not exists artwork_url text;
alter table show add column if not exists link_url text;     -- 配信元の番組のサイト(RSS の channel/link)
alter table show add column if not exists apple_url text;    -- Apple Podcasts のページ(別工程で取得)
alter table episode add column if not exists link_url text;  -- 配信元の回のページ(RSS の item/link)
