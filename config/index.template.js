module.exports = {
  api: {
    url: ''     // API URL
    port: 8000, // API listening port
    static: {
      videoWatch: '../video-watch/dist' // path to video-app
    }
  },
  db: {
    host: '',
    port: 5432,
    database: '',
    user: '',
    password: ''
  },
  videoService: {
    inDir: '',     // directory containing new videos
    saveDir: '',   // directory to save videos after processing
    locationIds: ['TEST', 'UML', 'WIN'], // location IDs to process
  },
  s3: {
    bucket: '', // S3 bucket name
    path: ''    // S3 videos path
    client: {
      maxAsyncS3: 20,                     // default
      s3RetryCount: 3,                    // default
      s3RetryDelay: 1000,                 // default
      multipartUploadThreshold: 20971520, // default (20 MB)
      multipartUploadSize: 15728640,      // default (15 MB)
      s3Options: {
        accessKeyId: '',     // S3 Access Key ID
        secretAccessKey: '', // S3 Secret Access Key
        region: ''           // default
      }
    }
  }
}