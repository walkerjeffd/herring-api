const fs = require('fs')
const express = require('express')
const morgan = require('morgan')
const bodyParser = require('body-parser')

const db = require('./lib/db')
const utils = require('./lib/utils')
// const volunteer = require('./lib/volunteer')

const config = require('./config')

const app = express()

// access logging
morgan.token('real-ip', req => req.headers['x-real-ip'] || req.connection.remoteAddress)
const logFormat = ':date[iso] :real-ip :remote-user :method :url HTTP/:http-version :status :res[content-length] - :response-time ms'
const accessLogStream = fs.createWriteStream(config.api.logFile, { flags: 'a' })
app.use(morgan(logFormat, { stream: accessLogStream }))

// body parser (json only)
app.use(bodyParser.json())

// allow CORS
const allowCrossDomain = (req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*')
  res.header('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE')
  res.header('Access-Control-Allow-Headers', 'Content-Type')
  next()
}
app.use(allowCrossDomain)

// set up priority queue
// const volunteerQueue = []
// function refreshVolunteerQueue () {
//   console.log('updating volunteerQueue')
//   volunteer.getVideos(config.volunteer.path)
//     .then((data) => {
//       const videos = data.map((row) => { // eslint-disable-line
//         return row.videos
//           .filter(d => d.n_count === 0)
//           .map(d => d.id)
//       })
//       volunteerQueue = [].concat.apply([], videos); // eslint-disable-line
//       console.log(`updated volunteerQueue (n = ${volunteerQueue.length})`)
//     })
// }
// if (config.api.volunteer) {
//   refreshVolunteerQueue()
//   setInterval(refreshVolunteerQueue, config.volunteer.interval * 1000)
// }

// paths to app builds
app.use('/reports', express.static(config.api.static.reports))
app.use('/datasets', express.static(config.api.static.datasets))

// pages
app.use('/www/', express.static('./www/'))

// endpoints
app.get('/', (req, res) => {
  return res.status(200).json({ status: 'ok', data: [] })
})

app.get('/status/', (req, res, next) => {
  const locationId = req.query.location_id || 'UML'
  const siteParams = utils.getSiteParams(locationId)

  const defaultQuery = {
    location_id: locationId,
    ...siteParams.status,
    ...siteParams.times
  }

  const query = Object.assign(defaultQuery, req.query)
  query.end_date = utils.limitDateToToday(query.end_date)

  return db.getStatus(query)
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

app.get('/video', (req, res, next) => {
  const locationId = req.query.location_id || 'UML'
  const params = utils.getSiteParams(locationId)
  const { window, counts, times, sampler } = params
  const defaultQuery = {
    location_id: locationId,
    ...utils.getWindowDates(window),
    ...times,
    ...counts
  }
  const query = Object.assign(defaultQuery, req.query)

  return db.getRandomVideo(query, sampler)
    .then((result) => {
      if (result.length) {
        console.log('served random video location_id=%s id=%d ip=%s', locationId, result[0].id, req.headers['x-real-ip'] || req.connection.remoteAddress)
      } else {
        console.log('served random video location_id=%s id=NULL ip=%s', locationId, req.headers['x-real-ip'] || req.connection.remoteAddress)
      }
      return res.status(200).json({ status: 'ok', data: result })
    })
    .catch(next)
})

app.get('/videos', (req, res, next) => {
  const locationId = req.query.location_id || 'UML'
  const siteParams = utils.getSiteParams(locationId)

  const defaultQuery = {
    location_id: locationId,
    ...siteParams.allVideos
  }

  const query = Object.assign(defaultQuery, req.query)

  db.getVideos(query)
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

app.post('/count/', (req, res, next) => {
  console.log('received count=%d video_id=%d ip=%s', req.body.count, req.body.video_id, req.headers['x-real-ip'] || req.connection.remoteAddress)
  db.saveCount(req.body)
    .then(result => res.status(201).json({ status: 'ok', data: result }))
    .catch(next)
})

app.get('/users/', (req, res, next) => {
  const locationId = req.query.location_id || 'UML'

  const defaultQuery = {
    location_id: locationId,
    ...utils.getSiteParams(locationId).leaderboard
  }

  const query = Object.assign(defaultQuery, req.query)

  return db.getUsers(query)
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

app.get('/users/:uid', (req, res, next) => {
  const locationId = req.query.location_id || 'UML'

  const defaultQuery = {
    location_id: locationId,
    uid: req.params.uid,
    ...utils.getSiteParams(locationId).leaderboard
  }
  const query = Object.assign(defaultQuery, req.query)

  db.getUserByUid(query)
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

app.delete('/users/:uid', (req, res, next) => {
  db.deleteUser({ uid: req.params.uid })
    .then(() => res.status(202).json({ status: 'ok' }))
    .catch(next)
})

app.put('/users/:uid', (req, res, next) => {
  db.updateUser({ uid: req.params.uid, username: req.body.username })
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

app.get('/username-available/', (req, res, next) => {
  if (!req.query.username) {
    return res.status(400).json({ status: 'error', error: { message: 'Missing username query parameter' } })
  }
  return db.checkUsernameAvailability(req.query.username)
    .then(result => res.status(200).json({ status: 'ok', data: { available: result } }))
    .catch(next)
})

app.post('/users/', (req, res, next) => {
  console.log('received new user', req.body.uid, req.body.username, req.headers['x-real-ip'] || req.connection.remoteAddress)
  db.createUser(req.body)
    .then(result => res.status(201).json({ status: 'ok', data: result }))
    .catch(next)
})

app.get('/sensor/', (req, res, next) => {
  const locationId = req.query.location_id || 'UML'

  const defaultQuery = {
    location_id: locationId,
    uid: req.params.uid,
    ...utils.getSiteParams(locationId).status
  }
  const query = Object.assign(defaultQuery, req.query)
  // query.end_date = utils.minDateOrToday(query.end_date, utils.getSiteParams(locationId).status.end_date)

  return db.getSensorData(query)
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

app.get('/sensor-hourly/', (req, res, next) => {
  const locationId = req.query.location_id || 'UML'

  const defaultQuery = {
    location_id: locationId,
    ...utils.getSiteParams(locationId).status
  }
  const query = Object.assign(defaultQuery, req.query)
  query.end_date = utils.limitDateToToday(query.end_date)

  return db.getSensorHourlyData(query)
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

app.post('/sensor/', (req, res, next) => {
  console.log('received sensor data')
  if (!req.body) {
    return res.status(400).json({ status: 'error', error: { message: 'No data found in request' } })
  } else if (!req.body.secret || req.body.secret !== config.api.sensor.secret) {
    return res.status(401).json({ status: 'error', error: { message: 'Unauthorized request, secret is missing or incorrect' } })
  }
  const data = {
    location_id: 'UML',
    timestamp: req.body.timestamp,
    temperature_degc: req.body.data.Temperature_degC,
    specificconductance_us_cm: req.body.data.SpecificConductance_uS_cm,
    depth_m: req.body.data.Depth_m,
    battery_v: req.body.data.Battery_V,
    turbidity_ntu: req.body.data.Turbidity_NTU,
    nh3_ammonia_mg_l: req.body.data.NH3_Ammonia_mg_L,
    chlorophyll_ug_l: req.body.data.Chlorophyll_ug_L,
    chlorophyll_rfu: req.body.data.Chlorophyll_RFU,
    odo_pcsat: req.body.data.ODO_pcSat,
    odo_mg_l: req.body.data.ODO_mg_L,
    bga_pc_ug_l: req.body.data.BGA_PC_ug_L
  }
  return db.saveSensor(data)
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

app.get('/run-estimate/', (req, res, next) => {
  const locationId = req.query.location_id || 'UML'

  const defaultQuery = {
    location_id: locationId,
    ...utils.getSiteParams(locationId).run
  }
  const query = Object.assign(defaultQuery, req.query)
  query.end_date = utils.limitDateToToday(query.end_date)

  return db.getDailyRunEstimate(query)
    .then(result => res.status(200).json({ status: 'ok', data: result }))
    .catch(next)
})

// error handler
function errorHandler (err, req, res, next) { // eslint-disable-line no-unused-vars
  console.error(err.toString())
  return res.status(500).json({
    status: 'error',
    error: {
      data: err,
      message: err.toString()
    }
  })
}
app.use(errorHandler)

// start server
app.listen(config.api.port, () => {
  console.log('listening port=%d', config.api.port)
})
