-- 番組の分類を2つに分ける(2026-11-15)。
-- genre  = 画面に出す系統(寝落ち用・朗読・芸人ラジオ・雑談・教養・環境音)。
-- cohort = 番組を集めた目的。解析の比較にだけ使い、画面には出さない。
--   core(寝落ち・睡眠導入、朗読、芸人ラジオ、雑談、環境音)/ popular(人気番組の一般枠)
--   control(比較用を含む教養)/ benchmark_en(海外の寝落ち番組の基準)
alter table show add column if not exists cohort text not null default 'core'
  check (cohort in ('core','popular','control','benchmark_en'));
