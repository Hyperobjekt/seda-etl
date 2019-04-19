geo_types = counties districts schools

# id field names for various regions
counties_id = countyid
districts_id = leaidC
schools_id = ncessch

# master data file names
counties_main = SEDA_county_pool_GCS_v30.csv
districts_main = SEDA_geodist_pool_GCS_v30.csv
schools_main = SEDA_school_pool_GCS_v30_latlong.csv

counties_metrics = avg grd coh ses seg pov sz
counties_dems = all a b p f h m mf np pn wa wb wh fl

schools_metrics = pct avg grd coh sz
schools_dems = all w a h b i fl rl frl

# variables to pull into individual files
# counties_vars = sz all_avg all_grd all_coh a_avg a_grd a_coh b_avg b_grd b_coh p_avg p_grd p_coh f_avg f_grd f_coh h_avg h_grd h_coh m_avg m_grd m_coh mf_avg mf_grd mf_coh np_avg np_grd np_coh pn_avg pn_grd pn_coh wa_avg wa_grd wa_coh wb_avg wb_grd wb_coh wh_avg wh_grd wh_coh w_avg w_grd w_coh all_ses w_ses b_ses h_ses wb_ses wh_ses wb_seg wh_seg np_seg wb_pov wh_pov np_pov
counties_vars = $(foreach m, $(counties_metrics), $(foreach d, $(counties_dems), $(d)_$(m)))
districts_vars = $(counties_vars)
# schools_vars = fl_pct rl_pct frl_pct w_pct i_pct a_pct h_pct b_pct
schools_vars = $(foreach m, $(schools_metrics), $(foreach d, $(schools_dems), $(d)_$(m)))

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
tippecanoe_poly_opts =  $(tippecanoe_default_opts) $(attr_types) --empty-csv-columns-are-null --use-attribute-for-id=fid --simplification=10 --coalesce-densest-as-needed --maximum-zoom=12 --detect-shared-borders --no-tile-stats --force
tippecanoe_point_opts = $(tippecanoe_default_opts) $(attr_types) --empty-csv-columns-are-null --generate-ids -zg --drop-densest-as-needed --extend-zooms-if-still-dropping --no-tile-stats --force

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

### Creates geojson without the data populated
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


build/geography/%.geojson: build/geography/base/%.geojson build/%.csv
	mkdir -p $(dir $@)
	cat $< | \
	tippecanoe-json-tool -e id | \
	LC_ALL=C sort | \
	tippecanoe-json-tool --empty-csv-columns-are-null --wrap --csv=$(word 2,$^) > $@

build/geography/schools.geojson: build/schools.csv
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

build/%.csv: build/ids/%.csv build/centers/%.csv build/from_dict/%.csv
	mkdir -p $(dir $@)
	csvjoin -c id --left --no-inference $^ | \
	python3 scripts/clean_data.py $* > $@


build/schools.csv: build/from_dict/schools.csv
	mkdir -p $(dir $@)
	cat $< | \
	python3 scripts/clean_data.py schools > $@

## Processed data, where all variables defined in the dictionary file
## are extracted from their associated files.

.SECONDEXPANSION:
build/from_dict/%.csv: build/source_data/$$*_cov.csv build/source_data/$$($$*_main)
	mkdir -p $(dir $@)
	cat dictionaries/$*_dictionary.csv | \
	python3 scripts/create_data_from_dictionary.py $(dir $<) > $@

### Centers data to create a lat/lon point associated with each feature
### with and accompanying name

build/centers/%.csv: build/geography/base/%.geojson
	mkdir -p $(dir $@)
	$(geojson_label_cmd) --style largest $< | \
	in2csv --format json -k features | \
	csvcut -c properties/id,properties/name,geometry/coordinates/0,geometry/coordinates/1 | \
	sed '1s/.*/id,name,lon,lat/' | \
	python3 scripts/clean_data.py $* > $@

### IDs file, pulled from the master data files.  Used for joins so we only
### use identifiers with associated education data.

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

reduced_schools: $(foreach x, $(schools_vars), $(foreach y, $(schools_vars), build/reduced/schools/$(x)-$(y).csv))
point_radius = 0.02

scatterplot_schools: build/schools.csv
	mkdir -p build/scatterplot/national
	cat $< | \
	python3 scripts/reduce_points.py $(firstword $(subst -, ,$*)) $(lastword $(subst -, ,$*)) all_sz $(point_radius) > $@

schools_meta: build/schools.csv
	mkdir -p build/meta

# variables to pull into individual files
counties_scatter = id,name,lat,lon,all_sz
districts_scatter = $(counties_scatter)
schools_scatter = id,name,lat,lon,all_sz


build/plot/districts/all.csv: build/districts.csv
	mkdir -p $(dir $@)
	cat $< | \
	python3 get_clean_cols.py districts > $@

build/plot/districts/meta.csv: build/districts.csv
	mkdir -p $(dir $@)
	cat $< | \
	python3 get_clean_cols.py districts $(districts_scatter) > $@

build/plot/counties/meta.csv: build/districts.csv
	mkdir -p $(dir $@)
	cat $< | \
	python3 get_clean_cols.py districts $(districts_scatter) > $@


scatterplot: $(foreach t, $(geo_types), build/scatterplot/$(t)-base.csv) $(foreach g,$(geo_types),$(foreach v,$($(g)_vars),build/scatterplot/$(g)-$(v).csv))

build/scatterplot/%-base.csv: build/%.csv
	mkdir -p $(dir $@)
	cat $< | \
	csvcut -c $($*_scatter) > $@

.SECONDEXPANSION:
build/scatterplot/%.csv: build/processed/$$(subst -$$(lastword $$(subst -, ,$$*)),,$$*).csv
	mkdir -p $(dir $@)
	csvcut -c id,$(lastword $(subst -, ,$*)) $^ > $@

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

search_cols = id,name,state,lat,lon,all_avg,all_grd,all_coh,all_sz

search:  $(foreach t, $(geo_types), build/search/$(t).csv)

build/search/%.csv: build/%.csv
	mkdir -p $(dir $@)
	csvcut -c $(search_cols) $< > $@

deploy_search:
	python3 scripts/deploy_search.py ./build/search/counties.csv counties
	python3 scripts/deploy_search.py ./build/search/districts.csv districts
	python3 scripts/deploy_search.py ./build/search/schools.csv schools

######
### EXPORTS
######
### Creates public data by state
######

# TODO
