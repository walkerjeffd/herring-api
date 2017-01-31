var Promise = require('bluebird'),
    path = require('path'),
    fs = require('fs'),
    ffprobe = Promise.promisify(require('fluent-ffmpeg').ffprobe),
    s3 = require('s3'),
    pg = require('pg'),
    moment = require('moment');

var SKIP_S3 = false;

var config = require('./config');

var s3Client = s3.createClient(config.s3.client);

var pool = new pg.Pool(config.db);

var readdir = Promise.promisify(fs.readdir),
    rename = Promise.promisify(fs.rename);

var getVideoMetadata = function (video) {
  console.log('getVideoMetadata("%s/%s")', video.location_id, video.filename);

  return ffprobe(video.filepath)
    .then(function (metadata) {
      var format = metadata.format;
      var filename = path.basename(format.filename);

      var timestring = filename.substr(2, 19);
      var start = moment(timestring, 'YYYY-MM-DD_HH-mm-ss');
      var end = moment(start).add(Math.round(format.duration), 's');

      video.filepath = format.filename;
      video.filename = filename;
      video.duration = format.duration;
      video.filesize = format.size;
      video.start_timestamp = start.toISOString();
      video.end_timestamp = end.toISOString();

      return video;
    });
}

var uploadFileToS3 = function (video) {
  console.log('uploadFileToS3("%s/%s")', video.location_id, video.filename);

  var filename = video.filename,
      bucket = config.s3.bucket,
      key = path.join(config.s3.path, video.location_id, filename);

  var params = {
    localFile: video.filepath,

    s3Params: {
      Bucket: bucket,
      Key: key,
      ACL: 'public-read'
    }
  };

  if (SKIP_S3) {
    console.log('uploadFileToS3("%s/%s"): skipping', video.location_id, filename);
    return video;
  }

  s3Client.s3.headObject({
      Bucket: bucket,
      Key: key
    }, function (err, data) {
      if (data) {
        console.log('uploadFileToS3("%s/%s"): Warning: file already exists on s3', video.location_id, filename);
      }
    });

  var uploader = s3Client.uploadFile(params);
  console.log('uploadFileToS3("%s/%s"): uploading', video.location_id, filename);

  return new Promise(function (resolve, reject) {
    uploader.on('error', function(err) {
      reject(err);
    });
    // uploader.on('progress', function() {
    //   console.log("progress", uploader.progressMd5Amount,
    //               uploader.progressAmount / uploader.progressTotal * 100);
    // });
    uploader.on('end', function() {
      console.log('uploadFileToS3("%s/%s"): done', video.location_id, filename);
      var url = s3.getPublicUrl(bucket, key);
      video.url = url;
      resolve(video);
    });
  })
}

var moveFileToSaveDir = function (video) {
  console.log('moveFileToSaveDir("%s/%s"): %s', video.location_id, video.filename, config.save_dir);
  var inPath = video.filepath,
      savePath = path.join(config.save_dir, video.location_id, video.filename);

  return rename(inPath, savePath)
    .then(function () {
      video.filepath = savePath;
      return video;
    });
}

var saveVideoToDb = function (video) {
  console.log('saveVideoToDb("%s/%s")', video.location_id, video.filename);

  var data = [
    video.url,
    video.filename,
    video.duration,
    video.filesize,
    video.start_timestamp,
    video.end_timestamp,
    video.location_id
  ];

  return new Promise(function (resolve, reject) {
    pool.connect(function (err, client, done) {
      if (err) {
        return reject(err);
      }

      var sql = 'INSERT INTO videos ' +
        '(url, filename, duration, filesize, start_timestamp, end_timestamp, location_id) ' +
        'VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *';

      client.query(sql, data, function (err, result) {
        done();

        if (err) {
          return reject(err);
        }

        return resolve(result.rows[0]);
      });
    });
  });
};

var processVideo = function (video) {
  console.log('processVideo("%s/%s"): %s', video.location_id, path.basename(video.filepath), video.filepath);
  return getVideoMetadata(video)
    .then(uploadFileToS3)
    .then(moveFileToSaveDir)
    .then(saveVideoToDb)
    .then(function (row) {
      video.db = row;
      console.log('processVideo("%s/%s"): done', video.location_id, video.filename);
      return video;
    });
}

var getLocationDb = function (location) {
  console.log('getLocationDb("%s")', location.id);
  return new Promise(function (resolve, reject) {
    pool.connect(function (err, client, done) {
      if (err) {
        return reject(err);
      }

      var sql = 'SELECT * FROM locations WHERE id=$1';

      client.query(sql, [location.id], function (err, result) {
        done();

        if (err) {
          return reject(err);
        }

        if (result.rows.length < 1) {
          return reject(new Error('Location ' + location.id + ' not found in database'));
        }

        return resolve(result.rows[0]);
      });
    });
  });
}

var processLocationDir = function (locationId) {
  console.log('processLocationDir("%s")', locationId);
  var location = {
    id: locationId
  };

  return getLocationDb(location)
    .then(function (locationDb) {
      location.db = locationDb;
      location.dir = path.join(config.in_dir, location.id);

      return readdir(location.dir)
        .then(function (files) {
          console.log('processLocationDir("%s"): processing %d files', location.id, files.length);

          location.files = files.map(function (filename) {
            return path.join(location.dir, filename);
          });

          return location;
        });
    })
    .then(function (location) {
      var videos = location.files.map(function (filepath) {
        return {
          location_id: location.db.id,
          filepath: filepath,
          filename: path.basename(filepath)
        };
      });
      return Promise.mapSeries(videos, processVideo);
    })
    .then(function (videos) {
      location.videos = videos;
      return location;
    })
    .then(function (location) {
      console.log('processLocationDir("%s"): done', location.id);
    });
}

console.log('video-service/process.js: start: %s', new Date());

Promise.mapSeries(config.locationIds, processLocationDir)
  .then(function (locations) {
    process.exit(0);
  })
  .catch(function (err) {
    console.log(err);
    process.exit(1);
  });
