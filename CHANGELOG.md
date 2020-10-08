# CHANGELOG

## 10/08/2020

- improved entrypoint (`build.sh`) to allow building separate data types with flags (`--data`, `--tiles`, `--search`)
- updated `clean_data.py` to cast flag columns to int to reduce overall data size
- add new `explorer` tasks to the makefile that strip margin of error and remove `.0` suffix from any numbers

## 10/07/2020

- added new flag columns to districts and schools data set
  - `r`: rural
  - `u`: urban
  - `s`: suburban
  - `t`: town
- added new flag columns to schools dataset
  - `mg`: magnet
  - `ch`: charter
- updated source data to use 2019 shapefile
