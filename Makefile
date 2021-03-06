# For comma-delimited list
null :=
space := $(null) $(null)
comma := ,
dot := .
hyphen := -

# available region types
geo_types = states counties districts schools

# id field names for various regions
states_id = fips
counties_id = sedacounty
districts_id = sedalea
schools_id = sedasch

# master data file names
states_main = SEDA_states.csv
counties_main = SEDA_counties.csv
districts_main = SEDA_districts.csv
schools_main = SEDA_schools.csv

# margin of error var names (without demographic)
suffix_moe = avg_e grd_e coh_e

# metrics available at the grouped level (states, counties, districts) with paired demographics
group_metrics = avg grd coh ses seg min
group_dems = all w a b p f h i m mf np pn wa wb wh wi
group_data_vars = $(foreach m, $(group_metrics), $(foreach d, $(group_dems), $(d)_$(m)))
group_data_moe = $(foreach m, $(suffix_moe), $(foreach d, $(group_dems), $(d)_$(m)))
# comma separate vars for csvkit arguments
group_data_vars_comma = $(subst $(space),$(comma),$(strip $(group_data_vars)))
group_error_vars = $(subst $(space),$(comma),$(strip $(group_data_moe)))

# metrics available at the school level with paired demographics
schools_metrics = avg grd coh frl
schools_dems = all
schools_data_vars = $(foreach m, $(schools_metrics), $(foreach d, $(schools_dems), $(d)_$(m)))
schools_moe = $(foreach m, $(suffix_moe), $(foreach d, $(schools_dems), $(d)_$(m)))
# comma separate data vars to strip from the tileset
schools_error_vars = $(subst $(space),$(comma),$(strip $(schools_moe)))
schools_data_vars_comma = $(subst $(space),$(comma),$(strip $(schools_data_vars)))


# determines how data values get parsed (size is int, rest are float)
int_cols = a_sz w_sz all_sz b_sz h_sz i_sz m_sz f_sz p_sz np_sz wa_sz wb_sz wh_sz wi_sz mf_sz pn_sz u r s t e m c ch mg bie
float_cols = $(group_data_vars) $(group_data_moe) $(schools_data_vars) $(schools_moe)

# variables to pull into master files for each level
group_vars = $(group_data_vars) $(group_data_moe) $(int_cols)
states_vars = $(group_vars)
counties_vars = $(group_vars)
districts_vars = $(group_vars)
schools_vars = $(schools_data_vars) $(schools_moe) all_sz

# variables containing place meta data
meta_vars = id,name,lat,lon,all_sz

# meta data file targets
meta_files = $(foreach t, $(geo_types), build/scatterplot/meta/$(t).csv)

# contains make targets for each individual variable file so data can be loaded in chunks
# (eg. build/scatterplot/counties/all_coh.csv) 
region_files = $(foreach g,$(geo_types),build/scatterplot/$(g).csv)

discovery_files = build/scatterplot/districts/all_avg3.csv build/scatterplot/districts/all_avg4.csv build/scatterplot/districts/all_avg5.csv build/scatterplot/districts/all_avg6.csv build/scatterplot/districts/all_avg7.csv build/scatterplot/districts/all_avg8.csv

# files to create reduced pairs for
reduced_pair_files = build/scatterplot/schools/reduced/schools.csv

# use this build ID if one is not set in the environment variables
DATA_VERSION?=v4.1-dev

.PHONY: help tiles data search geojson scatterplot deploy_s3 deploy_search deploy_tilesets deploy_scatterplot deploy_all deploy_flagged deploy_similar

# Based on https://swcarpentry.github.io/make-novice/08-self-doc/
#### help                       : Print help
help: Makefile
	perl -ne '/^#### / && s/^#### //g && print' $<

#### all                        : Build everything
all: tiles data search scatterplot similar flagged moe

# Note: removed `scatterplot` task from CSV build, front end now uses full data files (10/08/20)
#### csv files									: Build static CSV files
csv: data explorer similar flagged moe

#### s3                         : Build and deploy all S3 data
s3: csv deploy_s3

#### mapbox                     : Build and deploy all mapbox assets
mapbox: tiles deploy_tilesets

#### algolia                    : Build and deploy all algolia (search) data
algolia: search deploy_search

#### tiles                      : Create mbtiles for all regions
tiles: $(foreach t, $(geo_types), build/tiles/$(t).mbtiles)

#### geojson                    : Create GeoJSON files with data for all regions
geojson: $(foreach t, $(geo_types), build/geography/$(t).geojson)

#### data                       : Creates master data files used to populate search, tilesets, etc.
data: $(foreach t, $(geo_types), build/data/$(t).csv)

#### explorer                   : Creates static files used in the explorer
explorer: $(foreach t, $(geo_types), build/explorer/$(t).csv)

#### export_data                : create csv / geojson files split by state 
export_data: data geojson
	python3 scripts/create_export_data.py

#### scatterplot                : Create all individual var files used for scatterplots
scatterplot: $(meta_files) $(region_files) $(reduced_pair_files)
	find build/scatterplot/ -type f -size 0 -delete

#### search                     : Create data files containing data for search
search:  $(foreach t, $(geo_types), build/search/$(t).csv)

#### clean                      : Remove files
clean:
	rm -rf build

#### deploy_all                 : Deploy all data to S3 / CloudFront endpoint
deploy_all: deploy_tilesets deploy_scatterplot deploy_similar deploy_flagged



###
### CHOROPLETH TILES
###
### `make tiles`
### Creates the .mbtiles files for the tilesets, populated with data
###

# attribute type flags for tippecanoe
attr_types = --attribute-type=id:string $(foreach t, $(float_cols), --attribute-type=$(t):float) $(foreach t, $(int_cols), --attribute-type=$(t):int)
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



###
### GEOJSON
###
### `make geojson`
### Creates GeoJSON containing all of the data that is used in tilesets.
###

states-geoid = "this.properties.id = this.properties.GEOID"
states-name = "this.properties.name = this.properties.NAME"
counties-geoid = "this.properties.id = this.properties.GEOID"
counties-name = "this.properties.name = this.properties.NAME"
districts-geoid = "this.properties.id = this.properties.GEOID"
districts-name = "this.properties.name = this.properties.NAME"

### Creates counties geojson w/ GEOID and name (no data)
# build/geography/base/%.geojson:
# 	mkdir -p $(dir $@)
# 	node ./scripts/update_geojson.js $* source/shapes/$*.geojson $@
# 	echo "{ \"type\":\"FeatureCollection\", \"features\": " | cat - $@ > build/geography/base/tmp.geojson
# 	echo "}" >> build/geography/base/tmp.geojson
# 	mv build/geography/base/tmp.geojson $@


### Creates districts geojson w/ GEOID and name (no data) from seda shapefiles
build/geography/base/counties.geojson:
	mkdir -p $(dir $@)
	mapshaper source/shapes/counties/*.shp combine-files \
		-each $(counties-geoid) \
		-each $(counties-name) \
		-filter-fields id,name \
		-uniq id \
		-o - combine-layers format=geojson > $@

### Creates districts geojson w/ GEOID and name (no data) from seda shapefiles
build/geography/base/states.geojson:
	mkdir -p $(dir $@)
	mapshaper source/shapes/states/*.shp combine-files \
		-each $(states-geoid) \
		-each $(states-name) \
		-filter-fields id,name \
		-uniq id \
		-o - combine-layers format=geojson > $@

### Creates districts geojson w/ GEOID and name (no data) from seda shapefiles
build/geography/base/districts.geojson:
	mkdir -p $(dir $@)
	mapshaper source/shapes/districts/*.shp combine-files \
		-each $(districts-geoid) \
		-each $(districts-name) \
		-filter-fields id,name \
		-uniq id \
		-o - combine-layers format=geojson > $@

### Create data file with only data for tilesets
build/geography/data/districts.csv: build/districts.csv
	mkdir -p $(dir $@)
	csvcut --not-columns lat,lon,all_avg3,all_avg4,all_avg5,all_avg6,all_avg7,all_avg8,state_name,state,$(group_error_vars) $< > $@

### Create data file with only data for tilesets
build/geography/data/%.csv: build/%.csv
	mkdir -p $(dir $@)
	csvcut --not-columns lat,lon,state_name,state,featname,$(group_error_vars) $< > $@

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

### find schools in the same location, offset slightly
build/overlapping_schools.csv: build/schools.csv
	csvcut -c id,lat,lon $< | \
	sort -n | sed -E s/,/\ /g | \
	uniq -f 1 -c | \
	sed -E s/^[\ ]*//g | \
	csvgrep -d \  -r [2-9]{1} -c 1 | \
	sed '1s/.*/count,id,lat,lon/' | \
	csvsort -c 1 -r -I



###
### DATA
###
### `make data`
### build master data files containing all data for each region type.
###

geojson_label_cmd = node --max_old_space_size=4096 $$(which geojson-polygon-labels)

### Build master data file for counties / districts from center points and dictionary
build/%.csv: build/ids/%.csv build/centers/%.csv build/from_dict/%.csv
	mkdir -p $(dir $@)
	csvjoin -c id --left --no-inference $^ | \
	python3 scripts/clean_data.py $* | \
	sed -E 's/(-?[0-9]+)\.0,/\1,/g' > $@

### Build master data file for schools from dictionary
build/schools.csv: build/from_dict/schools.csv
	mkdir -p $(dir $@)
	node scripts/separate_schools.js $< | \
	python3 scripts/clean_data.py schools | \
	sed -E 's/(-?[0-9]+)\.0,/\1,/g' > $@

### Extracts data based on the dictionary file for counties / districts / schools
.SECONDEXPANSION:
build/from_dict/%.csv: source/$$*_cov.csv source/$$($$*_main) source/district_grade_estimates.csv
	mkdir -p $(dir $@)
	cat dictionaries/$*_dictionary.csv | \
	python3 scripts/create_data_from_dictionary.py $(dir $<) > $@

### Build centers data with lat / lon center point and name for counties / districts
build/centers/%.csv: build/geography/base/%.geojson
	mkdir -p $(dir $@)
	$(geojson_label_cmd) --style largest $< | \
	in2csv --format json -k features | \
	csvcut -c properties/id,properties/name,geometry/coordinates/0,geometry/coordinates/1 | \
	sed '1s/.*/id,featname,lon,lat/' | \
	python3 scripts/clean_data.py $* > $@

### Builds a csv file containing only IDs for the given region, used for joins
build/ids/%.csv: build/from_dict/%.csv
	mkdir -p $(dir $@)
	csvcut -c 1 $< | \
	csvsort -c 1 --no-inference | \
	uniq | \
	sed '1s/.*/id/' > $@

### Build full data CSV for each region and split by state
build/data/%.csv: build/%.csv
	mkdir -p $(dir $@)
	cat $< | python3 scripts/strip_values.py $* | \
	csvcut --not-columns fid,state,state_name,featname > $@
	xsv partition -p 2 id $(dir $@)$* $@

### Build full data CSV for each region and split by state
build/data/districts.csv: build/districts.csv
	mkdir -p $(dir $@)
	cat $< | python3 scripts/strip_values.py districts | \
	csvcut --not-columns fid,all_avg3,all_avg4,all_avg5,all_avg6,all_avg7,all_avg8,state,state_name,featname > $@
	xsv partition -p 2 id $(dir $@)districts $@

### Build full data CSV for schools and split by state
build/data/schools.csv: build/schools.csv
	mkdir -p $(dir $@)
	cat $< | python3 scripts/strip_values.py schools | \
	csvcut --not-columns w_pct,i_pct,a_pct,h_pct,b_pct,state,state_name,fid,city > $@
	xsv partition -p 2 id $(dir $@)schools $@

###
### EXPLORER DATA
###

build/explorer/%.csv: build/data/%.csv
	mkdir -p $(dir $@)
	csvcut --not-columns $(group_error_vars) $^ | \
	sed 's/.0,/,/g' > $@

build/explorer/schools.csv: build/data/schools.csv
	mkdir -p $(dir $@)
	csvcut --not-columns all_avg_e,all_grd_e,all_coh_e  $^ | \
	sed 's/.0,/,/g' > $@

###
### SOURCE DATA
###
### handles fetching and deploying source data
###

### Fetch source data used for the build from S3 bucket
source/%.csv:
	mkdir -p $(dir $@)


###
### SCATTERPLOT
###
### `make scatterplot`
### Takes each of the variables for each region (e.g. counties_vars)
### and generate csv files mapping id : variable value.  These files
### are used for scatterplots.  Each variable is loaded as needed.
### Also creates a base file to use on initial load, with names, lat, lon, etc.
###

# point radius used for for reducing points
point_radius = 0.015

### Create the meta data file for states (no need to reduce)
build/scatterplot/meta/states.csv: build/data/states.csv
	mkdir -p $(dir $@)
	cp $< $@

### Create the meta data file for districts / counties
build/scatterplot/meta/%.csv: build/data/%.csv
	mkdir -p $(dir $@)
	cat $< | csvcut -c $(meta_vars) > $@

### Create the master meta data file for schools, and also split by state
build/scatterplot/meta/schools.csv: build/data/schools.csv
	mkdir -p $(dir $@)
	csvcut -c $(meta_vars) $< > $@
	xsv partition -p 2 id $(dir $@)schools $@

### Create the single variable file for districts (e.g. all_avg)
### NOTE: returns true even on fail when the data var is unavailable
###       so it doesn't break the build chain
build/scatterplot/%.csv: build/data/%.csv
	mkdir -p $(dir $@)
	csvcut --not-columns $(group_error_vars) $< | \
	sed -E 's/(-?[0-9]+)\.0,/\1,/g' > $@

### Create the single variable file for schools and also split by state
### NOTE: returns true even on fail when the data var is unavailable
###       so it doesn't break the build chain
build/scatterplot/schools.csv: build/data/schools.csv
	mkdir -p $(dir $@)
	csvcut --not-columns city,lat,lon,fid,$(schools_error_vars) $< | \
	sed -E 's/(-?[0-9]+)\.0,/\1,/g' > $@
	xsv partition --filename schools/{}.csv --prefix-length 2 id $(dir $@) $@ || true

### Create reduced school data sets for each variable pair based on a point radius
build/scatterplot/schools/reduced/schools.csv: build/schools.csv
	mkdir -p $(dir $@)
	python3 scripts/create_pairs.py schools $(point_radius) > $@



###
### SEARCH
###
### Generated search file contains all counties, districts, and schools
### with their name, latitude, longitude, and three key metrics.
### The search file is deployed to Algolia for indexing.
###

# columns to extract for search
search_cols = id,name,state_name,lat,lon,all_sz,all_avg,all_grd,all_coh

### Create search data for districts / counties
build/search/%.csv: build/%.csv
	mkdir -p $(dir $@)
	csvcut -c $(search_cols),all_ses $< > $@

build/search/states.csv: build/states.csv
	mkdir -p $(dir $@)
	csvcut -c id,name,lat,lon,all_sz,all_avg,all_grd,all_coh,all_ses $< > $@

### Create search data for schools (includes city name)
build/search/schools.csv: build/schools.csv
	mkdir -p $(dir $@)
	csvcut -c $(search_cols),city,all_frl $< > $@


###
### SIMILAR PLACES
###

similar: $(foreach t, $(geo_types), build/similar/$(t).csv)

# no similar states, so don't do anything
build/similar/states.csv:
	mkdir -p $(dir $@)

build/similar/%.csv: source/%_similar.csv
	mkdir -p $(dir $@)
	cat $< | \
	sed '1s/.*/id,sim1,sim2,sim3,sim4,sim5/' | \
	csvcut -c id,sim1,sim2,sim3,sim4,sim5 > $@
	xsv partition -p 2 id $(dir $@)$* $@

build/similar/schools.csv: source/schools_similar.csv
	mkdir -p $(dir $@)
	cat $< | \
	sed '1s/.*/id,sim1,sim2,sim3,sim4,sim5/' | \
	csvcut -c id,sim1,sim2,sim3,sim4,sim5 > $@
	xsv partition -p 2 id $(dir $@)schools $@


###
### FLAGGED SCHOOLS
###

flags = sped gifted lep missing
flagged: $(foreach t, $(flags), build/flagged/$(t).json)

build/flagged/%.json: source/flag_%.csv
	mkdir -p $(dir $@)
	csvgrep $< -c 2 -m 1 | python3 ./scripts/ncessch_to_json_array.py > $@

# Convert the missing flags CSV file to JSON:
# - csvgrep: pull rows where flag = 1
# - csvcut: pull only the id column
# - tail: remove the column header
# - csvformat: add double quotes to entries, replace new lines with commas
# - sed: drop the trailing comma from the output
# - awk: wrap the output in square brackets so it is a javascript array
build/flagged/missing.json: source/flag_missing.csv
	mkdir -p $(dir $@)
	csvgrep source/flag_missing.csv -c 3 -m 1 | \
	csvcut -c 1 | \
	tail -n +2 | \
	csvformat -U 1 -M "," | \
	sed -E 's/,$$/ /g' | \
	awk '{print "["$$1"]"}' > $@

###
### MARGIN OF ERROR
###

moe: ${foreach g, $(geo_types), build/moe/$(g).csv}

build/moe/%.csv: build/data/%.csv
	mkdir -p $(dir $@)
	csvcut -c id,$(group_error_vars) $< > $@

build/moe/schools.csv: build/data/schools.csv
	mkdir -p $(dir $@)
	csvcut -c id,all_avg_e,all_grd_e,all_coh_e $< > $@

###
### DEPLOYMENT
###

#### deploy_service             : Update export service (updates to use latest image from dockerhub)
deploy_service:
	aws ecs update-service --cluster edop-pdf-cluster --service edop-pdf-container-service --force-new-deployment

#### deploy_tilesets            : Deploy the tilesets to mapbox using the upload API
deploy_tilesets:
	for f in build/tiles/*.mbtiles; do node ./scripts/deploy_tilesets.js $$f $$(basename "$${f%.*}")-$(subst $(dot),$(hyphen),$(DATA_VERSION)); done

#### deploy_export_data         : Deploy the csv / geojson exports
deploy_export_data:
	aws s3 cp ./build/export s3://$(EXPORT_DATA_BUCKET)/$(DATA_VERSION) \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000


#### deploy_search              : Algolia deploy (WARNING: 100,000+ records, costs $$)
deploy_search:
	python3 scripts/deploy_search.py ./build/search/counties.csv counties
	python3 scripts/deploy_search.py ./build/search/districts.csv districts
	python3 scripts/deploy_search.py ./build/search/schools.csv schools
	python3 scripts/deploy_search.py ./build/search/states.csv states

#### deploy_source_csv          : Deploy local source csv data to S3 bucket
deploy_source_csv:
	for f in source/*.csv; do gzip $$f; done
	for f in source/*.csv.gz; do aws s3 cp $$f s3://$(DATA_BUCKET)/source/$(DATA_VERSION)/$$(basename $$f) --acl=public-read; done

#### deploy_source_geojson      : Deploy local source geojson data to S3 bucket
deploy_source_geojson:
	for f in source/*.geojson; do gzip $$f; done
	for f in source/*.geojson.gz; do aws s3 cp $$f s3://$(DATA_BUCKET)/source/$(DATA_VERSION)/$$(basename $$f) --acl=public-read; done

#### deploy_source_zip          : Deploy local source zip data to S3 bucket
deploy_source_zip:
	for f in source/*.zip; do aws s3 cp $$f s3://$(DATA_BUCKET)/source/$(DATA_VERSION)/$$(basename $$f) --acl=public-read; done

  
deploy_s3:
	mkdir -p ./build/s3
	mkdir -p ./build/scatterplot && cp -rf ./build/scatterplot ./build/s3
	mkdir -p ./build/similar && cp -rf ./build/similar ./build/s3
	mkdir -p ./build/flagged && cp -rf ./build/flagged ./build/s3
	mkdir -p ./build/data && cp -rf ./build/data ./build/s3
	mkdir -p ./build/explorer && cp -rf ./build/explorer ./build/s3
	mkdir -p ./build/moe && cp -rf ./build/moe ./build/s3
	aws s3 cp ./build/s3 s3://$(DATA_BUCKET)/build/$(DATA_VERSION) \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000
	aws cloudfront create-invalidation --distribution-id $(CLOUDFRONT_ID) \
  	--paths "/$(DATA_VERSION)/*"

#### deploy_scatterplot         : Deploy scatterplot var files to S3 bucket 
deploy_scatterplot:
	aws s3 cp ./build/scatterplot s3://$(DATA_BUCKET)/build/$(DATA_VERSION)/scatterplot \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000
	aws cloudfront create-invalidation --distribution-id $(CLOUDFRONT_ID) \
  	--paths "/$(DATA_VERSION)/scatterplot/*"

#### deploy_similar             : Deploy similar locations csv to S3 and invalidate CloudFront cache
deploy_similar:
	aws s3 cp ./build/similar s3://$(DATA_BUCKET)/build/$(DATA_VERSION)/similar \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000
	aws cloudfront create-invalidation --distribution-id $(CLOUDFRONT_ID) \
  	--paths "/$(DATA_VERSION)/similar/*"

#### deploy_flagged             : Deploy school flags to S3 and invalidate CloudFront cache
deploy_flagged:
	aws s3 cp ./build/flagged s3://$(DATA_BUCKET)/build/$(DATA_VERSION)/flagged \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000
	aws cloudfront create-invalidation --distribution-id $(CLOUDFRONT_ID) \
  	--paths "/$(DATA_VERSION)/flagged/*"

#### deploy_data                : Deploy static data csvs
deploy_data:
	aws s3 cp ./build/data s3://$(DATA_BUCKET)/build/$(DATA_VERSION)/data \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000
	aws cloudfront create-invalidation --distribution-id $(CLOUDFRONT_ID) \
  	--paths "/$(DATA_VERSION)/data/*"

#### deploy_moe                 : Deploy margin of error to S3 and invalidate CloudFront cache
deploy_moe:
	aws s3 cp ./build/moe s3://$(DATA_BUCKET)/build/$(DATA_VERSION)/moe \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000
	aws cloudfront create-invalidation --distribution-id $(CLOUDFRONT_ID) \
  	--paths "/$(DATA_VERSION)/moe/*"
