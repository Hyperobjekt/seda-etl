import os
import sys
import csv
import rtree
import math
import pandas as pd
import numpy as np
from data_types import get_dtypes_dict

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'build')

OUTPUT_DIR = os.path.join(BASE_DIR, 'build', 'reduced')

def dist(p, q):
  "Return the Euclidean distance between points p and q."
  return math.hypot(p[0] - q[0], p[1] - q[1])

def get_subset(points, r):
  """Return a maximal list of elements of points such that no pairs of
  points in the result have distance less than r.
  """
  result = []
  index = rtree.index.Index()
  for i, p in enumerate(points):
    geoid, px, py = p
    if px == -9999 or py == -9999:
      continue
    nearby = index.intersection((px - r, py - r, px + r, py + r))
    if all(dist([p[1], p[2]], [points[j][1], points[j][2]]) >= r for j in nearby):
      result.append(p)
      index.insert(i, (px, py, px, py))
  return result

def extract_tuples(df, xVar, yVar, zVar):
  """Return tuples containing the id, and values for
  the provided xVar, yVar, zVar
  """
  subset = df[['id', xVar, yVar]]
  tuples = [tuple(x) for x in subset.values]
  return tuples

def create_pair_csv(region, df, xVar, yVar, zVar, radius):
  """Write a csv file from the dataframe with id, xVar, yVar columns
  sampling only one point from within the provided radius.
  Points with a higher zVar value have priority. 
  """
  # no file needed when x and y are the same
  if xVar == yVar:
    return

  # make sure the columns exist in the data set
  if xVar not in df.columns or yVar not in df.columns or zVar not in df.columns:
    print("skipping x / y pair, var does not exist " + xVar + ", " + yVar ,file=sys.stderr)
    return

  # extract data into tuples
  tuples = extract_tuples(data_df, xVar, yVar, zVar)

  # get subset of points
  subset = get_subset(tuples, radius)

  output_file = os.path.join(OUTPUT_DIR, region, xVar + '-' + yVar + '.csv')

  # convert tuples to new csv
  output_df = pd.DataFrame(subset)
  output_df = output_df.round(2)
  try:
    output_df.columns = [ 'id', xVar, yVar ]
    output_df.to_csv(output_file, index=False)
    print("wrote", output_file)
  except ValueError:
    print("error", xVar, yVar, output_df)

if __name__ == '__main__':

  region = sys.argv[1]
  radius = float(sys.argv[2])
  dtypes = get_dtypes_dict(region)
  zVar = 'sz'

  # do not create pairs with these columns
  no_pairs = [ 'id', 'state', 'name', 'lon', 'lat', 'fid', 'sz' ]

  # Read the data dictionary from stdin
  data_df = pd.read_csv(
    os.path.join(DATA_DIR, region + '.csv'),
    dtype=dtypes
  )

  # sort by zVar so the largest are selected
  data_df = data_df.sort_values(by=[zVar], ascending=False)

  data_df = data_df.reindex(sorted(data_df.columns), axis=1)

  for i, c1 in enumerate(data_df.columns):
    for c2 in data_df.columns[i:]:
      if c1 != c2 and c1 not in no_pairs and c2 not in no_pairs:
        create_pair_csv(region, data_df, c1, c2, zVar, radius)

