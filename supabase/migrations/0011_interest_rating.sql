-- みんなの🎯を、3択(interest_vote)から10段階(interest_rating)にする。
-- 10段階は、AIの🎯(analysis.interest_score 1〜10)と同じ意味・同じゾーンの式で★に直す(docs/SCORE.md §2・§4)。
-- interest_vote(-1/0/1)は、10段階の導入前の行のために残す(10段階があれば、そちらだけを使う)。

alter table sleep_log add column if not exists interest_rating int check (interest_rating between 1 and 10);
