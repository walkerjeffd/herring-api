suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(lubridate))
suppressPackageStartupMessages(library(RColorBrewer))
suppressPackageStartupMessages(library(gridExtra))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(glue))

theme_set(theme_bw())

updated_at <- paste0("Updated: ", with_tz(now(), "US/Eastern"))

# load config -------------------------------------------------------------

cfg <- read_json("./config.json")

# load data ---------------------------------------------------------------

pg <- src_postgres(
  dbname = cfg$db$database,
  host = cfg$db$host,
  port = cfg$db$port,
  user = cfg$db$user,
  password = cfg$db$password
)

generate_report <- function(site, start_date, end_date, fullDay) {
  fname <- glue("pdf/video-{year(start_date)}-{site}.pdf")
  cat(glue("generating report: {fname}"), "\n")

  yr <- year(ymd(start_date))

  tbl_videos <- pg %>%
    tbl("videos") %>%
    filter(!flagged, location_id == site)  %>%
    collect() %>%
    mutate(
      start_timestamp = with_tz(start_timestamp, tzone = "US/Eastern"),
      end_timestamp = with_tz(end_timestamp, tzone = "US/Eastern"),
      date = as.Date(start_timestamp, tz = "US/Eastern")
    ) %>%
    filter(
      date >= as.Date(start_date),
      date <= as.Date(end_date)
    )

  tbl_counts <- pg %>%
    tbl("counts") %>%
    filter(!flagged) %>%
    collect()

  counts <- tbl_counts %>%
    left_join(select(tbl_videos, id, start_timestamp, date), by = c("video_id" = "id")) %>%
    filter(
      date >= as.Date(start_date),
      date <= as.Date(end_date)
    )

  counts_by_video <- tbl_counts %>%
    group_by(video_id) %>%
    summarise(
      n_count = n(),
      mean_count = mean(count)
    )

  videos <- tbl_videos %>%
    left_join(counts_by_video, by = c("id" = "video_id")) %>%
    mutate(
      n_count = coalesce(n_count, 0L),
      mean_count = coalesce(mean_count, 0.0),
      counted = n_count > 0
    )

  stats_by_video_day <- videos %>%
    group_by(date) %>%
    summarise(
      n_video = n(),
      n_watched = sum(counted),
      n_unwatched = n_video - n_watched,
      n_count = sum(n_count),
      sum_count = sum(mean_count),
      mean_count_per_min = mean(if_else(counted, mean_count / (duration / 60), 0))
    )

  stats_by_video_day_7AM7PM <- videos %>%
    filter(hour(start_timestamp) >= 7, hour(start_timestamp) < 19) %>%
    group_by(date) %>%
    summarise(
      n_video = n(),
      n_watched = sum(counted),
      n_unwatched = n_video - n_watched,
      n_count = sum(n_count),
      sum_count = sum(mean_count),
      mean_count_per_min = mean(if_else(counted, mean_count / (duration / 60), 0))
    )

  stats_by_count_day <- tbl_counts %>%
    filter(video_id %in% videos$id) %>%
    mutate(
      date = as.Date(created_at, tz = "US/Eastern")
    ) %>%
    group_by(date) %>%
    summarise(
      n_count = n(),
      n_count_zero = sum(count == 0),
      sum_count = sum(count),
      n_session = length(unique(session))
    )

  videos_hour_tally <- videos %>%
    filter(
      date >= as.Date(start_date),
      date <= as.Date(end_date)
    ) %>%
    mutate(
      hour = hour(start_timestamp)
    ) %>%
    group_by(date, hour) %>%
    summarise(
      n = n(),
      mean_duration = mean(duration)/60, # sec -> min
      sum_duration = sum(duration)/60, # sec -> min
      sum_duration_watched = sum(duration * counted)/60,
      n_watched = sum(counted),
      n_count = sum(n_count),
      sum_count = sum(mean_count)
    ) %>%
    ungroup %>%
    complete(
      date, hour = seq(0, 23, by = 1),
      fill = list(
        n = 0,
        mean_duration = 0,
        sum_duration = 0,
        n_watched = 0,
        n_count = 0,
        sum_count = 0
      )
    ) %>%
    filter(
      date < as.Date(now(), tz = "US/Eastern") | hour < hour(now(tzone = "US/Eastern"))
    )

  if (fullDay) {
    run_counts <- videos %>%
      filter(
        date >= ymd(start_date),
        date <= ymd(end_date),
        # !(hour(start) != hour(end) & hour(end) %in% c(7, 11, 15, 19) & minute(end) > 0)
      ) %>%
      mutate(
        hour = hour(start_timestamp),
        period = case_when(
          hour >= 0 & hour < 4 ~ 1,
          hour >= 4 & hour < 7 ~ 2,
          hour >= 7 & hour < 11 ~ 3,
          hour >= 11 & hour < 15 ~ 4,
          hour >= 15 & hour < 19 ~ 5,
          hour >= 19 ~ 6,
          TRUE ~ NA_real_
        )
      ) %>%
      filter(!is.na(period)) %>%
      select(date, video_id = id, start = start_timestamp, end = end_timestamp, hour, period, duration, n_count, mean_count)
  } else {
    run_counts <- videos %>%
      filter(
        date >= ymd(start_date),
        date <= ymd(end_date),
        hour(start_timestamp) < 21,
        hour(end_timestamp) >= 5
        # !(hour(start) != hour(end) & hour(end) %in% c(7, 11, 15, 19) & minute(end) > 0)
      ) %>%
      mutate(
        hour = hour(start_timestamp),
        period = case_when(
          hour >= 7 & hour < 11 ~ 1,
          hour >= 11 & hour < 15 ~ 2,
          hour >= 15 & hour < 19 ~ 3,
          TRUE ~ NA_real_
        )
      ) %>%
      filter(!is.na(period)) %>%
      select(date, video_id = id, start = start_timestamp, end = end_timestamp, hour, period, duration, n_count, mean_count)
  }

  run_hour <- run_counts %>%
    select(
      date,
      hour,
      n_count,
      y_i = mean_count,
      t_i = duration
    ) %>%
    mutate(
      t_i_counted = t_i * (n_count > 0)
    ) %>%
    group_by(date, hour) %>%
    summarise(
      N = n(),
      n = sum(n_count > 0),
      T = sum(t_i),
      sum_y = sum(y_i, na.rm = TRUE),
      sum_t = sum(t_i_counted),
      mean_t = coalesce(sum_t / n, 0),
      r = coalesce(sum_y / sum_t, 0),
      Y = r * T,
      se2 = coalesce(sum((y_i - r * t_i_counted) ^ 2, na.rm = TRUE) / (n - 1), 0),
      var_Y = coalesce((T / mean_t)^2 * (N - n) / (N * n) * se2, 0),
      df = n - 1,
      t_star = coalesce(qt(0.975, df = df), 0),
      ci_lower = Y - t_star * sqrt(var_Y),
      ci_upper = Y + t_star * sqrt(var_Y),
      a = if_else(n == 0, 0, N * (N - n) / n)
    )

  run_period <- run_counts %>%
    select(
      date,
      period,
      n_count,
      y_i = mean_count,
      t_i = duration
    ) %>%
    mutate(
      t_i_counted = t_i * (n_count > 0)
    ) %>%
    group_by(date, period) %>%
    summarise(
      N = n(),
      n = sum(n_count > 0),
      T = sum(t_i),
      sum_y = sum(y_i, na.rm = TRUE),
      sum_t = sum(t_i_counted),
      mean_t = coalesce(sum_t / n, 0),
      r = coalesce(sum_y / sum_t, 0),
      Y = r * T,
      se2 = if_else(n > 1, coalesce(sum((y_i - r * t_i_counted) ^ 2, na.rm = TRUE) / (n - 1), 0), 0),
      var_Y = coalesce((T / mean_t)^2 * (N - n) / (N * n) * se2, 0),
      df = n - 1,
      t_star = coalesce(qt(0.975, df = df), 0),
      ci_lower = Y - t_star * sqrt(var_Y),
      ci_upper = Y + t_star * sqrt(var_Y),
      a = if_else(n == 0, 0, N * (N - n) / n)
    )

  run_day <- run_period %>%
    group_by(date) %>%
    summarise(
      df_num = sum(a * se2),
      df_den = sum((a * se2) ^ 2 / (n - 1), na.rm = TRUE),
      N = sum(N),
      n = sum(n),
      T = sum(T),
      sum_y = sum(sum_y),
      sum_t = sum(sum_t),
      Y = sum(Y),
      r = Y / T,
      var_Y = sum(var_Y),
      se_Y = sqrt(var_Y),
      df = coalesce(df_num ^ 2 / df_den, 0),
      df = round(df),
      t_star = coalesce(qt(0.975, df = df), 0),
      ci_lower = Y - t_star * sqrt(var_Y),
      ci_upper = Y + t_star * sqrt(var_Y)
    )

  run_total <- run_day %>%
    summarise(
      N = sum(N),
      n = sum(n),
      T = sum(T),
      sum_y = sum(sum_y),
      sum_t = sum(sum_t),
      Y = sum(Y),
      r = Y / T,
      var_Y = sum(var_Y),
      se_Y = sqrt(var_Y),
      df = sum(df_num) ^ 2 / sum(df_den),
      df = round(df),
      t_star = coalesce(qt(0.975, df = df), 0),
      ci_lower = Y - t_star * sqrt(var_Y),
      ci_upper = Y + t_star * sqrt(var_Y)
    )

  run_day_cumul <- run_day %>%
    mutate(
      Y = cumsum(Y),
      var_Y = cumsum(var_Y),
      se = sqrt(var_Y),
      df_num = cumsum(df_num),
      df_den = cumsum(df_den),
      df = df_num ^ 2 / df_den,
      df = coalesce(round(df), 0),
      t_star = map_dbl(df, ~ qt(0.975, df = .)),
      t_star = coalesce(t_star, 0),
      ci_lower = Y - t_star * se,
      ci_upper = Y + t_star * se
    )

  pdf(
    fname,
    title = glue("Herring Video Report ({site}, {yr})"),
    width = 11,
    height = 8.5
  )

  # TILES

  p1 <- videos_hour_tally %>%
    ggplot(aes(date, hour, fill = n)) +
    geom_tile() +
    scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(breaks = seq(0, 23), expand = c(0, 0)) +
    scale_fill_gradientn("# Videos\nRecorded", colours = rev(brewer.pal(8, "Spectral")), limits = c(0, NA)) +
    labs(
      x = "Date",
      y = "Hour of Day",
      title = "# Videos Recorded"
    ) +
    theme(
      panel.grid.minor = element_blank()
    )

  p2 <- videos_hour_tally %>%
    ggplot(aes(date, hour, fill = sum_duration)) +
    geom_tile() +
    scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(breaks = seq(0, 23), expand = c(0, 0)) +
    scale_fill_gradientn("Duration\n(min)", colours = rev(brewer.pal(8, "Spectral")), limits = c(0, NA)) +
    labs(
      x = "Date",
      y = "Hour of Day",
      title = "Total Duration of Recorded Videos"
    ) +
    theme(
      panel.grid.minor = element_blank()
    )

  p3 <- videos_hour_tally %>%
    ggplot(aes(date, hour, fill = n_watched)) +
    geom_tile(aes(alpha = n_watched > 0)) +
    scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(breaks = seq(0, 23), expand = c(0, 0)) +
    scale_alpha_manual("", values = c("TRUE" = 1, "FALSE" = 0), guide = FALSE) +
    scale_fill_gradientn("# Videos\nCounted", colours = rev(brewer.pal(8, "Spectral")), limits = c(1, NA)) +
    labs(
      x = "Date",
      y = "Hour of Day",
      title = "# Videos Counted"
    ) +
    theme(
      panel.grid.minor = element_blank()
    )

  p4 <- videos_hour_tally %>%
    ggplot(aes(date, hour, fill = sum_count)) +
    geom_tile(aes(alpha = n_watched > 0)) +
    scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(breaks = seq(0, 23), expand = c(0, 0)) +
    scale_alpha_manual("", values = c("TRUE" = 1, "FALSE" = 0), guide = FALSE) +
    scale_fill_gradientn("# Fish\nCounted", colours = rev(brewer.pal(8, "Spectral")), limits = c(0, NA)) +
    labs(
      x = "Date",
      y = "Hour of Day",
      title = "# Fish Counted"
    ) +
    theme(
      panel.grid.minor = element_blank()
    )

  grid.arrange(
    p1, p2, p3, p4,
    ncol = 2,
    top = glue("Herring Videos ({site}, {yr}) | Hourly Video Summary"),
    bottom = updated_at
  )

  # RUN ESTIMATE

  p1 <- run_day %>%
    ggplot(aes(date, Y)) +
    geom_col(fill = "gray50") +
    geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper), width = 0.5) +
    # scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(breaks = scales::pretty_breaks(n = 10), labels = scales::comma, expand = c(0, 0)) +
    coord_cartesian(ylim = c(0, max(run_day$ci_upper, na.rm = TRUE) * 1.1)) +
    labs(
      x = "Date",
      y = "Est. # Fish",
      title = "Daily Run Estimate",
      subtitle = "Date = when video was recorded"
    )

  p2 <- run_day_cumul %>%
    ggplot(aes(date)) +
    geom_line(aes(y = Y)) +
    geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2) +
    geom_point(
      data = run_day_cumul %>%
        filter(date == max(date)),
      aes(x = date, y = Y)
    ) +
    geom_text(
      data = run_day_cumul %>%
        filter(
          date == max(date)
        ),
      aes(label = scales::comma(round(Y)), x = date, y = Y),
      hjust = 1, vjust = 0, nudge_y = 0
    ) +
    # scale_x_date(breaks = scales::pretty_breaks(n = 8)) +
    scale_y_continuous(breaks = scales::pretty_breaks(n = 6), labels = scales::comma) +
    labs(
      x = "Date",
      y = "Cumul. Est. # Fish",
      title = "Cumulative Est. Total Fish (95% CI)",
      subtitle = if_else(fullDay, "Full Day Estimate (24 hr)", "Daytime Estimate (7AM - 7PM)")
    )

  p3 <- run_hour %>%
    ggplot(aes(date, hour, fill = Y)) +
    geom_tile(aes(alpha = n > 0)) +
    scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(breaks = seq(0, 23), expand = c(0, 0)) +
    scale_alpha_manual("", values = c("TRUE" = 1, "FALSE" = 0), guide = FALSE) +
    scale_fill_gradientn("# Fish", colours = rev(brewer.pal(8, "Spectral")), limits = c(0, NA)) +
    labs(
      x = "Date",
      y = "Hour of Day",
      title = "Estimated # Fish"
    ) +
    theme(
      panel.grid.minor = element_blank()
    )

  p4 <- run_hour %>%
    ggplot(aes(date, hour, fill = sqrt(se2))) +
    geom_tile(aes(alpha = n > 0)) +
    scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(breaks = seq(0, 23), expand = c(0, 0)) +
    scale_alpha_manual("", values = c("TRUE" = 1, "FALSE" = 0), guide = FALSE) +
    scale_fill_gradientn("Std Error", colours = rev(brewer.pal(8, "Spectral")), limits = c(0, NA)) +
    labs(
      x = "Date",
      y = "Hour of Day",
      title = "Standard Error"
    ) +
    theme(
      panel.grid.minor = element_blank()
    )

  grid.arrange(
    p1, p2, p3, p4,
    ncol = 2,
    top = glue("Herring Videos ({site}, {yr}) | Estimated Run Summary"),
    bottom = updated_at
  )

  # BAR CHARTS - DAILY VIDEOS

  p1 <- stats_by_video_day %>%
    select(date, n_unwatched, n_watched) %>%
    gather(var, value, -date) %>%
    mutate(
      var = ordered(var, levels = c("n_watched", "n_unwatched"))
    ) %>%
    ggplot(aes(date, value, fill = var)) +
    geom_bar(position = "stack", stat = "identity") +
    scale_fill_manual(
      "",
      values = c("n_unwatched" = "gray50", "n_watched" = "deepskyblue"),
      labels = c("n_unwatched" = "Not Watched", "n_watched" = "Watched")
    ) +
    scale_x_date(expand = c(0, 0)) +
    labs(
      x = "Date",
      y = "# Videos",
      title = "Number of Videos per Day",
      subtitle = "Date = when video was recorded"
    )

  p2 <- stats_by_video_day %>%
    select(date, n_video, n_watched) %>%
    ggplot(aes(date, n_watched / n_video, fill = "% Watched")) +
    geom_bar(position = "stack", stat = "identity") +
    scale_fill_manual(
      "",
      values = c("deepskyblue")
    ) +
    scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(labels = scales::percent, expand = c(0, 0), limits = c(0, 1)) +
    labs(
      x = "Date",
      y = "% Videos Watched",
      title = "Percent of Videos Watched per Day",
      subtitle = "Date = when video was recorded"
    )

  grid.arrange(p1, p2, nrow = 2, bottom = updated_at)

  # BAR CHARTS - DAILY VIDEOS (7AM - 7 PM)

  p1 <- stats_by_video_day_7AM7PM %>%
    select(date, n_unwatched, n_watched) %>%
    gather(var, value, -date) %>%
    mutate(
      var = ordered(var, levels = c("n_watched", "n_unwatched"))
    ) %>%
    ggplot(aes(date, value, fill = var)) +
    geom_bar(position = "stack", stat = "identity") +
    scale_fill_manual(
      "",
      values = c("n_unwatched" = "gray50", "n_watched" = "deepskyblue"),
      labels = c("n_unwatched" = "Not Watched", "n_watched" = "Watched")
    ) +
    scale_x_date(expand = c(0, 0)) +
    labs(
      x = "Date",
      y = "# Videos",
      title = "Number of Videos per Day (7AM - 7PM Only)",
      subtitle = "Date = when video was recorded"
    )

  p2 <- stats_by_video_day_7AM7PM %>%
    select(date, n_video, n_watched) %>%
    ggplot(aes(date, n_watched / n_video, fill = "% Watched")) +
    geom_bar(position = "stack", stat = "identity") +
    scale_fill_manual(
      "",
      values = c("deepskyblue")
    ) +
    scale_x_date(expand = c(0, 0)) +
    scale_y_continuous(labels = scales::percent, expand = c(0, 0), limits = c(0, 1)) +
    labs(
      x = "Date",
      y = "% Videos Watched",
      title = "Percent of Videos Watched per Day (7AM - 7PM Only)",
      subtitle = "Date = when video was recorded"
    )

  grid.arrange(p1, p2, nrow = 2, bottom = updated_at)


  #### BAR CHARTS - BY VIDEO DATE

  p1 <- stats_by_video_day %>%
    ggplot(aes(date, n_count)) +
    geom_bar(fill = "orangered", stat = "identity") +
    labs(
      x = "Date Video was Recorded",
      y = "# Counts",
      title = "Number of Counts per Day"
    )

  p2 <- stats_by_video_day %>%
    ggplot(aes(date, sum_count)) +
    geom_bar(fill = "orangered", stat = "identity") +
    labs(
      x = "Date Video was Recorded",
      y = "# Fish",
      title = "Number of Fish Counted per Day"
    )

  p3 <- stats_by_video_day %>%
    ggplot(aes(date, mean_count_per_min)) +
    geom_bar(fill = "orangered", stat = "identity") +
    labs(
      x = "Date Video was Recorded",
      y = "Average # Fish per Minute",
      title = "Fish Passage Rate per Day"
    )

  grid.arrange(p1, p2, p3, ncol = 2, top = "Daily Stats by Date Video was Recorded", bottom = updated_at)


  # BAR CHARTS - BY COUNT DATE ----------------------------------------------

  p1 <- stats_by_count_day %>%
    ggplot(aes(date, n_count)) +
    geom_bar(fill = "chartreuse3", stat = "identity") +
    labs(
      x = "Date Video was Counted",
      y = "# Video Counts",
      title = "Number of Video Counts per Day"
    )

  p2 <- stats_by_count_day %>%
    ggplot(aes(date, sum_count)) +
    geom_bar(fill = "chartreuse3", stat = "identity") +
    labs(
      x = "Date Video was Counted",
      y = "# Fish Counted",
      title = "Number of Fish Counted per Day"
    )

  p3 <- stats_by_count_day %>%
    ggplot(aes(date, n_count/n_session)) +
    geom_bar(fill = "chartreuse3", stat = "identity") +
    labs(
      x = "Date Video was Counted",
      y = "# Videos Counted",
      title = "Avg Number of Videos Counted per Session"
    )

  p4 <- stats_by_count_day %>%
    ggplot(aes(date, n_count_zero / n_count)) +
    geom_bar(fill = "chartreuse3", stat = "identity") +
    scale_y_continuous(labels = scales::percent) +
    labs(
      x = "Date Video was Counted",
      y = "% Videos with Zero Count",
      title = "Percent of Videos Watched with Zero Fish"
    )

  grid.arrange(p1, p2, p3, p4, ncol = 2, top = "Daily Stats by Count Date", bottom = updated_at)


  # HISTOGRAMS --------------------------------------------------------------

  p1 <- videos %>%
    filter(mean_count > 0) %>%
    ggplot(aes(mean_count)) +
    geom_histogram(binwidth = 2) +
    labs(
      x = "# Fish / Video",
      y = "# Videos",
      title = "# Fish per Video (excluding 0 counts)",
      subtitle = "How many fish are counted per video?"
    ) +
    theme(
      strip.background = element_blank(),
      strip.placement = "outside"
    )
  p2 <- videos %>%
    filter(mean_count > 0) %>%
    ggplot(aes(mean_count/(duration / 60))) +
    geom_histogram() +
    labs(
      x = "# Fish / Minute",
      y = "# Videos",
      title = "# Fish per Video Minute (excluding 0 counts)",
      subtitle = "How many fish pass per minute of video?"
    ) +
    theme(
      strip.background = element_blank(),
      strip.placement = "outside"
    )
  p3 <- videos %>%
    filter(duration < 100) %>%
    ggplot(aes(duration)) +
    geom_histogram() +
    labs(
      x = "Duration (seconds)",
      y = "# Videos",
      title = "Video Duration",
      subtitle = "How long are the videos?"
    ) +
    theme(
      strip.background = element_blank(),
      strip.placement = "outside"
    )
  p4 <- videos %>%
    filter(!is.na(n_count), n_count > 0) %>%
    ggplot(aes(factor(n_count))) +
    geom_bar() +
    labs(
      x = "# Times Video was Counted",
      y = "# Videos",
      title = "# Counts per Video",
      subtitle = "How many times has the same video been watched?"
    ) +
    theme(
      strip.background = element_blank(),
      strip.placement = "outside"
    )
  grid.arrange(p1, p2, p3, p4, nrow = 2, top = "Histograms", bottom = updated_at)

  p <- counts %>%
    ggplot(aes(created_at, start_timestamp)) +
    geom_point(size = 1) +
    scale_x_datetime(
      breaks = scales::pretty_breaks(n = 10),
      labels = scales::date_format("%b %d")
    ) +
    scale_y_datetime(
      breaks = scales::pretty_breaks(n = 10),
      labels = scales::date_format("%b %d")
    ) +
    labs(
      x = "Timestamp of Count",
      y = "Start Timestamp of Video"
    ) +
    theme(aspect = 1)
  grid.arrange(p, top = "Count Timestamp vs Video Timestamp", bottom = updated_at)

  dev.off()

}



map(cfg$reports, ~ generate_report(.$site, .$start, .$end, .$fullDay))

# generate_report("PLY", "2023-04-12", "2023-07-01", TRUE)
#
# site="PLY"
# start_date="2023-04-12"
# end_date="2023-07-01"
# fullDay=TRUE

# # load volunteer counts ---------------------------------------------------
#
# volunteer <- fromJSON(file.path("json", paste0("volunteer-counts-", cfg$report$year, ".json"))) %>%
#   mutate(
#     start = mdy_hms(paste(date, starttime), tz = "US/Eastern"),
#     end = mdy_hms(paste(date, endtime), tz = "US/Eastern"),
#     count = as.numeric(count),
#     human_duration = as.numeric(difftime(end, start, units = "mins"))
#   ) %>%
#   arrange(start) %>%
#   distinct %>%
#   mutate(
#     id = row_number()
#   )
#
# volunteer_videos <- volunteer %>%
#   select(id, start, end) %>%
#   mutate(
#     video = map2(start, end, function (start, end) {
#       filter(videos, start_timestamp >= start, start_timestamp <= end) %>%
#         select(video_id = id, filename, video_start = start_timestamp, video_end = end_timestamp, duration, n_count, mean_count, counted)
#     })
#   ) %>%
#   unnest(video) %>%
#   group_by(id, start, end) %>%
#   summarise(
#     n_video = n(),
#     n_video_counted = sum(counted),
#     video_count = as.integer(sum(mean_count)),
#     video_duration = round(sum(duration) / 60, 1)
#   ) %>%
#   ungroup
#
# volunteer_videos <- volunteer %>%
#   left_join(volunteer_videos, by = c("id", "start", "end")) %>%
#   mutate(
#     n_video = ifelse(is.na(n_video), 0, n_video),
#     n_video_counted = ifelse(is.na(n_video_counted), 0, n_video_counted),
#     video_count = ifelse(is.na(video_count), 0, video_count),
#     video_duration = ifelse(is.na(video_duration), 0, video_duration)
#   )
#
# volunteer_tbl <- volunteer_videos %>%
#   select(lastname, date, start, end, n_video, n_video_counted, human_duration, video_duration, count, video_count) %>%
#   arrange(start) %>%
#   mutate(
#     start = format(start, "%H:%M"),
#     end = format(end, "%H:%M")
#   ) %>%
#   rename(
#     `Last Name` = lastname,
#     `Date` = date,
#     `Start\nTime` = start,
#     `End\nTime` = end,
#     `# Videos\nRecorded` = n_video,
#     `# Videos\nCounted` = n_video_counted,
#     `Human Duration\n(min)` = human_duration,
#     `Video Duration\n(min)` = video_duration,
#     `Human\nCount` = count,
#     `Video\nCount` = video_count
#   )
#
#
#
# # VOLUNTEER ---------------------------------------------------------------
#
# volunteer_plot_data <- volunteer_videos %>%
#   filter(n_video == n_video_counted)
#
# lm_counts <- lm(video_count ~ count, data = volunteer_plot_data)
#
# p <- volunteer_plot_data %>%
#   ggplot(aes(count, video_count)) +
#   geom_abline() +
#   geom_point(size = 1) +
#   geom_smooth(method = "lm", se = FALSE) +
#   annotate(
#     "text", x = 0, y = max(c(volunteer_plot_data$count, volunteer_plot_data$video_count)),
#     label = paste0(
#       "Video Count = ",
#       format(coef(lm_counts)[1], digits = 3),
#       " + ",
#       format(coef(lm_counts)[2], digits = 3),
#       " * Human Count\nR^2 = ",
#       format(summary(lm_counts)$r.squared, digits = 3)
#     ),
#     hjust = 0, vjust = 0.5
#   ) +
#   coord_equal() +
#   labs(
#     x = "Human Count",
#     y = "Video Count",
#     title = "Human (in-person volunteer) vs. Video Counts",
#     subtitle = "Only includes video counts if all videos during 10-minute period have been counted\nBlack Line = 1:1 Line, Blue Line = Linear Regression"
#   )
# print(p)
#
#
# # Volunteer counts table
#
# for (i in seq(1, nrow(volunteer_tbl), by = 25)) {
#   i_max <- min(nrow(volunteer_tbl), i + 24)
#   volunteer_tbl[i:i_max, ] %>%
#     tableGrob() %>%
#     grid.arrange(top = "Volunteer Counts", bottom = updated_at)
# }


