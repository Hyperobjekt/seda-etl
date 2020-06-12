#!/bin/bash

########
# This script takes a zip file containing the input data
# required to build all of the SEDA exporer data.  It
# renames all of the files accordingly and outputs it
# into the build/source_data directory.
########

if [ $# -eq 0 ]
  then
    echo "Must provide source data zip file"
    exit 1
fi

# cleanup
rm -rf build/source_data build/seda-source
mkdir -p build

# extract source data and place accordingly
unzip $1 -d build
mv build/seda-source/ build/source_data/

# rename similar places files
mv build/source_data/similar-places/SchoolMatch.csv build/source_data/schools_similar.csv
mv build/source_data/similar-places/DistrictMatch.csv build/source_data/districts_similar.csv
mv build/source_data/similar-places/CountyMatch.csv build/source_data/counties_similar.csv

# rename associated variable files
mv build/source_data/county\ level\ variables.csv build/source_data/counties_cov.csv
mv build/source_data/district\ level\ variables.csv build/source_data/districts_cov.csv
mv build/source_data/school\ level\ variables.csv build/source_data/schools_cov.csv
# mv build/source_data/state\ level\ variables.csv build/source_data/states_cov.csv

# rename flags data
mv build/source_data/flags/spedidea\ flag.csv build/source_data/flag_sped.csv
mv build/source_data/flags/lep\ flag.csv build/source_data/flag_lep.csv
mv build/source_data/flags/gifted\ flag.csv build/source_data/flag_gifted.csv

# discoveries data
mv build/source_data/discoveries/*.csv build/source_data
rm -rf build/source_data/discoveries