import os
import sys
import csv
import pandas as pd
import numpy as np

if __name__ == '__main__':

  BASE_DIR = os.path.dirname(os.path.dirname(__file__))

  if len(sys.argv) > 1:
    DATA_DIR = os.path.join(BASE_DIR, sys.argv[1])
  else:
    DATA_DIR = os.path.join(BASE_DIR, 'build', 'data')
  
  # Read the data dictionary from stdin
  dict_df = pd.read_csv(
    sys.stdin, 
    keep_default_na=False, 
    dtype='object')
  
  # Get all of the files needed to generate the output
  files = dict_df.source_file.unique()

  data_df_list = [] 
  for f in files:
    # get input data types
    if 'type' in dict_df.columns:
      dtypes_df = dict_df.loc[
        (dict_df['source_file'] == f) & (dict_df['type'] != '')
      ]
      dtypes_dict = pd.Series(
        dtypes_df['type'].values,index=dtypes_df['column']).to_dict()
    else:
      dtypes_dict = {}
    # load csv, make sure identifiers are proper length 
    data_df_list.append(
      pd.read_csv(
        os.path.join(DATA_DIR, f),
        encoding='windows-1251',
        dtype=dtypes_dict,
        converters={
          'countyid': '{:0>5}'.format,
          'leaid': '{:0>7}'.format,
          'leaidC': '{:0>7}'.format,
          'ncessch': '{:0>12}'.format
        }
      )
    )
  
  # Two types of rows

  # A. Identifier is unique
  #     - pull the columns from the file
  output_a_df_list = []
  for i, df in enumerate(data_df_list):
    copy_df = dict_df.loc[
      (dict_df['source_file'] == files[i]) & (dict_df['row_condition'] == '')
    ]
    if not copy_df.empty:
      values_df = df[copy_df.column.values].drop_duplicates()
      values_df.columns = copy_df.output_column.values
      values_df.set_index('id', inplace=True)
      output_a_df_list.append(values_df)
  output_a_df = pd.concat(output_a_df_list, axis=1)

  # B. Identifier is not unique in the file, so row condition is provided
  #    - loop through each file and get each data prop based on row condition
  output_b_df_list = []
  for i, df in enumerate(data_df_list):
    copy_df = dict_df.loc[
      (dict_df['source_file'] == files[i]) & (dict_df['row_condition'] != '')
    ]
    if not copy_df.empty:
      # get columns by row condition
      by_condition_df = copy_df.groupby('row_condition').apply(
          lambda x: pd.Series(dict(
                      output_column = "%s" % ','.join(x['output_column']),
                      column = "%s" % ','.join(x['column'])))
          ).reset_index()

      # output a df for each row condition and add to a list
      values_df_list = []
      for index, row in by_condition_df.iterrows():
        from_cols = row['column'].split(",")
        to_cols = row['output_column'].split(",")
        conditions = row['row_condition'].split(" ")
        values_df = df.loc[df[conditions[0]] == conditions[2]][from_cols]
        values_df.columns = to_cols
        values_df.set_index('id', inplace=True)
        values_df_list.append(values_df)
      # combine data for all row conditions
      output_b_df_list.append(
        pd.concat(values_df_list, axis=1)
      )
  # combine data from all files
  output_b_df = pd.concat(output_b_df_list, axis=1)

output_df = pd.concat(
  [output_a_df, output_b_df], axis=1)

# fill in the names column if there are multiple
if 'name2' in output_df.columns:
  output_df['name'] = output_df[['name', 'name2']].apply(
    lambda x: x[1] if pd.isnull(x[0]) else x[0], axis=1)
  output_df.drop(['name2'], axis=1, inplace=True)

# if data set has coordinates, strip out rows missing them
if 'lat' in output_df.columns:
  output_df = output_df[pd.notnull(output_df['lat'])]

# fill in missing numeric values
output_df = output_df.fillna(-9999)
output_df = output_df.round(3)
output_df = output_df.reset_index()
output_df[['fid']] = output_df[['index']].apply(pd.to_numeric)
output_df.set_index('index', inplace=True)
output_df.to_csv(sys.stdout, index_label='id')
