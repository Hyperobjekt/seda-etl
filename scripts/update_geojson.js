'use strict';

const fs = require('fs');
const JSONStream = require('JSONStream');
const cmdArgs = process.argv.slice(2);
const path = require('path');
const dissolve = require('./dissolve_features.js');

if (cmdArgs.length !== 3) {
  console.error('ERROR: must provide region, input file, output file');
  process.exit(1);
}

const region = cmdArgs[0];
const inFile = cmdArgs[1];
const outFile = cmdArgs[2];

// attribute updates for provided identifiers
const UPDATES = {
  '46113': {
    id: '46102',
    name: 'Oglala Lakota County'
  },
  '4665460': {
    name: 'Oglala Lakota County 65-1'
  },
  '4703810': {
    id: '4700148',
    name: 'Shelby County'
  }
}

const UPDATE_KEYS = Object.keys(UPDATES);

const updateFeature = (feature) => {
  if (UPDATE_KEYS.indexOf(feature.properties.id) > -1) {
    const updates = UPDATES[feature.properties.id]
    console.log(`updating ${feature.properties.name} to ${updates.name}`)
    feature.properties = Object.assign(feature.properties, updates);
  }
  return feature;
}

const updateDataAndGeo = (feature) => {
  feature = updateFeature(feature);
  return dissolve.dissolveFeatures(feature)
}

const streamParse = JSONStream.parse('features.*', updateDataAndGeo)
const out = fs.createWriteStream(outFile);

fs.createReadStream(inFile)
  .pipe(streamParse)
  .pipe(JSONStream.stringify())
  .pipe(out);
