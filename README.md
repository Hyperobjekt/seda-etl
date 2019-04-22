# SEDA ETL Pipeline

Creates tilesets and data used for the SEDA project

## Getting Started

Clone this repository then use docker to build the image that is used for all tasks.

```
$: docker pull hyperobjekt/seda-etl
```

Once the image is built you can run any of the pipeline tasks outlined below.

## Pipeline Tasks

Use the `./run-task.sh` script via the docker image to run tasks:

```
$: docker run
    --volume ${PWD}:/App \
    --workdir="/App" \ 
    --env-file .env.local \ 
    --entrypoint /App/run-task.sh \
    hyperobjekt/seda-etl {TASK_NAME}
```

> Note: You must enter values for the variables in the `.env` file.  Copy the `.env` file to `.env.local`, enter values for the variables, and then specify the env file when running docker.

The following tasks are available:

  - `all`: make all of the targets listed below
  - `tiles`: creates tilesets for each region in `./build/tiles`
  - `geojson`: creates GeoJSON files for schools, districts, counties in `./build/geography`
  - `data`: creates master data files for schools, districts, counties in `./build`
  - `vars`: segments master csv files into individual variable csv files that are used for the scatterplot
  - `search`: creates data for search in `./build/search.csv` 
  - `deploy_tiles`: deploys tiles to mapbox
  - `deploy_search`: deploys search data to Algolia index
  - `deploy_vars`: deploys individual variable CSV files to S3

