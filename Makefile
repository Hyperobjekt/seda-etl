geo_types = counties districts schools

# id field names for various regions
counties_id = countyid
districts_id = leaidC
schools_id = ncessch

# master data file names
counties_main = SEDA_county_pool_GCS_v22.csv
districts_main = SEDA_geodist_pool_GCS_v22.csv
schools_main = SEDA_school_pool_GCS_v30_latlong.csv

# variables to pull into individual files
counties_vars = all_avg all_grd all_coh a_avg a_grd a_coh b_avg b_grd b_coh p_avg p_grd p_coh f_avg f_grd f_coh h_avg h_grd h_coh m_avg m_grd m_coh mf_avg mf_grd mf_coh np_avg np_grd np_coh pn_avg pn_grd pn_coh wa_avg wa_grd wa_coh wb_avg wb_grd wb_coh wh_avg wh_grd wh_coh w_avg w_grd w_coh all_ses w_ses b_ses h_ses wb_ses wh_ses wb_seg wh_seg frpl_seg
districts_vars = $(counties_vars)
schools_vars = fl_pct rl_pct frl_pct w_pct i_pct a_pct h_pct b_pct

# length of id used for each region type id
counties_idlen = 5
districts_idlen = 7
schools_idlen = 12

# use this build ID if one is not set in the environment variables
BUILD_ID?=dev

# For comma-delimited list
null :=
space := $(null) $(null)
comma := ,

.PHONY: tiles data search vars geojson deploy_search deploy_tilesets deploy_vars deploy_all

all: tiles data vars search

deploy_all: deploy_search deploy_tilesets deploy_vars

## clean                            : Remove files
clean:
	rm -rf build

######
### CHOROPLETH TILES
######
### `make tiles`
### Creates the .mbtiles files for the tilesets, populated with data
######

numeric_cols = $(counties_vars) $(schools_vars)
attr_types = --attribute-type=id:string $(foreach t, $(numeric_cols), --attribute-type=$(t):float)

tippecanoe_default_opts = --maximum-tile-bytes=500000 --minimum-zoom=2
tippecanoe_poly_opts =  $(tippecanoe_default_opts) $(attr_types) --use-attribute-for-id=fid --simplification=10 --coalesce-densest-as-needed --maximum-zoom=12 --detect-shared-borders --no-tile-stats --force
tippecanoe_point_opts = $(tippecanoe_default_opts) $(attr_types) --generate-ids -zg --drop-densest-as-needed --extend-zooms-if-still-dropping --no-tile-stats --force

tiles: $(foreach t, $(geo_types), build/tiles/$(t).mbtiles)

build/tiles/%.mbtiles: build/geography/%.geojson
	mkdir -p $(dir $@)
	tippecanoe -L $*:$< $(tippecanoe_poly_opts) -o $@

build/tiles/schools.mbtiles: build/geography/schools.geojson
	mkdir -p $(dir $@)
	tippecanoe -L schools:$< $(tippecanoe_point_opts) -o $@

deploy_tilesets:
	for f in build/tiles/*.mbtiles; do node ./scripts/deploy_tilesets.js $$f $$(basename "$${f%.*}")-$$(BUILD_ID); done


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

geojson: $(foreach t, $(geo_types), build/geography/$(t).geojson)

build/geography/counties.geojson: build/processed/counties.csv
	mkdir -p $(dir $@)
	wget --no-use-server-timestamps -np -nd -r -P ./build/geography/counties -A '$(counties-pattern)' $(census_ftp_base)
	for f in ./build/geography/counties/*.zip; do unzip -d ./build/geography/counties $$f; done
	mapshaper ./build/geography/counties/*.shp combine-files \
		-each $(counties-geoid) \
		-each $(counties-name) \
		-filter-fields id,name \
		-o - combine-layers format=geojson | \
	tippecanoe-json-tool -e id | \
	LC_ALL=C sort | \
	tippecanoe-json-tool -w -c $< > $@

build/geography/districts.geojson: build/processed/districts.csv
	mkdir -p $(dir $@)
	aws s3 cp s3://$(DATA_BUCKET)/source/$(DATA_VERSION)/SEDA_shapefiles_v21.zip ./build
	unzip -d build/shp ./build/SEDA_shapefiles_v21.zip
	mapshaper ./build/shp/*.shp combine-files \
		-each $(districts-geoid) \
		-each $(districts-name) \
		-filter-fields id,name \
		-uniq id \
		-o - combine-layers format=geojson | \
	tippecanoe-json-tool -e id | \
	LC_ALL=C sort | \
	tippecanoe-json-tool -w -c $< > $@

build/geography/schools.geojson: build/processed/schools.csv
	mkdir -p $(dir $@)
	csv2geojson --lat lat --lon lon $^ | \
	mapshaper - -o $@ combine-layers format=geojson 

######
### DATA
######
### `make data`
### build master data files containing all data for each region type.
######

geojson_label_cmd = node --max_old_space_size=4096 $$(which geojson-polygon-labels)

data: $(foreach t, $(geo_types), build/$(t).csv)

build/%.csv: build/ids/%.csv build/centers/%.csv build/processed/%.csv
	mkdir -p $(dir $@)
	csvjoin -c id --left --no-inference $^ > $@

build/schools.csv: build/processed/schools.csv
	mkdir -p $(dir $@)
	cp $< $@

## Processed data, where all variables defined in the dictionary file
## are extracted from their associated files.

.SECONDEXPANSION:
build/processed/%.csv: build/data/$$*_cov.csv build/data/$$($$*_main)
	mkdir -p $(dir $@)
	cat dictionaries/$*_dictionary.csv | \
	python3 scripts/create_data_from_dictionary.py > $@

### Centers data to create a lat/lon point associated with each feature
### with and accompanying name

build/centers/%.csv: build/geography/%.geojson
	mkdir -p $(dir $@)
	$(geojson_label_cmd) --style largest $< | \
	in2csv --format json -k features | \
	csvcut -c properties/id,properties/name,geometry/coordinates/0,geometry/coordinates/1 | \
	awk -F, '{ printf "%0$($*_idlen).0f,%s,%s,%s\n", $$1,$$2,$$3,$$4 }' | \
	sed '1s/.*/id,name,lon,lat/' > $@

build/centers/schools.csv: build/processed/%.csv
	mkdir -p $(dir $@)
	csvcut -c id,name,lat,lon $< > $@

### IDs file, pulled from the master data files.  Used for joins so we only
### use identifiers with associated education data.

.SECONDEXPANSION:
build/ids/%.csv: build/data/$$($$*_main)
	mkdir -p $(dir $@)
	csvcut -e windows-1251 -c $($*_id) build/data/$($*_main) | \
	csvsort -c $($*_id) --no-inference | \
	uniq | \
	sed '1s/.*/id/' > $@

### Fetch source data from S3 bucket

build/data/%.csv:
	mkdir -p $(dir $@)
	wget -qO- http://$(DATA_BUCKET).s3-website-us-east-1.amazonaws.com/source/$(DATA_VERSION)/$*.csv.gz | \
	gunzip -c - > $@

######
### INDIVIDUAL VARIABLES
######
### `make vars`
### Takes each of the variables for each region (e.g. counties_vars)
### and generate csv files mapping id : variable value.  These files
### are used for scatterplots.  Each variable is loaded as needed.
######

vars: $(foreach g,$(geo_types),$(foreach v,$($(g)_vars),build/vars/$(g)-$(v).csv))

.SECONDEXPANSION:
build/vars/%.csv: build/processed/$$(subst -$$(lastword $$(subst -, ,$$*)),,$$*).csv
	mkdir -p $(dir $@)
	csvcut -c id,$(lastword $(subst -, ,$*)) $^ | \
	awk -F, ' $$2 != "" { print $$0 } ' | \
	awk -F, ' $$2 != -9999.0 { print $$0 } ' | \
	awk -F, '{ printf "%0$($(subst -$(lastword $(subst -, ,$*)),,$*)_idlen)i,%.4f\n", $$1,$$2 }' | \
	sed '1s/.*/id,$(lastword $(subst -, ,$*))/' > $@

deploy_vars:
	aws s3 cp ./build/vars s3://$(DATA_BUCKET)/build/$(BUILD_ID)/vars \ 
		--recursive \ 
		--acl=public-read \
		--content-encoding=gzip \
		--region=us-east-1 \ 
		--cache-control max-age=2628000

######
### SEARCH
######
### Generated search file contains all counties, districts, and schools
### with their name, latitude, longitude, and three key metrics.
### The search file is deployed to Algolia for indexing.
######

search_cols = id,name,lat,lon,all_avg,all_grd,all_coh

search: build/search.csv

build/search.csv: $(foreach t, $(geo_types), build/search/$(t).csv)
	csvstack -g counties,districts,schools $^  > $@

build/search/%.csv: build/%.csv
	mkdir -p $(dir $@)
	csvcut -c $(search_cols) $< > $@

deploy_search:
	python3 scripts/deploy_search.py ./build/search.csv


