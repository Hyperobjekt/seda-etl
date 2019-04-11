geo_types = counties districts schools

# id field names for various regions
counties_id = countyid
districts_id = leaidC
schools_id = ncessch

# master data file names
counties_main = SEDA_county_pool_GCS_v30.csv
districts_main = SEDA_geodist_pool_GCS_v30.csv
schools_main = SEDA_school_pool_GCS_v30_latlong.csv

# variables to pull into individual files
counties_vars = sz all_avg all_grd all_coh a_avg a_grd a_coh b_avg b_grd b_coh p_avg p_grd p_coh f_avg f_grd f_coh h_avg h_grd h_coh m_avg m_grd m_coh mf_avg mf_grd mf_coh np_avg np_grd np_coh pn_avg pn_grd pn_coh wa_avg wa_grd wa_coh wb_avg wb_grd wb_coh wh_avg wh_grd wh_coh w_avg w_grd w_coh all_ses w_ses b_ses h_ses wb_ses wh_ses wb_seg wh_seg np_seg wb_pov wh_pov np_pov
districts_vars = $(counties_vars)
schools_vars = fl_pct rl_pct frl_pct w_pct i_pct a_pct h_pct b_pct

# length of id used for each region type id
counties_idlen = 5
districts_idlen = 7
schools_idlen = 12

# use this build ID if one is not set in the environment variables
BUILD_ID?=dev
SOURCE_VERSION=0.0.1

# For comma-delimited list
null :=
space := $(null) $(null)
comma := ,

.PHONY: tiles data search vars geojson deploy_search deploy_tilesets deploy_vars deploy_all

all: tiles data vars search scatterplot

deploy_all: deploy_tilesets deploy_scatterplot

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
	for f in build/tiles/*.mbtiles; do node ./scripts/deploy_tilesets.js $$f $$(basename "$${f%.*}")-$(BUILD_ID); done


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
	wget -qO- http://$(DATA_BUCKET).s3-website-us-east-1.amazonaws.com/source/$(DATA_VERSION)/districts.geojson.gz | \
	gunzip -c - | \
	mapshaper - \
		-each $(districts-geoid) \
		-each $(districts-name) \
		-filter-fields id,name \
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
### SCATTERPLOT
######
### `make scatterplot`
### Takes each of the variables for each region (e.g. counties_vars)
### and generate csv files mapping id : variable value.  These files
### are used for scatterplots.  Each variable is loaded as needed.
### Also creates a base file to use on initial load, with names, lat, lon, etc.
######

# variables to pull into individual files
counties_scatter = id,name,lat,lon,all_avg,all_ses,sz
districts_scatter = $(counties_scatter)
schools_scatter = id,name,lat,lon,all_avg,frl_pct

scatterplot: $(foreach t, $(geo_types), build/scatterplot/$(t)-base.csv) $(foreach g,$(geo_types),$(foreach v,$($(g)_vars),build/scatterplot/$(g)-$(v).csv))

### TODO: Improve formatting, awk messes with header row and is not very readable
build/scatterplot/%-base.csv: build/%.csv
	mkdir -p $(dir $@)
	cat $< | \
	csvcut -c $($*_scatter) | \
	csvgrep -c name -i -r '^$$' | \
	awk -F, '{ printf "%s,%s,%.4f,%.4f,%.4f,%.4f,%.4f\n", $$1,$$2,$$3,$$4,$$5,$$6,$$7 }' | \
	sed --expression='s/-9999.0000//g' | \
	sed '1s/.*/$($*_scatter)/' > $@

build/scatterplot/schools-base.csv: build/schools.csv
	mkdir -p $(dir $@)
	cat $< | \
	csvcut -c $(schools_scatter) | \
	csvgrep -c name -i -r '^$$' | \
	sed --expression='s/-9999.0//g' | \
	sed '1s/.*/$(schools_scatter)/' > $@

.SECONDEXPANSION:
build/scatterplot/%.csv: build/processed/$$(subst -$$(lastword $$(subst -, ,$$*)),,$$*).csv
	mkdir -p $(dir $@)
	csvcut -c id,$(lastword $(subst -, ,$*)) $^ | \
	awk -F, ' $$2 != "" { print $$0 } ' | \
	awk -F, ' $$2 != -9999.0 { print $$0 } ' | \
	awk -F, '{ printf "%0$($(subst -$(lastword $(subst -, ,$*)),,$*)_idlen)i,%.4f\n", $$1,$$2 }' | \
	sed '1s/.*/id,$(lastword $(subst -, ,$*))/' > $@


split_schools: scatterplot
	mkdir -p build/scatterplot/schools
	for f in build/scatterplot/schools*.csv; do xsv partition -p 2 id build/scatterplot/schools/$$(basename "$${f#*-}" .csv) $$f; done

deploy_scatterplot:
	aws s3 cp ./build/scatterplot s3://$(DATA_BUCKET)/build/$(BUILD_ID)/scatterplot \
		--recursive \
		--acl=public-read \
		--region=us-east-1 \
		--cache-control max-age=2628000

######
### SEARCH
######
### Generated search file contains all counties, districts, and schools
### with their name, latitude, longitude, and three key metrics.
### The search file is deployed to Algolia for indexing.
######

search_cols = id,name,state,lat,lon,all_avg,all_grd,all_coh,sz

search:  $(foreach t, $(geo_types), build/search/$(t).csv)


build/search/%.csv: build/clean/%.csv
	mkdir -p $(dir $@)
	csvcut -c $(search_cols) $< | \
	sed '1s/.*/$(search_cols)/' > $@

deploy_search:
	python3 scripts/deploy_search.py ./build/search/counties.csv counties
	python3 scripts/deploy_search.py ./build/search/districts.csv districts
	python3 scripts/deploy_search.py ./build/search/schools.csv schools


deploy_source_data:
	for f in source_data/*.csv; do gzip $$f; done
	for f in source_data/*.geojson; do gzip $$f; done
	for f in source_data/*.gz; do aws s3 cp $$f s3://$(DATA_BUCKET)/source/$(SOURCE_VERSION)/$$(basename $$f) --acl=public-read; done


######
### EXPORTS
######
### Creates public data by state
######

### Remove any places with empty names, drop N/A values
build/clean/%.csv: build/%.csv
	mkdir -p $(dir $@)
	csvgrep -c name -i -r '^$$' $< | \
	sed --expression='s/-9999.0//g' | \
	sed --expression='s/-9999//g' > $@