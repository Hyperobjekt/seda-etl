import os
import sys
import csv
from algoliasearch import algoliasearch

ALGOLIA_ID = os.getenv('ALGOLIA_ID')
ALGOLIA_KEY = os.getenv('ALGOLIA_KEY')
ALGOLIA_INDEX = sys.argv[2]

if __name__ == '__main__':

  data = []

  with open(sys.argv[1]) as f:
    reader = csv.DictReader(f)
    for row in reader:
      try:
        row['_geoloc'] = {
          "lat": float(row['lat']),
          "lng": float(row['lon'])
        },
        row['lat'] = float(row['lat'])
        row['lon'] = float(row['lon'])
        
        if row['all_sz']:
          row['all_sz'] = float(row['all_sz'])
        else:
          row['all_sz'] = 0
        
        if row['all_avg']:
          row['all_avg'] = float(row['all_avg'])
        else:
          row['all_avg'] = -999

        if row['all_grd']:
          row['all_grd'] = float(row['all_grd'])
        else:
          row['all_grd'] = -999

        if row['all_coh']:
          row['all_coh'] = float(row['all_coh'])
        else:
          row['all_coh'] = -999

        # if row['all_ses']:
        #   row['all_ses'] = float(row['all_ses'])
        # else:
        #   row['all_ses'] = -999

        data.append(row)
      except ValueError as e:
        print('Invalid lat or lon, skipping', row['name'])

  client = algoliasearch.Client(ALGOLIA_ID, ALGOLIA_KEY)
  index = client.init_index(ALGOLIA_INDEX)
  index.replace_all_objects(data)
