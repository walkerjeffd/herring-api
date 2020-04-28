Herring Video Count API
=======================================

Jeffrey D Walker, PhD
[Walker Environmental Research, LLC](http://walkerenvres.com)

## Configuration

Copy server configuration template and set parameters. See README files in each component folder for details.

```bash
cp config/index.template.js config/index.js   # copy config template
nano config/index.js                          # edit config
```

## API

See `./api/README.md` for instructions.

## Video Processing Service

The video processing service (`./video-service`) processes new videos as they are uploaded via FTP.

Install [ffmpeg/ffprobe](https://ffmpeg.org/) for video conversions.

See `./video-service/README.md` for instructions.

## R Report

See `./r/README.md` for instructions.

```
cd r/
Rscript video-report.R # -> r/pdf/video-<YEAR>-<LOCATION_ID>.pdf
```



## Configuration

See `/config/index.template.js`

```js
{
  api: {
    port: 8000,                          // api listening port
    maxCount: 300,                       // max count for auto-flagging
    static: {
      // paths to static folders containing app builds, pdfs, datasets, etc
      videoWatch: '../video-watch/dist',
      videoStatus: '../video-status/dist',
      visTemp: '../vis-temp/dist',
      reports: '../r/pdf'
    },
    logFile: '/path/to/api-access.log'   // absolute path to log file
  },
  ...
}
```

## Run Development Server

```
# sudo ufw allow <config.api.port>     # open port, if necessary
npm start
```

## Run Production Server Using pm2

Set up configuration file

```
cd ../pm2
cp herring.template.json herring.json
nano herring.json    # set log file paths
```

Load and save pm2 configuration

```
cd ..
pm2 start ./pm2/herring.json
pm2 save
```

## Responses

All responses follow the general format:

```json
{
  "status": "ok"|"error",
  "data": { ... },         // if ok
  "error": {               // if error
    "data": { ... },
    "message": <text>
  }
}
```

## Endpoints

```js
GET  /static  // static builds
GET  /www     // static webpages
GET  /reports // static reports (r/pdf)
GET  /dataset // static datasets (r/csv)

GET  /video   // get random video to watch
GET  /videos  // get all videos for admin page
GET  /status  // get count status
POST /count   // submit count
```

### `/video`

**Query Parameters**

Limit random sample to subset of entire collection.

```js
?id=<boolean>                              // first video of session?
?id=<videos.id::int>                       // specific video
?date=<videos.start_timestamp::yyyy-mm-dd> // date recorded
?location=<locations.id::text>             // location id
```

**Response**

Returns array of video objects with length 0 or 1. Array has length of 0 if no videos are available based on query parameters.

```json
{
  "status": "ok",
  "data": [{
    "id": <int>,
    "created_at": <timestamp utc>,
    "url": <url>,
    "url_webm": <url>,
    "filename": <filename>,
    "duration": <real>,
    "filesize": <int>,
    "start_timestamp": <timestamp utc>,
    "end_timestamp": <timestamp utc>,
    "location_id": <text>,
    "flagged": <boolean>
  }]
}
```

### `/videos`

**Query Parameters**

Limit to subset of entire collection.

```js
?location=<locations.id::text>             // location id
```

**Response**

Returns array of video objects. Array has length of 0 if no videos are available based on query parameters.

```json
{
  "status": "ok",
  "data": [{
    "id": <int>,
    "created_at": <timestamp utc>,
    "url": <url>,
    "url_webm": <url>,
    "filename": <filename>,
    "duration": <real>,
    "filesize": <int>,
    "start_timestamp": <timestamp utc>,
    "end_timestamp": <timestamp utc>,
    "location_id": <text>,
    "flagged": <boolean>
  }]
}
```

### `/status`

**Query Parameters**

None

**Response**

Returns object containing `videos` and `counts`.

```json
{
  "status": "ok",
  "data": {
    "videos": {
      "summary": {
        "n": <int>,        // total videos available
        "n_watched": <int> // number of videos with at least one count
      }
    },
    "counts": {
      "summary": {
        "n": <int>,   // total number of counts
        "sum": <int>  // total number of fish counted
      },
      "daily": [
        // daily time series of counts by day
        {
          "date": <timestamp>, // date count submitted
          "n": <int>,          // number of counts
          "sum": <int>         // total number of fish counted
        },
        ...
      ]
    }
  }
}
```


### `/count`

**Query Parameters**

None

**Request**

Request body in json format

```json
{
  "video_id": <int>,   // references video.id
  "count": <int>,      // number of fish counted
  "comment": "<text>", // comment about video
  "session": "<uuid>"  // session id (UUID) generated by client
}
```

**Response**

Returns new count object in json format.

```json
{
  "status": "ok",
  "data": [
    {
      "id": <int>,
      "created_at": <timestamp utc>,
      "video_id": <int>,
      "session": <uuid text>,
      "count": <int>,
      "comment": <text>,
      "flagged": <bool>
    }
  ]
}
```
