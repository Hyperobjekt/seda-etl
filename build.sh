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

# running locally in docker container, configure aws
if [[ -z "${AWS_ACCESS_ID}" ]]; then
    printf '%s\n' "Missing AWS_ACCESS_ID environment variable, could not configure AWS CLI." >&2
    exit 1
elif [[ -z "${AWS_SECRET_KEY}" ]]; then
    printf '%s\n' "Missing AWS_SECRET_KEY environment variable, could not configure AWS CLI." >&2
    exit 1
else
    aws configure set aws_access_key_id $AWS_ACCESS_ID
    aws configure set aws_secret_access_key $AWS_SECRET_KEY
    aws configure set default.region us-east-1
fi

make clean
./scripts/prepare_source.sh $1
make s3 mapbox