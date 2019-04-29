# available region types
geo_types = counties districts schools

# id field names for various regions
counties_id = countyid
districts_id = leaidC
schools_id = ncessch

# master data file names
counties_main = SEDA_county_pool_GCS_v30.csv
districts_main = SEDA_geodist_pool_GCS_v30.csv
schools_main = SEDA_school_pool_GCS_v30_latlong_city.csv

# metrics available at the county level with paired demographics
counties_metrics = avg grd coh ses seg pov sz
counties_dems = all w a b p f h m mf np pn wa wb wh fl

# metrics available at the school level with paired demographics
schools_metrics = pct avg grd coh sz
schools_dems = all w a h b i fl rl frl

# variables to pull into individual files
counties_vars = $(foreach m, $(counties_metrics), $(foreach d, $(counties_dems), $(d)_$(m)))
districts_vars = $(counties_vars)
schools_vars = $(foreach m, $(schools_metrics), $(foreach d, $(schools_dems), $(d)_$(m)))

# variables containing place meta data
meta_vars = id,name,lat,lon,all_sz

# meta data file targets
meta_files = $(foreach t, $(geo_types), build/scatterplot/meta/$(t).csv)

# individual files for all regions containing id,{VAR_NAME}
individual_var_files = $(foreach g,$(geo_types),$(foreach v,$($(g)_vars),build/scatterplot/$(g)/$(v).csv))

# files to create reduced pairs for
reduced_pair_files = build/scatterplot/schools/reduced/schools.csv

# use this build ID if one is not set in the environment variables
BUILD_ID?=dev
SOURCE_VERSION=0.0.1

# For comma-delimited list
null :=
space := $(null) $(null)
comma := ,

.PHONY: tiles data search geojson scatterplot deploy_search deploy_tilesets deploy_scatterplot deploy_all

### all                        : Build everything!
all: geojson tiles data search scatterplot

### deploy_all                 : Deploy everything, except search because that costs money through Algolia
deploy_all: deploy_tilesets deploy_scatterplot

### tiles:                     : Create mbtiles for all regions
tiles: $(foreach t, $(geo_types), build/tiles/$(t).mbtiles)

### deploy_tilesets            : Deploy the tilesets to mapbox using the upload API
deploy_tilesets:
	for f in build/tiles/*.mbtiles; do node ./scripts/deploy_tilesets.js $$f $$(basename "$${f%.*}")-$(BUILD_ID); done

### geojson                    : Create GeoJSON files with data for all regions
geojson: $(foreach t, $(geo_types), build/geography/$(t).geojson)

### data                       : Creates master data files used to populate search, tilesets, etc.
data: $(foreach t, $(geo_types), build/$(t).csv)

### deploy_public              : Deploys master csv data and geojson files split by state 
deploy_public:
	python3 scripts/deploy_public.py

### scatterplot                : Create all individual var files used for scatterplots
scatterplot: $(meta_files) $(individual_var_files) $(reduced_pair_files)
	find build/scatterplot/ -type f -size 0 -delete

### deploy_scatterplot         : Deploy scatterplot var files to S3 bucket 
deploy_scatterplot:
	aws s3 cp ./build/scatterplot s3://$(DATA_BUCKET)/build/$(BUILD_ID)/scatterplot \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000

### search                    : Create data files containing data for search
search:  $(foreach t, $(geo_types), build/search/$(t).csv)

### deploy_search             : Deploy the search data to Algolia (WARNING: 100,000+ records, this will cost $$)
deploy_search:
	python3 scripts/deploy_search.py ./build/search/counties.csv counties
	python3 scripts/deploy_search.py ./build/search/districts.csv districts
	python3 scripts/deploy_search.py ./build/search/schools.csv schools

### clean                      : Remove files
clean:
	rm -rf build


######
### CHOROPLETH TILES
######
### `make tiles`
### Creates the .mbtiles files for the tilesets, populated with data
######

# cols that get converted to float in the tileset
numeric_cols = $(counties_vars) $(schools_vars)
# attribute type flags for tippecanoe
attr_types = --attribute-type=id:string $(foreach t, $(numeric_cols), --attribute-type=$(t):float)
# tippecanoe options that apply to all tilesets
tippecanoe_default_opts = --maximum-tile-bytes=500000 --minimum-zoom=2
# tippecanoe options that apply to polygon layers
tippecanoe_poly_opts =  $(tippecanoe_default_opts) $(attr_types) --empty-csv-columns-are-null --use-attribute-for-id=fid --simplification=10 --coalesce-densest-as-needed --maximum-zoom=12 --detect-shared-borders --no-tile-stats --force
# tippecanoe options that apply to point layers
tippecanoe_point_opts = $(tippecanoe_default_opts) $(attr_types) --empty-csv-columns-are-null --generate-ids -zg --drop-densest-as-needed --extend-zooms-if-still-dropping --no-tile-stats --force

### Create mbtiles for a region with polygon features (counties, districts)
build/tiles/%.mbtiles: build/geography/%.geojson
	mkdir -p $(dir $@)
	tippecanoe -L $*:$< $(tippecanoe_poly_opts) -o $@

### Create mbtiles for schools (points)
build/tiles/schools.mbtiles: build/geography/schools.geojson
	mkdir -p $(dir $@)
	tippecanoe -L schools:$< $(tippecanoe_point_opts) -o $@



######
### GEOJSON
######
### `make geojson`
### Creates GeoJSON containing all of the data that is used in tilesets.
######

census_ftp_base = ftp://ftp2.census.gov/geo/tiger/GENZ2010/
counties-pattern = gz_*_*_050_*_500k.zip
counties-geoid = "this.properties.id = this.properties.STATE + this.properties.COUNTY"
counties-name = "this.properties.name = this.properties.NAME + ' ' + this.properties.LSAD"
districts-geoid = "this.properties.id = this.properties.GEOID"
districts-name = "this.properties.name = this.properties.NAME"

### Creates counties geojson w/ GEOID and name (no data)
build/geography/base/counties.geojson:
	mkdir -p $(dir $@)
	wget --no-use-server-timestamps -np -nd -r -P $(dir $@)tmp -A '$(counties-pattern)' $(census_ftp_base)
	for f in $(dir $@)tmp/*.zip; do unzip -d $(dir $@)tmp $$f; done
	mapshaper $(dir $@)tmp/*.shp combine-files \
		-each $(counties-geoid) \
		-each $(counties-name) \
		-filter-fields id,name \
		-o - combine-layers format=geojson > $@
	rm -rf $(dir $@)tmp

### Creates districts geojson w/ GEOID and name (no data)
build/geography/base/districts.geojson:
	mkdir -p $(dir $@)
	aws s3 cp s3://$(DATA_BUCKET)/source/$(DATA_VERSION)/SEDA_shapefiles_v21.zip $(dir $@)
	unzip -d $(dir $@)tmp $(dir $@)SEDA_shapefiles_v21.zip
	mapshaper $(dir $@)tmp/*.shp combine-files \
		-each $(districts-geoid) \
		-each $(districts-name) \
		-filter-fields id,name \
		-uniq id \
		-o - combine-layers format=geojson > $@
	rm -rf $(dir $@)tmp

### Create data file with only data for tilesets
build/geography/data/%.csv: build/%.csv
	mkdir -p $(dir $@)
	csvcut --not-columns lat,lon,state_name,state $< > $@

### Creates counties / districts geojson, populated with data
build/geography/%.geojson: build/geography/base/%.geojson build/geography/data/%.csv
	mkdir -p $(dir $@)
	cat $< | \
	tippecanoe-json-tool -e id | \
	LC_ALL=C sort | \
	tippecanoe-json-tool --empty-csv-columns-are-null --wrap --csv=$(word 2,$^) > $@

### Creates schools geojson file with data
build/geography/schools.geojson: build/schools.csv
	mkdir -p $(dir $@)
	csvcut --not-columns state,state_name,fid,city $< | \
	csv2geojson --lat lat --lon lon | \
	mapshaper - -o $@ combine-layers format=geojson 



######
### DATA
######
### `make data`
### build master data files containing all data for each region type.
######

geojson_label_cmd = node --max_old_space_size=4096 $$(which geojson-polygon-labels)

### Build master data file for counties / districts from center points and dictionary
build/%.csv: build/ids/%.csv build/centers/%.csv build/from_dict/%.csv
	mkdir -p $(dir $@)
	csvjoin -c id --left --no-inference $^ | \
	python3 scripts/clean_data.py $* > $@

### Build master data file for schools from dictionary
build/schools.csv: build/from_dict/schools.csv
	mkdir -p $(dir $@)
	cat $< | \
	python3 scripts/clean_data.py schools > $@

### Extracts data based on the dictionary file for counties / districts / schools
.SECONDEXPANSION:
build/from_dict/%.csv: build/source_data/$$*_cov.csv build/source_data/$$($$*_main)
	mkdir -p $(dir $@)
	cat dictionaries/$*_dictionary.csv | \
	python3 scripts/create_data_from_dictionary.py $(dir $<) > $@

### Build centers data with lat / lon center point and name for counties / districts
build/centers/%.csv: build/geography/base/%.geojson
	mkdir -p $(dir $@)
	$(geojson_label_cmd) --style largest $< | \
	in2csv --format json -k features | \
	csvcut -c properties/id,properties/name,geometry/coordinates/0,geometry/coordinates/1 | \
	sed '1s/.*/id,name,lon,lat/' | \
	python3 scripts/clean_data.py $* > $@

### Builds a csv file containing only IDs for the given region, used for joins
.SECONDEXPANSION:
build/ids/%.csv: build/source_data/$$($$*_main)
	mkdir -p $(dir $@)
	csvcut -e windows-1251 -c $($*_id) build/source_data/$($*_main) | \
	csvsort -c $($*_id) --no-inference | \
	uniq | \
	sed '1s/.*/id/' > $@



######
### SOURCE DATA
######
### handles fetching and deploying source data
######

### Fetch source data from S3 bucket
build/source_data/%.csv:
	mkdir -p $(dir $@)
	wget -qO- http://$(DATA_BUCKET).s3-website-us-east-1.amazonaws.com/source/$(DATA_VERSION)/$*.csv.gz | \
	gunzip -c - > $@

### Deploy local source data to S3 bucket
deploy_source_data:
	for f in source_data/*.csv; do gzip $$f; done
	for f in source_data/*.geojson; do gzip $$f; done
	for f in source_data/*.gz; do aws s3 cp $$f s3://$(DATA_BUCKET)/source/$(SOURCE_VERSION)/$$(basename $$f) --acl=public-read; done



######
### SCATTERPLOT
######
### `make scatterplot`
### Takes each of the variables for each region (e.g. counties_vars)
### and generate csv files mapping id : variable value.  These files
### are used for scatterplots.  Each variable is loaded as needed.
### Also creates a base file to use on initial load, with names, lat, lon, etc.
######

# point radius used for for reducing points
point_radius = 0.01

### Create the meta data file for districts / counties
build/scatterplot/meta/%.csv: build/%.csv
	mkdir -p $(dir $@)
	cat $< | csvcut -c $(meta_vars) > $@

### Create the master meta data file for schools, and also split by state
build/scatterplot/meta/schools.csv: build/schools.csv
	mkdir -p $(dir $@)
	csvcut -c $(meta_vars) $< > $@
	xsv partition -p 2 id $(dir $@)schools $@

### Create the single variable file for districts (e.g. all_avg)
### NOTE: returns true even on fail when the data var is unavailable
###       so it doesn't break the build chain
build/scatterplot/districts/%.csv: build/districts.csv
	mkdir -p $(dir $@)
	csvcut -c id,$* $< > $@ || true

### Create the single variable file for counties (e.g. all_avg)
### NOTE: returns true even on fail when the data var is unavailable
###       so it doesn't break the build chain
build/scatterplot/counties/%.csv: build/counties.csv
	mkdir -p $(dir $@)
	csvcut -c id,$* $< > $@ || true

### Create the single variable file for schools and also split by state
### NOTE: returns true even on fail when the data var is unavailable
###       so it doesn't break the build chain
build/scatterplot/schools/%.csv: build/schools.csv
	mkdir -p $(dir $@)
	csvcut -c id,$* $< > $@ || true
	xsv partition --filename {}/$*.csv --prefix-length 2 id $(dir $@) $@ || true

### Create reduced school data sets for each variable pair based on a point radius
build/scatterplot/schools/reduced/schools.csv: build/schools.csv
	mkdir -p $(dir $@)
	python3 scripts/create_pairs.py schools $(point_radius) > $@



######
### SEARCH
######
### Generated search file contains all counties, districts, and schools
### with their name, latitude, longitude, and three key metrics.
### The search file is deployed to Algolia for indexing.
######

# columns to extract for search
search_cols = id,name,state_name,lat,lon,all_sz

### Create search data for districts / counties
build/search/%.csv: build/%.csv
	mkdir -p $(dir $@)
	csvcut -c $(search_cols) $< > $@

### Create search data for schools (includes city name)
build/search/schools.csv: build/schools.csv
	mkdir -p $(dir $@)
	csvcut -c $(search_cols),city $< > $@

