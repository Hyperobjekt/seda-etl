import os
import sys
import csv
import pandas as pd
import numpy as np
from data_types import get_dtypes_dict

def strip_flags(df, col):
  if col in df.columns:
    df[col] = df[col].replace(0, '')
  return df

def strip_value(df, val):
  """Return data frame with "unavailable" numeric value removed
  """
  df = df.replace(val, np.nan)
  df = df.round(3)
  return df

if __name__ == '__main__':

  region = sys.argv[1]
  dtypes = get_dtypes_dict(region)
  flag_cols = [ 'r', 'u', 's', 't', 'mg', 'ch', 'm', 'e', 'c', 'bie' ]

  # Read the data dictionary from stdin
  data_df = pd.read_csv(sys.stdin, dtype=dtypes)

  # strip the value to create output
  output_df = strip_value(data_df, -999)
  for col in flag_cols:
    output_df = strip_flags(output_df, col)

  output_df.to_csv(sys.stdout, index=False)
