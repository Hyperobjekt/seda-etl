"use strict";

const fs = require("fs");
const cmdArgs = process.argv.slice(2);
const path = require("path");
const csv = require("csv-parser");
const entries = {};
let count = 0;

if (cmdArgs.length !== 1 && cmdArgs.length !== 2) {
  console.error(
    "ERROR: must provide source file, with optional output file",
    cmdArgs.length
  );
  process.exit(1);
}

const inFile = cmdArgs[0];
const outFile = cmdArgs.length === 2 ? cmdArgs[1] : null;

var readStream = fs.createReadStream(inFile);

const adjustLocation = (row, count) => {
  const result = { id: row["id"], lat: row["lat"], lon: row["lon"] };
  if (count === 1) result["lat"] = row["lat"] - 0.003;
  else if (count === 2) result["lat"] = row["lat"] + 0.003;
  else if (count === 3) result["lon"] = row["lon"] - 0.003;
  else if (count === 4) result["lon"] = row["lon"] + 0.003;
  return Object.assign({}, row, result);
};

const processRow = (row) => {
  const key = "" + row["lat"] + row["lon"];
  if (!entries.hasOwnProperty(key)) {
    entries[key] = 0;
    return row;
  }
  entries[key]++;
  count++;
  // console.warn(`duplicate ${entries[key]} found for ${row["id"]} (${key})`);
  return adjustLocation(row, entries[key]);
};

const mapValues = ({ header, index, value }) => {
  const floatCols = ["lat", "lon"];
  if (floatCols.indexOf(header) > -1) return parseFloat(value);
  return value;
};

// stream to stdout if no outfile provided
const out = outFile ? fs.createWriteStream(outFile) : process.stdout;

let headerKeys = null;

readStream
  .pipe(
    csv({
      mapValues,
    })
  )
  .on("headers", (headers) => {
    headerKeys = headers
    out.write(headers.join(",") + "\n");
  })
  .on("data", (data) => {  
    const row = processRow(data);
    out.write(
      headerKeys
        .map((k) => (["name", "city"].indexOf(k) > -1 ? `"${row[k]}"` : row[k]))
        .join(",") + "\n"
    );
  })
  .on("end", () => {
    console.warn(`adjusted lat/lon for ${count} overlapping schools`)
  });
