const config = require('../config');


const knex = require('knex')({
  client: 'pg',
  connection: config.db,
});

function fishStatus() {
  const sql = `
    WITH c AS (
      SELECT
        video_id,
        count(*) as n_count,
        avg(count) as mean_count
      FROM counts
      WHERE NOT flagged
      GROUP BY video_id
    ),
    vc AS (
      SELECT
        v.id,
        (v.start_timestamp AT TIME ZONE 'America/New_York')::date as date,
        c.mean_count as mean_count
      FROM videos v
      LEFT JOIN c ON v.id = c.video_id
      WHERE NOT v.flagged
      AND (v.start_timestamp AT TIME ZONE 'America/New_York')::date >= '2018-04-27'
    ),
    vcd AS (
      SELECT
        vc.date,
        sum(vc.mean_count) as count
      FROM vc
      GROUP BY vc.date
    ),
    d AS (
      SELECT generate_series('2018-04-25'::date, (now() at time zone 'US/Eastern')::date, '1 day')::date as date
    )
    SELECT
      d.date::text as date,
      COALESCE(vcd.count, 0)::real as count
    FROM d
    LEFT JOIN vcd
    ON d.date = vcd.date
    ORDER BY d.date;
  `;

  return knex
    .raw(sql)
    .then(result => result.rows);
}

function videoStatus() {
  const sql = `
    WITH c AS (
      SELECT
        video_id,
        count(*) as n_count
      FROM counts
      WHERE NOT flagged
      GROUP BY video_id
    ),
    vc AS (
      SELECT
        v.id,
        (v.start_timestamp AT TIME ZONE 'America/New_York')::date as date,
        (COALESCE(c.n_count, 0) > 0)::integer as counted
      FROM videos v
      LEFT JOIN c on v.id = c.video_id
      WHERE NOT flagged
      AND (v.start_timestamp AT TIME ZONE 'America/New_York')::date >= '2018-04-27'
    ),
    vcd AS (
      SELECT
        vc.date,
        count(*) as n_total,
        sum(counted) as n_counted
      FROM vc
      GROUP BY vc.date
    ),
    d AS (
      SELECT generate_series('2018-04-25'::date, (now() at time zone 'US/Eastern')::date, '1 day')::date as date
    )
    SELECT
      d.date::text as date,
      COALESCE(vcd.n_total::integer, 0) as n_total,
      COALESCE(vcd.n_counted::integer, 0) as n_counted
    FROM d
    LEFT JOIN vcd
    ON d.date = vcd.date
    ORDER BY d.date;
  `;

  return knex
    .raw(sql)
    .then(result => result.rows);
}

function activityStatus() {
  const sql = `
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
      AND (c.created_at at time zone 'America/New_York')::date = (current_timestamp at time zone 'America/New_York')::date
    ORDER BY c.created_at;
  `;

  return knex
    .raw(sql)
    .then(result => result.rows);
}

function getStatus() {
  return Promise.all([fishStatus(), videoStatus(), activityStatus()])
    .then((results) => {
      return {
        fish: results[0],
        video: results[1],
        activity: results[2]
      };
    });
}

function getVideos(params) {
  let qry = knex('videos')
    .select();

  if (params.location) {
    qry = qry.where('location_id', params.location);
  }

  if (params.year) {
    qry = qry.where(knex.raw('date_part(\'year\', start_timestamp at time zone \'America/New_York\')'), '=', params.year);
  }

  return qry.orderBy('location_id').orderBy('start_timestamp');
}

function getVideoById(id) {
  return knex('videos')
    .select()
    .where('id', id);
}

// function getRandomVideo(params) {
//   if (params.id) {
//     return getVideoById(params.id);
//   }

//   const counts = knex('counts')
//     .select('video_id', knex.raw('count(*)::integer as n_count'), knex.raw('avg(count)::real as mean_count'))
//     .where('flagged', false)
//     .groupBy('video_id')
//     .as('c');

//   // select subset of videos
//   let videos = knex('videos')
//     .where('flagged', false)
//     // run year
//     .andWhere(knex.raw('date_part(\'year\', start_timestamp at time zone \'America/New_York\')'), '=', config.api.runYear)
//     // only daylight hours
//     .andWhere(knex.raw('date_part(\'hour\', start_timestamp at time zone \'America/New_York\')'), '>=', 6)
//     .andWhere(knex.raw('date_part(\'hour\', start_timestamp at time zone \'America/New_York\')'), '<=', 19);

//   if (params.date) {
//     videos = videos.andWhere(knex.raw('(start_timestamp at time zone \'America/New_York\')::date::text'), params.date);
//   }
//   // else {
//     // videos = videos.whereRaw(
//     //   '(start_timestamp at time zone \'America/New_York\')::date > \'2017-05-14\'::date'
//     // );
//   // }

//   if (params.location) {
//     videos = videos.andWhere('location_id', params.location);
//   } else {
//     videos = videos.andWhere('location_id', 'UML');
//   }

//   // join videos and counts
//   const cte = videos
//     .leftJoin(counts, 'videos.id', 'c.video_id')
//     .select();
//     // .where(knex.raw('COALESCE(n_count, 0)'), '<=', 2)
//     // .where(function () {
//     //   this.where(knex.raw('COALESCE(mean_count, 0)'), '>', 0);
//     //   if (!params.first || params.first === 'false') {
//     //     this.orWhere(knex.raw('COALESCE(n_count, 0)'), '=', 0);
//     //   }
//     // });

//   return knex
//     .raw(
//       'with v as (?) ?',
//       [cte, knex.raw('select * from v offset floor( random() * (select count(*) from v) ) limit 1')]
//     )
//     .then(results => results.rows);
// }

function getRandomVideo(params) {
  if (params.id) {
    return getVideoById(params.id);
  }

  const cte = knex('videos')
    .where('flagged', false)
    .andWhere(knex.raw('date_part(\'year\', start_timestamp at time zone \'America/New_York\')'), '=', config.api.videos.year)
    .andWhere(knex.raw('(start_timestamp at time zone \'America/New_York\')::date'), '>=', config.api.videos.start)
    // only daylight hours
    .andWhere(knex.raw('date_part(\'hour\', start_timestamp at time zone \'America/New_York\')'), '>=', config.api.videos.hours[0])
    .andWhere(knex.raw('date_part(\'hour\', start_timestamp at time zone \'America/New_York\')'), '<', config.api.videos.hours[1])
    .andWhere('location_id', config.api.videos.location);

  return knex
    .raw(
      'with v as (?) ?',
      [cte, knex.raw('select * from v offset floor( random() * (select count(*) from v) ) limit 1')]
    )
    .then(results => results.rows);
}

function getSprintCount(params) {
  const count = knex('counts')
    .count()
    .whereRaw('(created_at at time zone \'America/New_York\')::date >= ?::date', params.from)
    .whereRaw('(created_at at time zone \'America/New_York\')::date <= ?::date', params.to)
    .then(result => result[0]);

  return count;
}

function saveCount(data) {
  return knex('counts')
    .returning('*')
    .insert({
      video_id: data.video_id,
      count: data.count,
      comment: data.comment,
      session: data.session,
      flagged: data.count >= config.api.maxCount,
      users_uid: data.users_uid,
    });
}

function saveSensor(data) {
  return knex('sensor')
    .returning('*')
    .insert(data);
}

function getSensorData(query) {
  let sql = knex('sensor')
    .select()
    .orderBy('timestamp', 'desc');

  if (query) {
    sql = sql.where(function whereClause() {
      if (query.start) {
        this.where('timestamp', '>=', query.start);
      }
      if (query.location_id) {
        this.where('location_id', query.location_id);
      }
    });
    if (query.last) {
      sql = sql.limit(query.last);
    }
  }
  return sql;
}

function getUser(params) {
  console.log('db:getUser', params);
  return knex('users')
    .where(params)
    .then((rows) => {
      if (rows.length === 0) {
        return Promise.reject('User not found');
      }
      return rows[0];
    })
    .then(user => knex('counts')
      .where('users_uid', user.uid)
      .groupBy('users_uid')
      .select(knex.raw('count(counts.count)::integer as n_count'), knex.raw('sum(counts.count)::integer as sum_count'))
      .then((rows) => {
        if (rows.length === 0) {
          return {
            ...user,
            n_count: 0,
            sum_count: 0
          };
        }
        return {
          ...user,
          n_count: rows[0].n_count,
          sum_count: rows[0].sum_count
        };
      })
    );
}

function updateUser(user) {
  return knex('users')
    .where({ uid: user.uid })
    .update({
      username: user.username
    })
    .returning('*');
}

function deleteUser(user) {
  return knex('users')
    .where({ uid: user.uid })
    .delete();
}

function createUser(data) {
  return knex('users')
    .returning('*')
    .insert(data);
}

function getLeaderboard() {
  return knex('counts')
    .leftJoin('users', 'counts.users_uid', 'users.uid')
    .leftJoin('videos', 'counts.video_id', 'videos.id')
    .where({
      'counts.flagged': false,
      'videos.flagged': false
    })
    .andWhere(knex.raw('date_part(\'year\', videos.start_timestamp at time zone \'America/New_York\')'), '=', config.api.runYear)
    .whereNotNull('counts.users_uid')
    .groupBy('users.uid')
    .orderBy(knex.raw('count(*)'), 'desc')
    .select(
      'users.uid as uid',
      'users.username as username',
      knex.raw('count(*) as count'),
      knex.raw('sum(counts.count) as total'),
      knex.raw('sum(videos.duration) as duration')
    );
}

function getDailyRunEstimate(params) {
  return knex('run_daily')
    .select()
    .where('date', '>=', params.start)
    .where('date', '<=', params.end);
}

module.exports = {
  getStatus,
  getRandomVideo,
  getVideoById,
  getVideos,
  getSprintCount,
  saveCount,
  saveSensor,
  getSensorData,
  createUser,
  getUser,
  updateUser,
  deleteUser,
  getLeaderboard,
  getDailyRunEstimate
};
