#!/bin/bash

# Docker entry point that recieves a filename to build,
# triggered on AWS batch by `utils/submit_jobs.py`.
#
# e.g. `python3 utils/submit_jobs.py data/demographics/block-groups.csv`
#   will start a docker container in AWS batch and run this script with
#   $1 = data/demographics/block-groups.csv
#
# This script determines which makefile is used to make the requested
# file, and also deploys it if needed.



# running locally in docker container, configure aws
if [[ -z "${AWS_ACCESS_ID}" ]]; then
    printf '%s\n' "Missing AWS_ACCESS_ID environment variable, could not configure AWS CLI." >&2
elif [[ -z "${AWS_SECRET_KEY}" ]]; then
    printf '%s\n' "Missing AWS_SECRET_KEY environment variable, could not configure AWS CLI." >&2
else
    aws configure set aws_access_key_id $AWS_ACCESS_ID
    aws configure set aws_secret_access_key $AWS_SECRET_KEY
    aws configure set default.region us-east-1
fi

if [[ $1 == *config* ]]; then
  printf '%s\n' "configured" >&2
else
  make $1
fi
