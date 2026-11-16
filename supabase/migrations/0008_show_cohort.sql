-- 番組の分類を分ける(2026-11-15)。
-- genre          = 画面に出す系統(寝落ち用・朗読・環境音・コメディ・雑談・教養)。アプリ独自の分け方。
-- apple_category = 配信者が RSS に書いた Apple Podcasts のカテゴリ(「大分類>小分類」)。系統の初期値に使う。
-- cohort         = 番組を集めた目的。解析の比較にだけ使い、画面には出さない。
--   core(寝落ち用・朗読・コメディ・雑談・環境音)/ popular(人気番組の一般枠)
--   control(比較用を含む教養)/ benchmark_en(海外の寝落ち番組の基準)
alter table show add column if not exists cohort text not null default 'core'
  check (cohort in ('core','popular','control','benchmark_en'));
alter table show add column if not exists apple_category text;
