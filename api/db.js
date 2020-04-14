const config = require('../config');


const knex = require('knex')({
  client: 'pg',
  connection: config.db,
});

function fishStatus(params) {
  return knex
    .raw(
      'SELECT * FROM f_fish_status(:location_id, :start_date, :end_date, :start_hour, :end_hour)',
      params
    )
    .then(result => result.rows);
}

function videoStatus(params) {
  return knex
    .raw(
      'SELECT * FROM f_video_status(:location_id, :start_date, :end_date, :start_hour, :end_hour)',
      params
    )
    .then(result => result.rows);
}

function activityStatus(params) {
  return knex
    .raw(
      'SELECT * FROM f_activity_status_today(:location_id)',
      params
    )
    .then(result => result.rows);
}

function getStatus(params) {
  return Promise.all([fishStatus(params), videoStatus(params), activityStatus(params)])
    .then(results => ({
      fish: results[0],
      video: results[1],
      activity: results[2]
    }));
}

function getVideos(params) {
  return knex('videos')
    .select()
    .where('location_id', params.location_id)
    .andWhere(knex.raw('(start_timestamp at time zone \'America/New_York\')::DATE'), '>=', params.start_date)
    .andWhere(knex.raw('(start_timestamp at time zone \'America/New_York\')::DATE'), '<=', params.end_date)
    .orderBy('start_timestamp');
}

function getVideoById(id) {
  return knex('videos')
    .select()
    .where('id', id);
}

function getRandomVideoUniform(params) {
  if (params.id) {
    return getVideoById(params.id);
  }

  let func;
  if (params.first) {
    func = 'f_candidate_videos_counted';
  } else {
    func = 'f_candidate_videos';
    // func = 'f_candidate_videos_counted_any'; // only counted videos for sprint
  }

  const cte = knex.raw(`SELECT * FROM ${func}(:location_id, :start_date, :end_date, :start_hour, :end_hour)`, params);

  return knex
    .raw(
      'WITH v AS (?) ?',
      [cte, knex.raw('SELECT * FROM v OFFSET FLOOR(RANDOM() * (SELECT COUNT(*) FROM v) ) LIMIT 1')]
    )
    .then(results => results.rows);
}

function getRandomVideoExponential(params) {
  if (params.id) {
    return getVideoById(params.id);
  }

  let func;
  if (params.first) {
    func = 'f_candidate_videos_counted';
  } else {
    func = 'f_candidate_videos';
  }

  const cte = knex.raw(`SELECT * FROM ${func}(:location_id, :start_date, :end_date, :start_hour, :end_hour)`, params);

  return knex
    .raw(
      'WITH v AS (?) ?',
      [cte, knex.raw('SELECT * FROM v OFFSET random_exp(:lambda, (SELECT count(*)::int FROM v)) LIMIT 1', params)]
    )
    .then(results => results.rows);
}

function saveCount(data) {
  return knex('counts')
    .returning('*')
    .insert({
      video_id: data.video_id,
      count: data.count,
      comment: data.comment,
      session: data.session,
      flagged: data.flagged || data.count >= config.api.maxCount,
      users_uid: data.users_uid,
    });
}

function saveSensor(data) {
  return knex('sensor')
    .returning('*')
    .insert(data);
}

function getSensorData(params) {
  return knex('sensor')
    .select()
    .where('location_id', params.location_id)
    .andWhere(knex.raw('(timestamp AT TIME ZONE \'US/Eastern\')::DATE >= ?', [params.start_date]))
    .andWhere(knex.raw('(timestamp AT TIME ZONE \'US/Eastern\')::DATE <= ?', [params.end_date]))
    .orderBy('timestamp');
}

function getSensorHourlyData(params) {
  return knex
    .raw(
      'SELECT * FROM f_sensor_hourly(:location_id, :start_date, :end_date)',
      params
    )
    .then(result => result.rows);
}

function checkUsernameAvailability(username) {
  return knex('users')
    .where('username', username)
    .then((rows) => {
      if (rows.length === 0) {
        return true;
      }
      return false;
    });
}

function getUserByUsername(params) {
  return knex
    .raw(
      'SELECT * FROM f_users_stats(:location_id, :start_date, :end_date) WHERE username=:username LIMIT 1',
      params
    )
    .then(result => result.rows);
}

function getUserByUid(params) {
  return knex
    .raw(
      'SELECT * FROM f_users_stats(:location_id, :start_date, :end_date) WHERE uid=:uid LIMIT 1',
      params
    )
    .then(result => result.rows);
}

function getUsers(params) {
  if (params.username) {
    return getUserByUsername(params);
  }
  return knex
    .raw(
      'SELECT * FROM f_users_stats(:location_id, :start_date, :end_date)',
      params
    )
    .then(result => result.rows);
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

function getDailyRunEstimate(params) {
  return knex
    .raw(
      'SELECT * FROM f_run_daily(:location_id, :start_date, :end_date)',
      params
    )
    .then(result => result.rows);
}

module.exports = {
  getStatus,
  getRandomVideoUniform,
  getRandomVideoExponential,
  getVideoById,
  getVideos,
  saveCount,
  saveSensor,
  getSensorData,
  getSensorHourlyData,
  createUser,
  checkUsernameAvailability,
  updateUser,
  deleteUser,
  getUsers,
  getUserByUsername,
  getUserByUid,
  getDailyRunEstimate
};
