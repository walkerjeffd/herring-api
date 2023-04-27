-- random row using truncated exponential distribution
-- returns value between 0 and hi, mean approx equal to 1/lambda if lambda is large
CREATE OR REPLACE FUNCTION random_exp(lambda REAL, hi INT) RETURNS integer AS $$
  BEGIN
    RETURN round(- ln(1 - random() * (1 - exp(- hi * lambda))) / lambda);
  END;
$$ LANGUAGE plpgsql;

-- run estimates by date, period
CREATE OR REPLACE FUNCTION f_run_periods(_location_id text, _start_date text, _end_date text)
RETURNS TABLE (
  location_id TEXT,
  date DATE,
  period INT,
  n REAL,
  n_count REAL,
  t REAL,
  sum_y REAL,
  sum_t REAL,
  mean_t REAL,
  r REAL,
  y REAL,
  se2 REAL,
  var_y REAL,
  df REAL,
  a REAL
)
AS $$
  WITH v AS (
    SELECT
      id,
      location_id,
      start_timestamp,
      duration,
      date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') AS start_hour,
      date_part('hour', end_timestamp AT TIME ZONE 'US/Eastern') AS end_hour,
      date_part('minute', end_timestamp AT TIME ZONE 'US/Eastern') AS end_minute
    FROM videos
    WHERE NOT flagged
    AND location_id = _location_id
    AND (start_timestamp AT TIME ZONE 'US/Eastern')::date >= _start_date::date
    AND (end_timestamp AT TIME ZONE 'US/Eastern')::date <= _end_date::date
    AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') >= 7
    AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') < 19
  ),
  c AS (
    SELECT
      c.video_id,
      count(c.count) as n_count,
      avg(c.count) as mean_count
    FROM counts c
    WHERE NOT c.flagged
    AND c.video_id IN (SELECT id FROM v)
    GROUP BY video_id
  ),
  vpd1 AS (
    SELECT
      v.id,
      v.location_id,
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
      location_id,
      date,
      period,
      sum(mean_count) / sum(duration * (n_count > 0)::int) AS r
    FROM vpd1
    GROUP BY location_id, date, period
  ),
  vpd2 AS (
    SELECT
      vpd1.*,
      pd_r.r
    FROM vpd1
    LEFT JOIN pd_r ON vpd1.date=pd_r.date AND vpd1.period=pd_r.period AND vpd1.location_id=pd_r.location_id
  ),
  pd1 AS (
    SELECT
      location_id,
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
    GROUP BY location_id, date, period
  )
  SELECT
    location_id,
    date,
    period,
    n::REAL,
    n_count::REAL,
    t::REAL,
    sum_y::REAL,
    sum_t::REAL,
    mean_t::REAL,
    r::REAL,
    y::REAL,
    se2::REAL,
    (CASE
    WHEN (pd1.n * pd1.n_count) > 0 THEN ((pd1.t / pd1.mean_t) ^ 2 * (pd1.n - pd1.n_count) / (pd1.n * pd1.n_count) * pd1.se2)
    ELSE 0
    END)::REAL AS var_y,
    (pd1.n_count - 1)::REAL AS df,
    (CASE
      WHEN pd1.n_count > 0 THEN pd1.n * (pd1.n - pd1.n_count)::real / pd1.n_count
      ELSE 0
    END)::REAL AS a
  FROM pd1
  ORDER BY location_id, date, period
$$ LANGUAGE SQL;

-- run estimates by date
CREATE OR REPLACE FUNCTION f_run_daily(_location_id text, _start_date text, _end_date text)
RETURNS TABLE (
  location_id TEXT,
  date TEXT,
  n REAL,
  n_count REAL,
  t REAL,
  sum_y REAL,
  sum_t REAL,
  y REAL,
  var_y REAL,
  df_num REAL,
  df_den REAL,
  se_y REAL,
  df INT
)
AS $$
  WITH d1 AS (
    SELECT
      location_id,
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
    FROM f_run_periods(_location_id, _start_date, _end_date)
    GROUP BY location_id, date
  ), d2 AS (
    SELECT
      location_id,
      date,
      n,
      n_count,
      t,
      sum_y,
      sum_t,
      y,
      var_y,
      df_num::REAL,
      df_den::REAL,
      sqrt(var_y)::REAL AS se_y,
      ROUND(CASE WHEN df_den > 0 THEN df_num ^ 2 / df_den ELSE 0 END)::INT AS df
    FROM d1
    ORDER BY location_id, date
  ), d AS (
    SELECT generate_series(_start_date::DATE, _end_date::DATE, '1 day')::DATE AS date
  )
  SELECT
    COALESCE(d2.location_id, _location_id) AS location_id,
    d.date::TEXT AS date,
    COALESCE(d2.n, 0)::REAL AS n,
    COALESCE(d2.n_count, 0)::REAL AS n_count,
    COALESCE(d2.t, 0)::REAL AS t,
    COALESCE(d2.sum_y, 0)::REAL AS sum_y,
    COALESCE(d2.sum_t, 0)::REAL AS sum_t,
    COALESCE(d2.y, 0)::REAL AS y,
    COALESCE(d2.var_y, 0)::REAL AS var_y,
    COALESCE(d2.df_num, 0)::REAL AS df_num,
    COALESCE(d2.df_den, 0)::REAL AS df_den,
    COALESCE(d2.se_y, 0)::REAL AS se_y,
    COALESCE(d2.df, 0)::INT AS df
  FROM d
  LEFT JOIN d2 ON d.date = d2.date
  ORDER BY d.date
$$ LANGUAGE SQL;


-- run estimates by date, period (full day)
CREATE OR REPLACE FUNCTION f_run_periods_full(_location_id text, _start_date text, _end_date text)
RETURNS TABLE (
  location_id TEXT,
  date DATE,
  period INT,
  n REAL,
  n_count REAL,
  t REAL,
  sum_y REAL,
  sum_t REAL,
  mean_t REAL,
  r REAL,
  y REAL,
  se2 REAL,
  var_y REAL,
  df REAL,
  a REAL
)
AS $$
  WITH v AS (
    SELECT
      id,
      location_id,
      start_timestamp,
      duration,
      date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') AS start_hour,
      date_part('hour', end_timestamp AT TIME ZONE 'US/Eastern') AS end_hour,
      date_part('minute', end_timestamp AT TIME ZONE 'US/Eastern') AS end_minute
    FROM videos
    WHERE NOT flagged
    AND location_id = _location_id
    AND (start_timestamp AT TIME ZONE 'US/Eastern')::date >= _start_date::date
    AND (end_timestamp AT TIME ZONE 'US/Eastern')::date <= _end_date::date
  ),
  c AS (
    SELECT
      c.video_id,
      count(c.count) as n_count,
      avg(c.count) as mean_count
    FROM counts c
    WHERE NOT c.flagged
    AND c.video_id IN (SELECT id FROM v)
    GROUP BY video_id
  ),
  vpd1 AS (
    SELECT
      v.id,
      v.location_id,
      v.start_timestamp AT TIME ZONE 'US/Eastern' as start_timestamp,
      (v.start_timestamp AT TIME ZONE 'US/Eastern')::date AS date,
      v.duration,
      CASE
        WHEN start_hour >= 0  AND start_hour < 4 THEN 1
        WHEN start_hour >= 4  AND start_hour < 7 THEN 2
        WHEN start_hour >= 7  AND start_hour < 11 THEN 3
        WHEN start_hour >= 11 AND start_hour < 15 THEN 4
        WHEN start_hour >= 15 AND start_hour < 19 THEN 5
        WHEN start_hour >= 19 THEN 6
        ELSE NULL
      END AS period,
      COALESCE(c.n_count, 0) as n_count,
      c.mean_count as mean_count
    FROM v
    LEFT JOIN c ON v.id=c.video_id
    WHERE NOT (v.end_hour != v.start_hour AND v.end_hour IN (0, 4, 7, 11, 15, 19) AND v.end_minute > 0)
    ORDER BY v.start_timestamp
  ),
  pd_r AS (
    SELECT
      location_id,
      date,
      period,
      sum(mean_count) / sum(duration * (n_count > 0)::int) AS r
    FROM vpd1
    GROUP BY location_id, date, period
  ),
  vpd2 AS (
    SELECT
      vpd1.*,
      pd_r.r
    FROM vpd1
    LEFT JOIN pd_r ON vpd1.date=pd_r.date AND vpd1.period=pd_r.period AND vpd1.location_id=pd_r.location_id
  ),
  pd1 AS (
    SELECT
      location_id,
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
    GROUP BY location_id, date, period
  )
  SELECT
    location_id,
    date,
    period,
    n::REAL,
    n_count::REAL,
    t::REAL,
    sum_y::REAL,
    sum_t::REAL,
    mean_t::REAL,
    r::REAL,
    y::REAL,
    se2::REAL,
    (CASE
    WHEN (pd1.n * pd1.n_count) > 0 THEN ((pd1.t / pd1.mean_t) ^ 2 * (pd1.n - pd1.n_count) / (pd1.n * pd1.n_count) * pd1.se2)
    ELSE 0
    END)::REAL AS var_y,
    (pd1.n_count - 1)::REAL AS df,
    (CASE
      WHEN pd1.n_count > 0 THEN pd1.n * (pd1.n - pd1.n_count)::real / pd1.n_count
      ELSE 0
    END)::REAL AS a
  FROM pd1
  ORDER BY location_id, date, period
$$ LANGUAGE SQL;

-- run estimates by date (full day)
CREATE OR REPLACE FUNCTION f_run_daily_full(_location_id text, _start_date text, _end_date text)
RETURNS TABLE (
  location_id TEXT,
  date TEXT,
  n REAL,
  n_count REAL,
  t REAL,
  sum_y REAL,
  sum_t REAL,
  y REAL,
  var_y REAL,
  df_num REAL,
  df_den REAL,
  se_y REAL,
  df INT
)
AS $$
  WITH d1 AS (
    SELECT
      location_id,
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
    FROM f_run_periods_full(_location_id, _start_date, _end_date)
    GROUP BY location_id, date
  ), d2 AS (
    SELECT
      location_id,
      date,
      n,
      n_count,
      t,
      sum_y,
      sum_t,
      y,
      var_y,
      df_num::REAL,
      df_den::REAL,
      sqrt(var_y)::REAL AS se_y,
      ROUND(CASE WHEN df_den > 0 THEN df_num ^ 2 / df_den ELSE 0 END)::INT AS df
    FROM d1
    ORDER BY location_id, date
  ), d AS (
    SELECT generate_series(_start_date::DATE, _end_date::DATE, '1 day')::DATE AS date
  )
  SELECT
    COALESCE(d2.location_id, _location_id) AS location_id,
    d.date::TEXT AS date,
    COALESCE(d2.n, 0)::REAL AS n,
    COALESCE(d2.n_count, 0)::REAL AS n_count,
    COALESCE(d2.t, 0)::REAL AS t,
    COALESCE(d2.sum_y, 0)::REAL AS sum_y,
    COALESCE(d2.sum_t, 0)::REAL AS sum_t,
    COALESCE(d2.y, 0)::REAL AS y,
    COALESCE(d2.var_y, 0)::REAL AS var_y,
    COALESCE(d2.df_num, 0)::REAL AS df_num,
    COALESCE(d2.df_den, 0)::REAL AS df_den,
    COALESCE(d2.se_y, 0)::REAL AS se_y,
    COALESCE(d2.df, 0)::INT AS df
  FROM d
  LEFT JOIN d2 ON d.date = d2.date
  ORDER BY d.date
$$ LANGUAGE SQL;

-- users stats and rank for given location, video start/end dates
CREATE OR REPLACE FUNCTION f_users_stats(_location_id text, _start_date text, _end_date text)
RETURNS TABLE (
  uid TEXT,
  username TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  n_count INT,
  sum_count INT,
  rank INT
)
AS $$
  WITH cv AS (
    SELECT
      counts.users_uid AS users_uid,
      COALESCE(COUNT(counts.count), 0)::INT AS n_count,
      COALESCE(SUM(counts.count), 0)::INT AS sum_count
    FROM counts
    LEFT JOIN videos ON counts.video_id = videos.id
    WHERE NOT counts.flagged
    AND NOT videos.flagged
    AND videos.location_id = _location_id
    AND (videos.start_timestamp AT TIME ZONE 'US/Eastern')::DATE >= _start_date::DATE
    AND (videos.end_timestamp AT TIME ZONE 'US/Eastern')::DATE <= _end_date::DATE
    AND counts.users_uid IS NOT NULL
    GROUP BY counts.users_uid
  ),
  ucv AS (
    SELECT
      users.uid AS uid,
      users.username AS username,
      users.created_at AS created_at,
      COALESCE(cv.n_count, 0)::INT AS n_count,
      COALESCE(cv.sum_count, 0)::INT AS sum_count
    FROM users
    LEFT JOIN cv ON users.uid = cv.users_uid
  )
  SELECT
    uid,
    username,
    created_at,
    n_count,
    sum_count,
    (RANK() OVER (ORDER BY n_count DESC))::INT AS rank
  FROM ucv
  ORDER BY rank, username
$$ LANGUAGE SQL;

-- hourly sensor readings
CREATE OR REPLACE FUNCTION f_sensor_hourly(_location_id text, _start_date text, _end_date text)
RETURNS TABLE (
  location_id TEXT,
  datetime TIMESTAMP WITH TIME ZONE,
  temperature_degc REAL,
  turbidity_ntu REAL,
  specificconductance_us_cm REAL,
  chlorophyll_rfu REAL,
  odo_mg_l REAL
)
AS $$
  SELECT
    location_id,
    date_trunc('hour', timestamp) AS datetime,
    avg(temperature_degc)::REAL AS temperature_degc,
    avg(turbidity_ntu)::REAL AS turbidity_ntu,
    avg(specificconductance_us_cm)::REAL AS specificconductance_us_cm,
    avg(chlorophyll_rfu)::REAL AS chlorophyll_rfu,
    avg(odo_mg_l)::REAL AS odo_mg_l
  FROM sensor
  WHERE location_id=_location_id
  AND (timestamp AT TIME ZONE 'US/Eastern')::date >= _start_date::date
  AND (timestamp AT TIME ZONE 'US/Eastern')::date <= _end_date::date
  GROUP BY location_id, date_trunc('hour', timestamp)
  ORDER BY date_trunc('hour', timestamp)
$$ LANGUAGE SQL;


-- get set of videos for specific location, date period, hour window, min/max # counts, minimum mean count
CREATE OR REPLACE FUNCTION f_video_set(_location_id TEXT, _start_date TEXT, _end_date TEXT, _start_hour INT, _end_hour INT, _min_count_n INT, _max_count_n INT, _min_count_mean REAL)
RETURNS TABLE(
  id INT,
  created_at TIMESTAMP WITH TIME ZONE,
  url TEXT,
  filename TEXT,
  duration REAL,
  filesize REAL,
  start_timestamp TIMESTAMP WITH TIME ZONE,
  end_timestamp TIMESTAMP WITH TIME ZONE,
  location_id TEXT,
  flagged BOOLEAN,
  url_webm TEXT,
  mp4_converted BOOLEAN,
  count_n INT,
  count_mean REAL
) AS $$
  WITH v AS (
    SELECT *
    FROM videos
    WHERE
      NOT flagged
      AND location_id = _location_id
      AND (start_timestamp AT TIME ZONE 'US/Eastern')::date >= _start_date::date
      AND (end_timestamp AT TIME ZONE 'US/Eastern')::date <= _end_date::date
      AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') >= _start_hour
      AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') <= _end_hour
    ORDER BY start_timestamp DESC
  ), c AS (
    SELECT
      c.video_id,
      count(c.count)::INT AS count_n,
      avg(c.count)::REAL AS count_mean
    FROM counts c
    WHERE NOT flagged
      AND c.video_id IN (SELECT id FROM v)
    GROUP BY c.video_id
  ), vc AS (
    SELECT v.*, COALESCE(c.count_n, 0)::INT AS count_n, COALESCE(c.count_mean, 0)::REAL AS count_mean
    FROM v
    LEFT JOIN c ON v.id = c.video_id
    ORDER BY v.start_timestamp desc
  )
  SELECT *
  FROM vc
  WHERE count_n >= _min_count_n
    AND count_n <= _max_count_n
    AND count_mean >= _min_count_mean
$$ LANGUAGE SQL;

-- get set of candidate videos
CREATE OR REPLACE FUNCTION f_candidate_videos(_location_id TEXT, _start_date TEXT, _end_date TEXT, _start_hour INT, _end_hour INT)
RETURNS TABLE(
  id INT,
  created_at TIMESTAMP WITH TIME ZONE,
  url TEXT,
  filename TEXT,
  duration REAL,
  filesize REAL,
  start_timestamp TIMESTAMP WITH TIME ZONE,
  end_timestamp TIMESTAMP WITH TIME ZONE,
  location_id TEXT,
  flagged BOOLEAN,
  url_webm TEXT,
  mp4_converted BOOLEAN
) AS $$
  SELECT *
  FROM videos
  WHERE
    NOT flagged
    AND location_id = _location_id
    AND (start_timestamp AT TIME ZONE 'US/Eastern')::date >= _start_date::date
    AND (end_timestamp AT TIME ZONE 'US/Eastern')::date <= _end_date::date
    AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') >= _start_hour
    AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') <= _end_hour
  ORDER BY start_timestamp DESC
$$ LANGUAGE SQL;

-- get set of counted candidate videos with > 0 fish
CREATE OR REPLACE FUNCTION f_candidate_videos_counted(_location_id TEXT, _start_date TEXT, _end_date TEXT, _start_hour INT, _end_hour INT)
RETURNS TABLE (
  id INT,
  created_at TIMESTAMP WITH TIME ZONE,
  url TEXT,
  filename TEXT,
  duration REAL,
  filesize REAL,
  start_timestamp TIMESTAMP WITH TIME ZONE,
  end_timestamp TIMESTAMP WITH TIME ZONE,
  location_id TEXT,
  flagged BOOLEAN,
  url_webm TEXT,
  mp4_converted BOOLEAN,
  n_count INT,
  mean_count REAL
) AS $$
  WITH v AS (
    SELECT *
    FROM f_candidate_videos(_location_id, _start_date, _end_date, _start_hour, _end_hour)
  ), c AS (
    SELECT
      c.video_id,
      count(c.count)::INT AS n_count,
      avg(c.count)::REAL AS mean_count
    FROM counts c
    WHERE NOT flagged
      AND c.video_id IN (SELECT id FROM v)
    GROUP BY c.video_id
  )
  SELECT v.*, COALESCE(c.n_count, 0)::INT AS n_count, COALESCE(c.mean_count, 0)::REAL AS mean_count
  FROM v
  LEFT JOIN c ON v.id = c.video_id
  WHERE COALESCE(c.mean_count, 0) > 0
  ORDER BY v.start_timestamp desc
$$ LANGUAGE SQL;

-- get set of candidate videos that have been counted at least once, included flagged counts, regardless of whether there were fish or not
CREATE OR REPLACE FUNCTION f_candidate_videos_counted_any(_location_id TEXT, _start_date TEXT, _end_date TEXT, _start_hour INT, _end_hour INT)
RETURNS TABLE (
  id INT,
  created_at TIMESTAMP WITH TIME ZONE,
  url TEXT,
  filename TEXT,
  duration REAL,
  filesize REAL,
  start_timestamp TIMESTAMP WITH TIME ZONE,
  end_timestamp TIMESTAMP WITH TIME ZONE,
  location_id TEXT,
  flagged BOOLEAN,
  url_webm TEXT,
  mp4_converted BOOLEAN,
  n_count INT,
  mean_count REAL
) AS $$
  WITH v AS (
    SELECT *
    FROM f_candidate_videos(_location_id, _start_date, _end_date, _start_hour, _end_hour)
  ), c AS (
    SELECT
      c.video_id,
      count(c.count)::INT AS n_count,
      avg(c.count)::REAL AS mean_count
    FROM counts c
    WHERE c.video_id IN (SELECT id FROM v)
    GROUP BY c.video_id
  )
  SELECT v.*, COALESCE(c.n_count, 0)::INT AS n_count, COALESCE(c.mean_count, 0)::REAL AS mean_count
  FROM v
  LEFT JOIN c ON v.id = c.video_id
  WHERE n_count > 0
  ORDER BY v.start_timestamp desc
$$ LANGUAGE SQL;

-- random video (exponential distribution)
CREATE OR REPLACE FUNCTION f_random_video_exponential(_location_id text, _start_date text, _end_date text)
RETURNS TABLE (
  p REAL,
  r REAL,
  max_p REAL,
  min_p REAL,
  id INT,
  created_at TIMESTAMP WITH TIME ZONE,
  url TEXT,
  filename TEXT,
  duration REAL,
  filesize REAL,
  start_timestamp TIMESTAMP WITH TIME ZONE,
  end_timestamp TIMESTAMP WITH TIME ZONE,
  location_id TEXT,
  flagged BOOLEAN,
  url_webm TEXT,
  mp4_converted BOOLEAN
)
AS $$
  WITH v1 AS (
    SELECT
      id,
      extract(epoch FROM (current_timestamp - start_timestamp)) / 86400 AS days_ago
    FROM videos
    WHERE
      NOT flagged
      AND location_id=_location_id
      AND (start_timestamp AT TIME ZONE 'US/Eastern')::date >= _start_date::date
      AND (end_timestamp AT TIME ZONE 'US/Eastern')::date <= _end_date::date
      AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') >= 7
      AND date_part('hour', start_timestamp AT TIME ZONE 'US/Eastern') < 19
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
    v5.p::REAL,
    v5.r::REAL,
    v5.max_p::REAL,
    v5.min_p::REAL,
    videos.*
  FROM v5
  LEFT JOIN videos ON v5.id = videos.id;
$$ LANGUAGE SQL;

-- fish status
CREATE OR REPLACE FUNCTION f_fish_status(_location_id TEXT, _start_date TEXT, _end_date TEXT, _start_hour INT, _end_hour INT)
RETURNS TABLE(
  date TEXT,
  count REAL
) AS $$
  WITH v AS (
    SELECT
      id,
      (start_timestamp AT TIME ZONE 'America/New_York')::DATE AS date
    FROM f_candidate_videos(_location_id, _start_date, _end_date, _start_hour, _end_hour)
  ),
  c AS (
    SELECT
      c.video_id,
      count(c.count) AS n_count,
      avg(c.count) AS mean_count
    FROM counts c
    WHERE NOT c.flagged
      AND c.video_id IN (SELECT id FROM v)
    GROUP BY c.video_id
  ),
  vc AS (
    SELECT
      v.id,
      v.date,
      COALESCE(c.mean_count, 0) AS mean_count
    FROM v
    LEFT JOIN c ON v.id = c.video_id
  ),
  vcd AS (
    SELECT
      vc.date,
      sum(vc.mean_count) AS count
    FROM vc
    GROUP BY vc.date
  ),
  d AS (
    SELECT generate_series(_start_date::DATE, _end_date::DATE, '1 day')::DATE as date
  )
  SELECT
    d.date::TEXT AS date,
    COALESCE(vcd.count, 0)::REAL AS count
  FROM d
  LEFT JOIN vcd
  ON d.date = vcd.date
  ORDER BY d.date;
$$ LANGUAGE SQL;

-- video status
CREATE OR REPLACE FUNCTION f_video_status(_location_id TEXT, _start_date TEXT, _end_date TEXT, _start_hour INT, _end_hour INT)
RETURNS TABLE(
  date TEXT,
  n_total INT,
  n_counted INT
) AS $$
  WITH v AS (
    SELECT
      id,
      (start_timestamp AT TIME ZONE 'America/New_York')::DATE AS date
    FROM f_candidate_videos(_location_id, _start_date, _end_date, _start_hour, _end_hour)
  ),
  c AS (
    SELECT
      c.video_id,
      count(c.count) AS n_count,
      avg(c.count) AS mean_count
    FROM counts c
    WHERE NOT c.flagged
      AND c.video_id IN (SELECT id FROM v)
    GROUP BY c.video_id
  ),
  vc AS (
    SELECT
      v.id,
      v.date,
      (COALESCE(c.n_count, 0) > 0)::INT AS counted
    FROM v
    LEFT JOIN c on v.id = c.video_id
  ),
  vcd AS (
    SELECT
      vc.date,
      count(counted) AS n_total,
      sum(counted) AS n_counted
    FROM vc
    GROUP BY vc.date
  ),
  d AS (
    SELECT generate_series(_start_date::DATE, _end_date::DATE, '1 day')::DATE AS date
  )
  SELECT
    d.date::TEXT AS date,
    COALESCE(vcd.n_total::integer, 0) AS n_total,
    COALESCE(vcd.n_counted::integer, 0) AS n_counted
  FROM d
  LEFT JOIN vcd ON d.date = vcd.date
  ORDER BY d.date
$$ LANGUAGE SQL;

-- activity status
CREATE OR REPLACE FUNCTION f_activity_status(_location_id TEXT, _date TEXT)
RETURNS TABLE(
  id INT,
  count_timestamp TIMESTAMP WITH TIME ZONE,
  video_id INT,
  count INT,
  comment TEXT,
  video_start TIMESTAMP WITH TIME ZONE,
  video_end TIMESTAMP WITH TIME ZONE,
  duration REAL,
  url TEXT
) AS $$
  SELECT
    c.id,
    c.created_at as count_timestamp,
    c.video_id,
    c.count,
    c.comment,
    v.start_timestamp as video_start,
    v.end_timestamp as video_end,
    v.duration as duration,
    v.url as url
  FROM counts c
  LEFT JOIN videos v ON c.video_id = v.id
  WHERE NOT c.flagged
    AND NOT v.flagged
    AND v.location_id = _location_id
    AND (c.created_at AT TIME ZONE 'America/New_York')::DATE = _date::DATE
  ORDER BY c.created_at
$$ LANGUAGE SQL;

-- today's activity status
CREATE OR REPLACE FUNCTION f_activity_status_today(_location_id TEXT)
RETURNS TABLE(
  id INT,
  count_timestamp TIMESTAMP WITH TIME ZONE,
  video_id INT,
  count INT,
  comment TEXT,
  video_start TIMESTAMP WITH TIME ZONE,
  video_end TIMESTAMP WITH TIME ZONE,
  duration REAL,
  url TEXT
) AS $$
  SELECT * FROM f_activity_status(_location_id, (current_timestamp AT TIME ZONE 'America/New_York')::DATE::TEXT)
$$ LANGUAGE SQL;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO myrwa_www;
