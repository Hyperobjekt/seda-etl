import os
import numpy as np
import pandas as pd
import geopandas as gpd
from shapely import geometry

upcast_dispatch = {geometry.Point: geometry.MultiPoint, 
                   geometry.LineString: geometry.MultiLineString, 
                   geometry.Polygon: geometry.MultiPolygon}

def maybe_cast_to_multigeometry(geom):
    caster = upcast_dispatch.get(type(geom), lambda x: x[0])
    return caster([geom])

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'build')
GEOJSON_DIR = os.path.join(BASE_DIR, 'build', 'geography')
OUTPUT_DIR = os.path.join(BASE_DIR, 'build', 'export')
STATES_FILE = os.path.join(BASE_DIR, 'static', 'states.csv')

GEO_TYPE_LEN = {
  'counties': 5,
  'districts': 7,
  'schools': 12
}

def create_state_csvs(df, region, fips, state):
  """Output the csv data for the provided state to a file
  """
  print("writing {} csv for {}".format(region, state))
  if not os.path.isdir(os.path.join(OUTPUT_DIR, state)):
    os.mkdir(os.path.join(OUTPUT_DIR, state))
  df.loc[df['id'].str.startswith(fips)].to_csv(
    os.path.join(OUTPUT_DIR, state, '{}.csv'.format(region)), index=False)

def create_state_geojson(df, region, fips, state):
  """Output the geojson data for the provided state to a file
  """
  print("writing {} geojson for {}".format(region, state))
  filename = os.path.join(OUTPUT_DIR, state, '{}.geojson'.format(region))
  geo_df.loc[geo_df['id'].str.startswith(fips)].to_file(
    filename, driver='GeoJSON')


if __name__ == '__main__':

  if not os.path.isdir(OUTPUT_DIR):
    os.mkdir(OUTPUT_DIR)
  
  if not os.path.isdir(os.path.join(OUTPUT_DIR, 'US')):
    os.mkdir(os.path.join(OUTPUT_DIR, 'US'))

  # read in states
  states_df = pd.read_csv(
    STATES_FILE, 
    usecols=['fips', 'state'], 
    dtype={ 'fips': 'object', 'state': 'object'})
  state_fips = {
      s[0]: s[1].upper()
      for s in zip(states_df.fips, states_df.state)
  }

  # generate for each geo type
  for k, v in GEO_TYPE_LEN.items():
    # read in master data file
    data_df = pd.read_csv(
      os.path.join(DATA_DIR, '{}.csv'.format(k)),
      dtype={
        'id': 'object',
        'name': 'object'
      }
    )
    # read in geojson file
    geo_df = gpd.read_file(
      os.path.join(GEOJSON_DIR, '{}.geojson'.format(k)),
      driver='GeoJSON')
    geo_df['geometry'] = geo_df['geometry'].apply(maybe_cast_to_multigeometry)

    # output state level csv and geojson
    for fips, state in state_fips.items():
      create_state_csvs(data_df, k, fips, state)
      create_state_geojson(geo_df, k, fips, state)

    # output national level geojson
    geo_file = os.path.join(OUTPUT_DIR, 'US', '{}.geojson'.format(k))
    geo_df.to_file(geo_file, driver='GeoJSON')

    # output national level csv
    csv_file = os.path.join(OUTPUT_DIR, state, '{}.csv'.format(k))
    data_df.to_csv(csv_file, index=False)