var fs = require('fs'),
    path = require('path'),
    express = require('express'),
    morgan = require('morgan'),
    bodyParser = require('body-parser');

var config = require('../config'),
    db = require('./db');

var app = express();

// create a write stream (in append mode)
var accessLogStream = fs.createWriteStream(path.join(__dirname, 'access.log'), {flags: 'a'})

// logging
var logFormat = ':date[iso] :remote-addr :remote-user :method :url HTTP/:http-version :status :res[content-length] - :response-time ms';
app.use(morgan(logFormat, {stream: accessLogStream}));

// body parser (json only)
app.use(bodyParser.json());

// allow CORS
var allowCrossDomain = function(req, res, next) {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  next();
};
app.use(allowCrossDomain);

// paths to app builds
app.use('/static/video-watch', express.static(config.api.static.videoWatch));
app.use('/static/video-status', express.static(config.api.static.videoStatus));
app.use('/static/vis-temp', express.static(config.api.static.visTemp));

// endpoints
app.get('/status/', function (req, res, next) {
  db.getStatus()
    .then(function (result) {
      return res.status(200).json({status: 'ok', data: result});
    })
    .catch(next)
});

app.get('/video/', function (req, res, next) {
  db.getVideo(req.query)
    .then(function (result) {
      return res.status(200).json({status: 'ok', data: result});
    })
    .catch(next);
});

app.post('/count/', function (req, res, next) {
  db.saveCount(req.body)
    .then(function (result) {
      return res.status(201).json({status: 'ok', data: result});
    })
    .catch(next)
});

// error handler
function errorHandler (err, req, res, next) {
  return res.status(500).json({
    status: 'error',
    error: {
      data: err,
      message: err.toString()
    }
  });
}
app.use(errorHandler);

// start server
app.listen(config.api.port, function () {
  console.log('started:port=%d', config.api.port);
});
