# SEDA ETL Pipeline

Creates tilesets and data used for the SEDA project

## Getting Started

### 1. Pull the docker image

Clone this repository then use docker to build the image that is used for all tasks.

```
$: docker pull hyperobjekt/seda-etl
```

Once the image is built you can run any of the pipeline tasks outlined below.

### 2. Create an .env.local file

The `.env.local` file sets all of the required environment variables required to access 3rd party APIs and hosting services. The `.env` file should have the following variables

- `DATA_BUCKET`: S3 bucket name where source and build data are stored (e.g. edop-data-bucket)
- `EXPORT_DATA_BUCKET`: S3 bucket where the public data exports are deployed (e.g. e)
- `DATA_VERSION`: version of the data (e.g. 1.0.0)
- `AWS_ACCESS_ID`: AWS access id for S3 deploy / CloudFront Invalidation / ECS service updates
- `AWS_SECRET_KEY`: AWS secret key
- `BUILD_ID`: build id (dev or prod)
- `MAPBOX_USERNAME`: mapbox username for tileset deploy
- `MAPBOX_TOKEN`: mapbox token for tileset deploy
- `ALGOLIA_ID`: algolia id for search deploy
- `ALGOLIA_KEY`: algolia key for search deploy
- `CLOUDFRONT_ID`: id of the data cloudfront distribution for invalidation on deploy

## Building Source Data

Use the docker image to build from a source data zip file. The source data zip file should be structured as the [seda-source](https://drive.google.com/drive/u/0/folders/1WFnOImwJyyN25pNYWeeCqrHNqCxBn-ax) folder.

```
docker run
  --volume ${PWD}:/App \
  --env-file .env.local \
  hyperobjekt/seda-etl --file=/App/source-file.zip
```

**Optional:** it may be more convenient to alias this command if you use it often. Add the following to your `.bashrc` or `.zshrc`.

```
alias sedaetl="docker run --env-file .env.local -v ${PWD}:/App hyperobjekt/seda-etl"
```

then you can run a build using:

```
sedaetl --file=/App/source-file.zip
```

### Deploying

- Use the `--deploy` flag to the build command above if you would like to deploy static data to the S3 endpoints and tilesets to mapbox.
- Use the `--deploy-search` flag to the build command above if you would like to deploy search data to algolia

## Running Individual Pipeline Tasks

Run the docker image from an interactive shell to run individual pipeline tasks:

```
$: docker run \
  -it \
  --volume ${PWD}:/App \
  --workdir="/App" \
  --env-file .env.local \
  --entrypoint /bin/bash \
  hyperobjekt/seda-etl 
```

In the interactive shell, you can use the `./run-task.sh` script to run individual tasks:

Run `./run-task.sh help` to get a list of available tasks. A list of available tasks is here for convenience:

```
help                       : Print help
all                        : Build everything
tiles                      : Create mbtiles for all regions
geojson                    : Create GeoJSON files with data for all regions
data                       : Creates master data files used to populate search, tilesets, etc.
export_data                : create csv / geojson files split by state
scatterplot                : Create all individual var files used for scatterplots
search                     : Create data files containing data for search
clean                      : Remove files
deploy_all                 : Deploy all data to S3 / CloudFront endpoint
deploy_service             : Update pdf export service
deploy_tilesets            : Deploy the tilesets to mapbox using the upload API
deploy_export_data         : Deploy the csv / geojson exports
deploy_scatterplot         : Deploy scatterplot var files to S3 bucket
deploy_search              : Algolia deploy (WARNING: 100,000+ records, costs $$)
deploy_source_csv          : Deploy local source csv data to S3 bucket
deploy_source_geojson      : Deploy local source geojson data to S3 bucket
deploy_source_zip          : Deploy local source zip data to S3 bucket
deploy_similar             : Deploy similar locations csv to S3 and invalidate CloudFront cache
deploy_flagged             : Deploy school flags to S3 and invalidate CloudFront cache
```
