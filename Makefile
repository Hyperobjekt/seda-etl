# Makefile for creating Census geography data for 2010 from source rather than S3
census_ftp_base = ftp://ftp2.census.gov/geo/tiger/GENZ2010/

counties-pattern = gz_*_*_050_*_500k.zip
counties-geoid = "this.properties.GEOID = this.properties.STATE + this.properties.COUNTY"

geo_types = counties districts
geo_files = $(foreach t, $(geo_types), build/geography/$(t).geojson)

tippecanoe_opts = --attribute-type=GEOID:string --simplification=10 --coalesce-densest-as-needed --maximum-zoom=12 --no-tile-stats --force
tile_join_opts = --empty-csv-columns-are-null --force --no-tile-stats

# min zoom to generate tiles for
counties_min_zoom = 2
districts_min_zoom = 2

# max tile size for geography
counties_bytes = 500000
districts_bytes = 200000

# column name mapping
og_cols = mn_avg_ol,mn_grd_ol,mn_mth_ol
new_cols = mn_ach,mn_slp,mn_diff

# For comma-delimited list
null :=
space := $(null) $(null)
comma := ,

# Assign layer properties based on minimum zoom
$(foreach g, $(geo_types), $(eval $(g)_census_opts = --maximum-tile-bytes=$($g_bytes) --minimum-zoom=$($g_min_zoom) --detect-shared-borders))
$(foreach g, $(geo_types), $(eval $(g)_centers_opts = --base-zoom=4))

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
	rm -rf build/geography build/tiles

### TILES

## build/tiles/%.mbtiles                        : Convert geography GeoJSON to .mbtiles
build/tiles/%.mbtiles: build/tiles/centers/%-data.mbtiles build/tiles/shapes/%-data.mbtiles
	mkdir -p $(dir $@)
	tile-join -n $* $(tile_join_opts) -o $@ $^

## build/tiles/centers/%.mbtiles                : Center .mbtiles with flags for centers based on layer
build/tiles/centers/%.mbtiles: build/geography/%-centers.geojson
	mkdir -p $(dir $@)
	tippecanoe -L $*-centers:$< $(tippecanoe_opts) $($*_centers_opts) -o $@

build/tiles/centers/%-data.mbtiles: build/processed/%-centers.csv build/tiles/centers/%.mbtiles
	mkdir -p $(dir $@)
	tile-join -l $*-centers $(tile_join_opts) -o $@ -c $^

## build/tiles/shapes/%.mbtiles                 : Census .mbtiles with specific flags for census geography
build/tiles/shapes/%.mbtiles: build/geography/%.geojson
	mkdir -p $(dir $@)
	tippecanoe -L $*:$< $(tippecanoe_opts) $($*_census_opts) -o $@

build/tiles/shapes/%-data.mbtiles: build/processed/%.csv build/tiles/shapes/%.mbtiles
	mkdir -p $(dir $@)
	tile-join -l $* $(tile_join_opts) -o $@ -c $^

### GEOJSON

## build/geography/%-centers.geojson            : GeoJSON centers
build/geography/%-centers.geojson: build/geography/%.geojson
	mkdir -p $(dir $@)
	$(geojson_label_cmd) --style largest $< > $@

## build/geography/counties.geojson             : Download and clean census GeoJSON
.SECONDARY:
build/geography/counties.geojson:
	mkdir -p $(dir $@)
	wget --no-use-server-timestamps -np -nd -r -P ./build/geography/counties -A '$(counties-pattern)' $(census_ftp_base)
	for f in ./build/geography/counties/*.zip; do unzip -d ./build/geography/counties $$f; done
	mapshaper ./build/geography/counties/*.shp combine-files \
		-each $(counties-geoid) \
		-filter-fields GEOID \
		-o $@ combine-layers format=geojson

## build/geography/districts.geojson             : Convert district shapefiles to geojson
build/geography/districts.geojson: build/shp/2013_Unified_Elementary_SD.shp
	mkdir -p $(dir $@)
	mapshaper ./build/shp/*.shp combine-files \
		-filter-fields GEOID,NAME \
		-uniq GEOID \
		-o $@ combine-layers format=geojson

## build/geography/schools.geojson               : Create GeoJSON for schools
build/geography/schools.geojson:
	mkdir -p $(dir $@)
	echo "Not yet implemented"

build/shp/2013_Unified_Elementary_SD.shp:
	unzip -d build/shp SEDA_shapefiles_v21.zip

### DATA

## build/processed/%.csv                     : Data for districts
build/processed/%.csv:
	mkdir -p $(dir $@)
	cat dictionaries/$*_dictionary.csv | \
	python3 scripts/create_data_from_dictionary.py > $@

build/processed/%-centers.csv: build/processed/%.csv
	mkdir -p $(dir $@)
	csvcut -c id,name $^ > $@
