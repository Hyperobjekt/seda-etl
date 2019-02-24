# SEDA ETL Pipeline

Creates tilesets and data used for the SEDA project

## Getting Started

Clone this repository then use docker to build the image that is used for all tasks.

```
$: docker build . -t hyperobjekt/seda-etl
```

Once the image is built, launch it into a shell and run any of the make targets specified below.

> Note: You must enter values for the variables in the `.env` file.  Copy the `.env` file to `.env.local`, enter values for the variables, and then specify the env file when running docker.

```
$: docker run -it 
    --volume ${PWD}:/App \
    --workdir="/App" \ 
    --env-file .env.local \ 
    --entrypoint /bin/bash \
    hyperobjekt/seda-etl
```

If performing any AWS related tasks, run the config task to configure aws-cli with the credentials from your `.env.local` file.

```
$: ./run-task.sh config
```

## Pipeline Tasks

Use the`./run-task.sh` script to run any of the pipeline tasks. (e.g. `./run-task.sh all`)

The following make targets are available:

  - `all`: make all of the targets listed below
  - `tiles`: creates tilesets for each region in `./build/tiles`
  - `geojson`: creates GeoJSON files for schools, districts, counties in `./build/geography`
  - `data`: creates master data files for schools, districts, counties in `./build`
  - `search`: creates data for search in `./build/search.csv` 
  - `deploy_tiles`: deploys tiles to mapbox
  - `deploy_search`: deploys search data to Algolia index
  - `deploy_vars`: deploys individual variable CSV files to S3