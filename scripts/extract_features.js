'use strict';

const fs = require('fs');
const JSONStream = require('JSONStream');
const cmdArgs = process.argv.slice(2);
const path = require('path');

if (cmdArgs.length !== 3 && cmdArgs.length !== 2) {
  console.error('ERROR: must provide comma separated ids, input file, with optional output file', cmdArgs.length);
  process.exit(1);
}

const ids = cmdArgs[0].split(',');
const inFile = cmdArgs[1];
const outFile = cmdArgs.length === 3 ? cmdArgs[2] : null;

const collectFeatures = (feature) => {
  if (!feature || !feature.properties) return null;
  if (ids.indexOf(feature.properties.id) > -1) {
    return feature
  }
  return null;
}

const streamParse = JSONStream.parse('features.*', collectFeatures)

// stream to stdout if no outfile provided
const out = outFile ? fs.createWriteStream(outFile) : process.stdout;

fs.createReadStream(inFile)
  .pipe(streamParse)
  .pipe(JSONStream.stringify())
  .pipe(out);
