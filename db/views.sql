-- run estimates by date and period
CREATE OR REPLACE VIEW run_periods AS
WITH v AS (
  SELECT
    id,
    start_timestamp,
    duration,
    date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') AS start_hour,
    date_part('hour', end_timestamp AT TIME ZONE 'US/Eastern') AS end_hour,
    date_part('minute', end_timestamp AT TIME ZONE 'US/Eastern') AS end_minute
  FROM videos
  WHERE NOT flagged
  AND location_id='UML'
  AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') >= 7
  AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') < 19
),
c AS (
  SELECT video_id, count(*) as n_count, avg(count) as mean_count
  FROM counts
  WHERE NOT FLAGGED
  GROUP BY video_id
),
vpd1 AS (
  SELECT 
    v.id,
    v.start_timestamp AT TIME ZONE 'US/Eastern' as start_timestamp,
    (v.start_timestamp AT TIME ZONE 'US/Eastern')::date AS date,
    v.duration,
    CASE
      WHEN start_hour >= 7  AND start_hour < 11 THEN 1
      WHEN start_hour >= 11 AND start_hour < 15 THEN 2
      WHEN start_hour >= 15 AND start_hour < 19 THEN 3
      ELSE NULL
    END AS period,
    COALESCE(c.n_count, 0) as n_count,
    c.mean_count as mean_count
  FROM v
  LEFT JOIN c ON v.id=c.video_id
  WHERE NOT (v.end_hour != v.start_hour AND v.end_hour IN (7, 11, 15, 19) AND v.end_minute > 0)
  ORDER BY v.start_timestamp
),
pd_r AS (
  SELECT
    date,
    period,
    sum(mean_count) / sum(duration * (n_count > 0)::int) AS r
  FROM vpd1
  GROUP BY date, period
),
vpd2 AS (
  SELECT
    vpd1.*,
    pd_r.r
  FROM vpd1
  LEFT JOIN pd_r ON vpd1.date=pd_r.date AND vpd1.period=pd_r.period
),
pd1 AS (
  SELECT
    date,
    period,
    count(*)::real AS n,
    sum((n_count > 0)::int)::real AS n_count,
    sum(duration)::real AS t,
    COALESCE(sum(mean_count), 0)::real AS sum_y,
    sum(duration * (n_count > 0)::int) AS sum_t,
    CASE
      WHEN sum((n_count > 0)::int) > 0 THEN sum(duration * (n_count > 0)::int) / sum((n_count > 0)::int)
      ELSE 0
    END AS mean_t,
    CASE
      WHEN sum(duration * (n_count > 0)::int) > 0 THEN sum(mean_count) / sum(duration * (n_count > 0)::int)
      ELSE 0
    END AS r,
    CASE 
      WHEN sum(duration * (n_count > 0)::int) > 0 THEN sum(mean_count) / sum(duration * (n_count > 0)::int) * sum(duration)
      ELSE 0
    END AS y,
    CASE
      WHEN (sum((n_count > 0)::int) - 1) > 0 THEN sum((mean_count - r * duration) ^ 2) / (sum((n_count > 0)::int) - 1)
      ELSE 0
    END AS se2
  FROM vpd2
  GROUP BY date, period
)
SELECT
  to_char(date, 'YYYY-MM-DD') AS date,
  period,
  n,
  n_count,
  t,
  sum_y,
  sum_t,
  mean_t,
  r,
  y,
  se2,
  CASE
   WHEN (pd1.n * pd1.n_count) > 0 THEN (pd1.t / pd1.mean_t) ^ 2 * (pd1.n - pd1.n_count) / (pd1.n * pd1.n_count) * pd1.se2
   ELSE 0
  END AS var_y,
  pd1.n_count - 1 AS df,
  CASE
    WHEN pd1.n_count > 0 THEN pd1.n * (pd1.n - pd1.n_count)::real / pd1.n_count
    ELSE 0
  END AS a
FROM pd1
ORDER BY date, period;


-- run estimates by date
CREATE OR REPLACE VIEW run_daily AS
WITH d1 AS (
  SELECT
    date,
    sum(n) AS n,
    sum(n_count) AS n_count,
    sum(t) AS t,
    sum(sum_y) AS sum_y,
    sum(sum_t) AS sum_t,
    sum(y) AS y,
    sum(var_y) AS var_y,
    sum(a * se2) AS df_num,
    sum(CASE WHEN n_count > 1 THEN (a * se2) ^ 2 / (n_count - 1) ELSE 0 END) AS df_den
  FROM run_periods
  GROUP BY date
)
SELECT
  date,
  n,
  n_count,
  t,
  sum_y,
  sum_t,
  y,
  var_y,
  df_num,
  df_den,
  sqrt(var_y) AS se_y,
  ROUND(CASE WHEN df_den > 0 THEN df_num ^ 2 / df_den ELSE 0 END) AS df
FROM d1
ORDER BY date;

-- hourly sensor readings
CREATE OR REPLACE VIEW sensor_hourly AS
SELECT
  date_trunc('hour', timestamp) AS timestamp,
  avg(temperature_degc) AS temperature_degc,
  avg(turbidity_ntu) AS turbidity_ntu,
  avg(specificconductance_us_cm) AS specificconductance_us_cm,
  avg(chlorophyll_rfu) AS chlorophyll_rfu,
  avg(odo_mg_l) AS odo_mg_l
FROM sensor
WHERE location_id='UML'
GROUP BY date_trunc('hour', timestamp)
ORDER BY date_trunc('hour', timestamp);

-- users stats and rank
CREATE OR REPLACE VIEW users_stats AS
WITH cv AS (
  SELECT
    counts.users_uid AS users_uid,
    COALESCE(COUNT(counts.count), 0)::int AS n_count,
    COALESCE(SUM(counts.count), 0)::int AS sum_count
  FROM counts
  LEFT JOIN videos ON counts.video_id = videos.id
  WHERE
    NOT counts.flagged AND
    NOT videos.flagged AND
    counts.users_uid IS NOT NULL
  GROUP BY counts.users_uid
),
ucv AS (
  SELECT
    users.uid AS uid,
    users.username AS username,
    users.created_at AS created_at,
    COALESCE(cv.n_count, 0)::int AS n_count,
    COALESCE(cv.sum_count, 0)::int AS sum_count
  FROM users
  LEFT JOIN cv ON users.uid = cv.users_uid
)
SELECT
  uid,
  username,
  created_at,
  n_count,
  sum_count,
  (RANK() OVER (ORDER BY n_count DESC))::int AS rank
FROM ucv
ORDER BY rank, username;

-- random video (exponential distribution)
CREATE OR REPLACE VIEW random_video AS
WITH v1 AS (
  SELECT
    id,
    extract(epoch FROM (current_timestamp - start_timestamp)) / 86400 AS days_ago
  FROM videos
  WHERE
    NOT flagged
    AND location_id='UML'
    AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') >= 7
    AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') < 19
    AND (start_timestamp AT TIME ZONE 'US/Eastern')::date >= '2018-04-27'
), v2 AS (
  SELECT
    v1.*,
    1 - exp(-1 * v1.days_ago / 15) AS p
  FROM v1
), v3 AS (
  SELECT
    v2.id,
    v2.days_ago,
    (p - min(p) OVER ()) / (max(p) OVER () - min(p) OVER ()) AS p
  FROM v2
), r AS (
  SELECT
    random() AS r
), v4 AS (
  SELECT
    v3.*,
    max(p) OVER () as max_p,
    min(p) OVER () as min_p,
    r.r
  FROM v3, r
), v5 AS (
  SELECT
    v4.id,
    v4.p,
    v4.r,
    v4.max_p,
    v4.min_p
  FROM v4
  WHERE p < r
  ORDER BY p DESC
  LIMIT 1
)
SELECT
  v5.p,
  v5.r,
  v5.max_p,
  v5.min_p,
  videos.*
FROM v5
LEFT JOIN videos ON v5.id = videos.id;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO myrwa_www;