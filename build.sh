#!/bin/bash

########
# This script takes a zip file containing the input data
# required to build all of the SEDA exporer data.  It
# renames all of the files accordingly and outputs it
# into the build/source_data directory.
########

SOURCE_FILE=""
SHOULD_DEPLOY=0
SHOULD_DEPLOY_SEARCH=0
SHOULD_BUILD_DATA=2
SHOULD_BUILD_TILES=2
SHOULD_BUILD_SEARCH=2
SHOULD_CLEAN=1
OTHER_ARGUMENTS=()
PREPARE_ONLY=0

# Loop through arguments and process them
for arg in "$@"
do
    case $arg in
        --deploy)
        SHOULD_DEPLOY=1
        shift # Remove --deploy from processing
        ;;
        --no-clean)
        SHOULD_CLEAN=0
        shift # Remove --deploy from processing
        ;;
        --search)
        SHOULD_BUILD_SEARCH=1
        SHOULD_DEPLOY_SEARCH=1
        shift # Remove --search from processing
        ;;
        --data)
        SHOULD_BUILD_DATA=1
        shift # Remove --data from processing
        ;;
        --tiles)
        SHOULD_BUILD_TILES=1
        shift # Remove --tiles from processing
        ;;
        --prepare-only)
        PREPARE_ONLY=1
        shift # Remove --prepare-only from processing
        ;;
        -f=*|--file=*)
        SOURCE_FILE="${arg#*=}"
        shift # Remove --file= from processing
        ;;
        *)
        OTHER_ARGUMENTS+=("$1")
        shift # Remove generic argument from processing
        ;;
    esac
done

# clean existing build
if [[ $SHOULD_CLEAN -eq 1 ]]; then
    make clean
fi

if [[ $SOURCE_FILE != "" ]]; then
    # load the source data
    ./scripts/prepare_source.sh $SOURCE_FILE
fi

# Determine which pieces to build
if [[ $PREPARE_ONLY -eq 0 ]]; then
    if [[ $SHOULD_BUILD_DATA -eq 2 && $SHOULD_BUILD_TILES -eq 2 && $SHOULD_BUILD_SEARCH -eq 2 ]]; then
        ## build everything if no specific flags are set
        make all
        # update variables for all build types so they deploy if --deploy is set
        SHOULD_BUILD_DATA=1
        SHOULD_BUILD_TILES=1
        SHOULD_BUILD_SEARCH=1
    else
        if [[ $SHOULD_BUILD_DATA -eq 1 ]]; then
            make csv
        fi
        if [[ $SHOULD_BUILD_TILES -eq 1 ]]; then
            make tiles
        fi
        if [[ $SHOULD_BUILD_SEARCH -eq 1 ]]; then
            make search
        fi
    fi
fi

# Deploy the data that was built
if [[ $SHOULD_DEPLOY -eq 1 ]]; then

    # Deploy data to S3 endpoint
    if [[ $SHOULD_BUILD_DATA -eq 1 ]]; then
        if [[ -z "${AWS_ACCESS_ID}" ]]; then
            printf '%s\n' "Missing AWS_ACCESS_ID environment variable, could not configure AWS CLI." >&2
            exit 1
        fi
        if [[ -z "${AWS_SECRET_KEY}" ]]; then
            printf '%s\n' "Missing AWS_SECRET_KEY environment variable, could not configure AWS CLI." >&2
            exit 1
        fi
        aws configure set aws_access_key_id $AWS_ACCESS_ID
        aws configure set aws_secret_access_key $AWS_SECRET_KEY
        aws configure set default.region us-east-1
        make deploy_s3
    fi

    # Deploy tilesets to mapbox
    if [[ $SHOULD_BUILD_TILES -eq 1 ]]; then
        if [[ -z "${MAPBOX_TOKEN}" ]]; then
            printf '%s\n' "Missing MAPBOX_TOKEN environment variable, required to deploy tilesets." >&2
            exit 1
        fi
        make deploy_tilesets
    fi

    # Deploy search to algolia if search and deploy flags are specified
    if [[ $SHOULD_DEPLOY_SEARCH -eq 1 ]]; then
        if [[ -z "${ALGOLIA_ID}" ]]; then
            printf '%s\n' "Missing ALGOLIA_ID environment variable, required to deploy search." >&2
            exit 1
        fi
        if [[ -z "${ALGOLIA_KEY}" ]]; then
            printf '%s\n' "Missing ALGOLIA_KEY environment variable, required to deploy search." >&2
            exit 1
        fi
        make deploy_search
    fi

fi


