# export leaderboard

library(tidyverse)
library(lubridate)
library(jsonlite)
library(glue)

LOCATION_ID <- "UML"
START_DATE <- "2024-04-01"
END_DATE <- "2024-07-01"

cfg <- read_json("./config.json")


# load: email -------------------------------------------------------------

# npm install -g firebase-tools
# firebase logout
# firebase login
# firebase auth:export ~/herring_users.csv --format=csv --project myrwa-herring
# awk -F "," '{print $1, $2}' ~/herring_users.csv > ~/herring_emails.csv
# rm ~/herring_users.csv
df_email <- read_delim("~/herring_emails.csv", col_names = c("uid", "email"), delim = " ")


# load: leaderboard -------------------------------------------------------

con <- DBI::dbConnect(
  RPostgreSQL::PostgreSQL(),
  dbname = cfg$db$database,
  host = cfg$db$host,
  port = cfg$db$port,
  user = cfg$db$user,
  password = cfg$db$password
)

df_stats <- DBI::dbGetQuery(
  con,
  "
    with t as (
      select * from f_users_stats($1, $2, $3)
    )
    select t.*,
      u.first_name, u.last_name, u.zip, u.allow_email
    from t left join users u on t.uid=u.uid",
  params = list(LOCATION_ID, START_DATE, END_DATE)
)

DBI::dbDisconnect(con)


# merge -------------------------------------------------------------------

df <- df_email %>%
  full_join(df_stats, by = "uid") %>%
  arrange(desc(n_count)) %>%
  rename(videos_counts = n_count, fish_counted = sum_count) %>%
  filter(!is.na(username))

head(df, 10)

df %>%
  filter(videos_counts > 0) %>%
  ggplot(aes(videos_counts)) +
  geom_histogram() +
  scale_x_log10()

# export ------------------------------------------------------------------

df %>%
  write_csv("csv/leaderboard.csv", na = "")

