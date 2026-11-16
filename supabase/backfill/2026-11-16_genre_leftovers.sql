-- 古い分類名のまま残っていた2番組を、いまの系統に直す(TestFlight のフィードバック: 「人気番組というカテゴリはおかしい」)。
-- アプリ側でも古い名前を読み替えるが、サイトと集計のために、データも直す。
update show set genre = '寝落ち用' where id = '2c6044df-b572-5f57-97e9-79b12f16ef06' and genre = '寝落ち・睡眠導入';
update show set genre = '雑談'     where id = 'fb07ace1-4cd5-5e1a-bd56-b1f202241624' and genre = '人気番組（一般）';
