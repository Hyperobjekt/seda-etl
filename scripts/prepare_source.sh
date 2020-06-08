#!/bin/bash

########
# This script 

if [ $# -eq 0 ]
  then
    echo "Must provide source data zip file"
    exit 1
fi

mkdir -p build/source_data
unzip $1 -d build/source_data

# remove unused files
rm -f build/source_data/*.dta build/source_data/*.xlsx build/source_data/*.do build/source_data/*_v22.csv
rm -f build/source_data/*Erin\ F*.csv
rm -rf build/source_data/functions

# rename similar places files
mv build/source_data/SchoolMatch.csv build/source_data/schools_similar.csv
mv build/source_data/DistrictMatch.csv build/source_data/districts_similar.csv
mv build/source_data/CountyMatch.csv build/source_data/counties_similar.csv

# rename associated variable files
mv build/source_data/county\ level\ variables.csv build/source_data/counties_cov.csv
mv build/source_data/district\ level\ variables.csv build/source_data/districts_cov.csv
mv build/source_data/school\ level\ variables.csv build/source_data/schools_cov.csv

# rename flags data
mv build/source_data/spedidea\ flag.csv build/source_data/flag_sped.csv
mv build/source_data/lep\ flag.csv build/source_data/flag_lep.csv
mv build/source_data/gifted\ flag.csv build/source_data/flag_gifted.csv
