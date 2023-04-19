/*
SQLのみのUDFでnDCGを計算する。

参考：
https://web.stanford.edu/class/cs276/19handouts/lecture8-evaluation-1per.pdf
https://www.szdrblog.info/entry/2017/02/24/235539
https://zenn.dev/bilzard/scraps/883f80b4ae3526
*/

CREATE TEMP FUNCTION SLICE_ARRAY(arr ARRAY<FLOAT64>, start INT64, finish INT64)
RETURNS ARRAY<FLOAT64>
AS (
  ARRAY((
    SELECT elem
    FROM UNNEST(arr) AS elem WITH OFFSET AS id
    WHERE id BETWEEN start AND finish
  ))
);


CREATE TEMP FUNCTION DCG(relevance_scores ARRAY<FLOAT64>, k INT64, dcg_type INT64)
-- DCG1 = rel_1 + \sum^{k}_{i=2}\frac{rel_i}{\log_2{i}}
-- DCG2 = \sum^{k}_{i=1}\frac{2^{rel_i}-1}{\log_2{i+1}}
-- DCG2 は適合度が高い文書が正しく上位に出ていることを強調する版
RETURNS FLOAT64 AS (
  (
    SELECT
      CASE
        WHEN dcg_type = 1
          THEN SUM(IF(i = 1, a, a / LOG(i, 2)))
        WHEN dcg_type = 2
          THEN SUM((pow(2, a) - 1) / LOG(i + 1, 2))
        ELSE ERROR('dcg_type は 1 か 2 を与えてください')
      END
    FROM (
      SELECT
        a,
        i + 1 AS i  -- 順位を1始まりにする
      FROM
        UNNEST(SLICE_ARRAY(relevance_scores, 0, k)) AS a WITH OFFSET AS i
    )
  )
);

CREATE TEMP FUNCTION IDEAL_DCG(relevance_scores ARRAY<FLOAT64>, k INT64, dcg_type INT64)
-- 理想の DCG を計算する。正規化するときの分母。適合度順に文書を並べて DCG func の引数にする。
RETURNS FLOAT64 AS (
  DCG(
    ARRAY(
      SELECT r
      FROM (
        SELECT r FROM UNNEST(relevance_scores) AS r
        ORDER BY r DESC
      )
    ),
    k,
    dcg_type
  )
);


CREATE TEMP FUNCTION NDCG(relevance_scores ARRAY<FLOAT64>, k INT64, dcg_type INT64)
RETURNS FLOAT64 AS (
  COALESCE(
    SAFE_DIVIDE(DCG(relevance_scores, k, dcg_type), IDEAL_DCG(relevance_scores, k, dcg_type)),
    0.0
  )
);

WITH example_data AS (
  SELECT [5.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3., 3., 3., 3.] AS relevance_scores, 10 AS k
)

SELECT
  NDCG(relevance_scores, k, 1) AS ndcg1,
  NDCG(relevance_scores, k, 2) AS ndcg2
FROM
  example_data;
