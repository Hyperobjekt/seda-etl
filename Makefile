# Makefile for creating Census geography data for 2010 from source rather than S3
census_ftp_base = ftp://ftp2.census.gov/geo/tiger/GENZ2010/

counties-pattern = gz_*_*_050_*_500k.zip
counties-geoid = "this.properties.id = this.properties.STATE + this.properties.COUNTY"
counties-name = "this.properties.name = this.properties.NAME + ' ' + this.properties.LSAD"
districts-geoid = "this.properties.id = this.properties.GEOID"
districts-name = "this.properties.name = this.properties.NAME"

geo_types = counties districts schools
geo_files = $(foreach t, $(geo_types), build/geography/$(t).geojson)

numeric_cols = all_ses w_ses b_ses h_ses wb_seg wh_seg frpl_seg all_avg all_grd all_coh a_avg a_grd a_coh b_avg b_grd b_coh p_avg p_grd p_coh f_avg f_grd f_coh h_avg h_grd h_coh m_avg m_grd m_coh mf_avg mf_grd mf_coh np_avg np_grd np_coh pn_avg pn_grd pn_coh wa_avg wa_grd wa_coh wb_avg wb_grd wb_coh wh_avg wh_grd wh_coh w_avg w_grd w_coh
attr_types = --attribute-type=id:string $(foreach t, $(numeric_cols), --attribute-type=$(t):float)

tippecanoe_default_opts = --maximum-tile-bytes=500000 --minimum-zoom=2
tippecanoe_poly_opts =  $(tippecanoe_default_opts) $(attr_types) -aI --simplification=10 --coalesce-densest-as-needed --maximum-zoom=12 --detect-shared-borders --no-tile-stats --force
tippecanoe_point_opts = $(tippecanoe_default_opts) $(attr_types) -aI -zg --drop-densest-as-needed --no-tile-stats --force

# For comma-delimited list
null :=
space := $(null) $(null)
comma := ,

# Edit node commands to use additional memory
mapshaper_cmd = node --max_old_space_size=4096 $$(which mapshaper)
geojson_label_cmd = node --max_old_space_size=4096 $$(which geojson-polygon-labels)

output_tiles = $(foreach t, $(geo_types), build/tiles/$(t).mbtiles)


all: $(output_tiles)

deploy:
	mkdir -p build/tilesets
	for f in build/tiles/*.mbtiles; do tile-join --no-tile-size-limit --force -e ./build/tilesets/$$(basename "$${f%.*}") $$f; done
	aws s3 cp ./build/tilesets s3://$(S3_TILESETS_BUCKET)/$(BUILD_ID) --recursive --acl=public-read --content-encoding=gzip --region=us-east-2 --cache-control max-age=2628000

## clean                            : Remove files
clean:
	rm -rf build/geography build/tiles build/processed



### CHOROPLETH TILES

## build/tiles/shapes/%.mbtiles                 : Census .mbtiles with specific flags for census geography
build/tiles/%.mbtiles: build/geography/%.geojson
	mkdir -p $(dir $@)
	tippecanoe -L $*:$< $(tippecanoe_poly_opts) -o $@

build/tiles/schools.mbtiles: build/geography/schools.geojson
	mkdir -p $(dir $@)
	tippecanoe -L schools:$< $(tippecanoe_point_opts) -o $@


### GEOJSON

## build/geography/counties.geojson             : Download and clean census GeoJSON
.SECONDARY:
build/geography/counties.geojson: build/processed/counties.csv
	mkdir -p $(dir $@)
	wget --no-use-server-timestamps -np -nd -r -P ./build/geography/counties -A '$(counties-pattern)' $(census_ftp_base)
	for f in ./build/geography/counties/*.zip; do unzip -d ./build/geography/counties $$f; done
	mapshaper ./build/geography/counties/*.shp combine-files id-field=GEO_ID \
		-each $(counties-geoid) \
		-each $(counties-name) \
		-filter-fields id,name \
		-o - id-field=id combine-layers format=geojson | \
	tippecanoe-json-tool -e id | \
	LC_ALL=C sort | \
	tippecanoe-json-tool -c build/processed/counties.csv > $@

## build/geography/districts.geojson             : Convert district shapefiles to geojson
build/geography/districts.geojson: build/shp/2013_Unified_Elementary_SD.shp build/processed/districts.csv
	mkdir -p $(dir $@)
	mapshaper ./build/shp/*.shp combine-files id-field=GEOID \
		-each $(districts-geoid) \
		-each $(districts-name) \
		-filter-fields id,name \
		-uniq id \
		-o - id-field=id combine-layers format=geojson | \
	tippecanoe-json-tool -e id | \
	LC_ALL=C sort | \
	tippecanoe-json-tool -c build/processed/districts.csv > $@


## build/geography/schools.geojson               : Create GeoJSON for schools
build/geography/schools.geojson: build/processed/schools.csv
	mkdir -p $(dir $@)
	csv2geojson --lat lat --lon lon $^ | \
	mapshaper - id-field=id -o $@ id-field=id combine-layers format=geojson 

build/shp/2013_Unified_Elementary_SD.shp:
	unzip -d build/shp SEDA_shapefiles_v21.zip

### DATA
counties_id = countyid
counties_extract_vars = sesall seswht sesblk seshsp sesdiff_whtblk sesdiff_whthsp diffexplch_blkwht diffexplch_hspwht diffexplch_flnfl hswhtblk hswhthsp hsflnfl
counties_rename_vars = all_ses w_ses b_ses h_ses wb_ses wh_ses diffexplch_blkwht diffexplch_hspwht diffexplch_flnfl hswhtblk hswhthsp hsflnfl
counties_file = build/data/counties_cov.csv

districts_id = leaid
districts_extract_vars = $(counties_extract_vars)
districts_rename_vars = $(counties_rename_vars)
districts_file = build/data/districts_cov.csv

schools_id = ncessch
schools_extract_vars = perflu perrlu perfrlu perwht perind perasn perhsp perblk
schools_rename_vars = $(schools_extract_vars)
schools_file = build/data/schools_cov.csv

vars: $(foreach g,$(geo_types),$(foreach v,$($(g)_rename_vars),build/vars/$(g)/$(v).csv))
build/vars/counties/%.csv: build/vars/counties.csv
	mkdir -p $(dir $@)
	csvcut -c id,$* $^ | \
	awk -F, ' $$2 != "" { print $$0 } ' | \
	awk -F, '{ printf "%05i,%.4f\n", $$1,$$2 }' | \
	sed '1s/.*/id,$*/' > $@

build/vars/districts/%.csv: build/vars/districts.csv
	mkdir -p $(dir $@)
	csvcut -c id,$* $^ | \
	awk -F, ' $$2 != "" { print $$0 } ' | \
	awk -F, '{ printf "%07i,%.4f\n", $$1,$$2 }' | \
	sed '1s/.*/id,$*/' > $@

build/vars/schools/%.csv: build/vars/schools.csv
	mkdir -p $(dir $@)
	csvcut -c id,$* $^ | \
	awk -F, ' $$2 != "" { print $$0 } ' | \
	awk -F, '{ printf "%12i,%.4f\n", $$1,$$2 }' | \
	sed '1s/.*/id,$*/' > $@

# Give columns new names
# Should be able to refactor into single rule, but
# $($*_extract_vars) was not working
.INTERMEDIATE:
build/vars/counties.csv:
	mkdir -p $(dir $@)
	csvcut -c $(counties_id),$(subst $(space),$(comma),$(strip $(counties_extract_vars))) $(counties_file) | \
	sed '1s/.*/id,$(subst $(space),$(comma),$(strip $(counties_rename_vars)))/' > $@
build/vars/districts.csv:
	mkdir -p $(dir $@)
	csvcut -c $(districts_id),$(subst $(space),$(comma),$(strip $(districts_extract_vars))) $(districts_file) | \
	sed '1s/.*/id,$(subst $(space),$(comma),$(strip $(districts_rename_vars)))/' > $@
build/vars/schools.csv:
	mkdir -p $(dir $@)
	csvcut -c $(schools_id),$(subst $(space),$(comma),$(strip $(schools_extract_vars))) $(schools_file) | \
	sed '1s/.*/id,$(subst $(space),$(comma),$(strip $(schools_rename_vars)))/' > $@

## build/processed/%.csv                     : Data for districts
build/processed/%.csv:
	mkdir -p $(dir $@)
	cat dictionaries/$*_dictionary.csv | \
	python3 scripts/create_data_from_dictionary.py > $@


### CENTERS TILES (for labels)

# ## build/tiles/centers/%.mbtiles                : Center .mbtiles with flags for centers based on layer
# build/tiles/centers/%.mbtiles: build/geography/%-centers.geojson
# 	mkdir -p $(dir $@)
# 	tippecanoe -L $*-centers:$< $(tippecanoe_point_opts) $($*_centers_opts) -o $@

# build/tiles/centers/%-data.mbtiles: build/processed/%-centers.csv build/tiles/centers/%.mbtiles
# 	mkdir -p $(dir $@)
# 	tile-join -l $*-centers $(tile_join_opts) -o $@ -c $^

# ## build/geography/%-centers.geojson            : GeoJSON centers
# build/geography/%-centers.geojson: build/geography/%.geojson
# 	mkdir -p $(dir $@)
# 	$(geojson_label_cmd) --style largest $< > $@

# build/processed/%-centers.csv: build/processed/%.csv
# 	mkdir -p $(dir $@)
# 	csvcut -c id,name $^ > $@
