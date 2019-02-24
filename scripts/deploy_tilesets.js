const AWS = require('aws-sdk');
const axios = require('axios');
const fs = require('fs');

const username = process.env.MAPBOX_USERNAME;
const mbToken = process.env.MAPBOX_TOKEN;

const mbCredUrl = `https://api.mapbox.com/uploads/v1/${username}/credentials?access_token=${mbToken}`;
const mbUploadUrl = `https://api.mapbox.com/uploads/v1/${username}?access_token=${mbToken}`;

const completeUpload = function (config, name) {
  const headers = {
    "Content-Type": "application/json",
    "Cache-Control": "no-cache"
  };
  const body = {
    "url": `http://${config.data.bucket}.s3.amazonaws.com/${config.data.key}`,
    "tileset": `${username}.${name}`,
    "name": name
  };
  return axios.post(mbUploadUrl, body, { headers })
    .then(function(success) {
      console.log(`upload successful, mapbox processing may take several minutes. Upload id: ${success.data.id}`)
    })
    .catch(function (err) {
      console.log(err)
    })
}

const uploadToS3 = function (filepath, config, name) {
  console.log(`starting upload of ${name}`);
  fs.readFile(filepath, function(err, filedata) {
    if (err) throw err; // Something went wrong!
    var params = {
      Bucket: config.data.bucket,
      Key: config.data.key,
      Body: filedata,
    };
    let s3bucket = new AWS.S3();
    // 2. Upload file to s3 bucket
    s3bucket.upload(params, function(err, data) {
      if (err) throw err; // Something went wrong!
      console.log(`finished upload of ${name}`);
      completeUpload(config, name)
    });
  });
}

const deployTileset = function (filepath, name) {
  // 1. Get credentials for s3 bucket
  axios.post(mbCredUrl)
    .then(function (config) {
      AWS.config.update({
        region: "us-east-1",
        credentials: new AWS.Credentials(
          config.data.accessKeyId, 
          config.data.secretAccessKey,
          config.data.sessionToken
        )
      });
      uploadToS3(filepath, config, name);
    })
    .catch(function (err) {
      console.log(err)
    });
}

const filepath = process.argv[2];
const tileset_name = process.argv[3];

deployTileset(filepath, tileset_name);