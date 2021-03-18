#!/bin/bash

########
# This script takes a zip file containing the input data
# required to build all of the SEDA exporer data.  It
# renames all of the files accordingly and outputs it
# into the source directory.
########

if [ $# -eq 0 ]
  then
    echo "No zip file provided"
    exit 1
fi

# cleanup
rm -rf source
mkdir -p source

# extract source data and place accordingly
unzip -o $1 -d source

# rename similar places files
mv source/similar-places/SchoolMatch.csv source/schools_similar.csv
mv source/similar-places/DistrictMatch.csv source/districts_similar.csv
mv source/similar-places/CountyMatch.csv source/counties_similar.csv
rm -rf source/similar-places
echo "successfully prepared similar places"

# rename associated variable files
mv source/state\ level\ variables.csv source/states_cov.csv
mv source/county\ level\ variables.csv source/counties_cov.csv
mv source/district\ level\ variables.csv source/districts_cov.csv
mv source/school\ level\ variables.csv source/schools_cov.csv
echo "successfully prepared associated variables"

# rename flags data
mv source/flags/spedidea\ flag.csv source/flag_sped.csv
mv source/flags/lep\ flag.csv source/flag_lep.csv
mv source/flags/gifted\ flag.csv source/flag_gifted.csv
rm -rf source/flags
echo "successfully prepared flags"

# discoveries data
mv source/discoveries/*.csv source
rm -rf source/discoveries
echo "successfully prepared discoveries data"

# rename SEDA data
for FILE in source/SEDA_county*.csv; do
    mv $FILE source/SEDA_counties.csv
done

for FILE in source/SEDA_geodist*.csv; do
    mv $FILE source/SEDA_districts.csv
done

for FILE in source/SEDA_state*.csv; do
    mv $FILE source/SEDA_states.csv
done

for FILE in source/SEDA_school*.csv; do
    mv $FILE source/SEDA_schools.csv
done
echo "successfully prepared SEDA data files"