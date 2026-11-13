alter table analysis add column if not exists interest_score smallint check (interest_score between 1 and 10);
