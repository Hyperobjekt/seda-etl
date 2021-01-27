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

OUTPUT_DIR = os.path.join(BASE_DIR, 'build', 'scatterplot', 'schools', 'reduced')

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
    px = p[1]
    py = p[2]
    pz = p[3]
    if np.isnan(px) or np.isnan(py) or np.isnan(pz) or px == -999 or py == -999 or pz == -999:
      continue
    nearby = index.intersection((px - r, py - r, px + r, py + r))
    if all(dist([px, py], [points[j][1], points[j][2]]) >= r for j in nearby):
      result.append(p)
      index.insert(i, (px, py, px, py))
  return result

def extract_tuples(df, cols):
  """Return tuples containing the id, and values for
  the provided xVar, yVar, zVar
  """
  subset = df[cols]
  tuples = [tuple(x) for x in subset.values]
  return tuples

def create_pair_csv(region, df, xVar, yVar, zVar, radius):
  """Write a csv file from the dataframe with id, xVar, yVar columns
  sampling only one point from within the provided radius.
  Points with a higher zVar value have priority. 
  """

  # make sure the columns exist in the data set
  if xVar == yVar or xVar not in df.columns or yVar not in df.columns or zVar not in df.columns:
    print("skipping x / y pair " + xVar + ", " + yVar ,file=sys.stderr)
    return

  # extract data into tuples
  output_cols = [ 'id', xVar, yVar, zVar ]
  tuples = extract_tuples(df, output_cols)

  # get subset of points
  subset = get_subset(tuples, radius)

  # convert tuples to new csv
  output_file = os.path.join(OUTPUT_DIR, xVar + '-' + yVar + '.csv')
  output_df = pd.DataFrame(subset)
  # output_df['id'] = output_df.index
  output_df = output_df[[0]]
  # output_df = output_df.round(3)
  try:
    output_df.columns = ['id']
    output_df.to_csv(output_file, index=False)
    print("reduced", xVar, "/", yVar, "pair to",str(output_df.shape[0]),"points. (", 100*output_df.shape[0]/df.shape[0], "%)")
  except ValueError:
    print("error witing file", xVar, yVar)

if __name__ == '__main__':

  region = sys.argv[1]
  radius = float(sys.argv[2])
  dtypes = get_dtypes_dict(region)
  zVar = 'all_sz'

  # create pairs with these columns
  y_vars = ['all_avg', 'all_grd', 'all_coh']

  # Read the data dictionary from stdin
  data_df = pd.read_csv(
    os.path.join(DATA_DIR, region + '.csv'),
    dtype=dtypes
  )

  # sort by zVar so the largest are selected
  data_df = data_df.sort_values(by=[zVar], ascending=False)

  # sort the columns in alphabetic order for consistent var names
  data_df = data_df.reindex(sorted(data_df.columns), axis=1)

  # loop through all columns and make pairs
  for col in y_vars:
    create_pair_csv(region, data_df, col, 'all_frl', zVar, radius)


