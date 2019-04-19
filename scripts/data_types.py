import os
import sys

import pandas as pd

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DICT_DIR = os.path.join(BASE_DIR, 'dictionaries')

def get_dtypes_dict(region):
  dict_df = pd.read_csv(
    os.path.join(DICT_DIR, region + '_dictionary.csv'), 
    keep_default_na=False, 
    dtype='object')
  df = dict_df[['output_column', 'type']].drop_duplicates('output_column')
  return pd.Series(df['type'].values,index=df['output_column']).to_dict()

if __name__ == '__main__':
  print(get_dtypes_dict(sys.argv[1]))
