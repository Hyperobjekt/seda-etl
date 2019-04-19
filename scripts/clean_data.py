import os
import sys
import csv
import rtree
import math
import re
import pandas as pd
import numpy as np
from data_types import get_dtypes_dict

ID_LEN_DICT = {
  'counties': 5,
  'districts': 7,
  'schools': 12
}

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'build')

OUTPUT_DIR = os.path.join(BASE_DIR, 'build', 'reduced')

def clean_id(df, region, col='id'):
  """Returns a dataframe with the proper ID length for the
  provided region.  
  """
  id_len = ID_LEN_DICT[region]
  df[col] = df[col].str.rjust(id_len, '0')
  return df

def clean_name(df, region, col='name'):
  """Removes rows with no name, and formats school names
  if the region is schools.
  """
  df = df[df[col] != '-9999']
  df.dropna(subset=[col],inplace=True)
  if region == 'schools':
    df[col] = df[col].str.replace('elem sch$|el$', 'elementary', case=False)
    df[col] = df[col].str.replace(' sch$| school$', '', case=False)
  df[col] = df[col].str.title()
  return df

def clean_numbers(df, precision=3):
  """Return data frame with "unavailable" numeric value removed
  and rounded numbers
  """
  df = df.replace(-9999, np.nan)
  df = df.round(precision)
  return df

def clean_data(df, region, precision=3):
  """Strips unavailable data markers, round number cols and 
  cleans up names.
  """
  if 'id' in df.columns:
    df = clean_id(df, region)
  if 'name' in df.columns:
    df = clean_name(df, region)
  return clean_numbers(df, precision)

if __name__ == '__main__':

  region = sys.argv[1]
  dtypes = get_dtypes_dict(region)

  # Read the data dictionary from stdin
  data_df = pd.read_csv(sys.stdin, dtype=dtypes)

  output_df = clean_data(data_df, region)
  output_df.to_csv(sys.stdout, index=False)