import os
import sys
import csv
import pandas as pd
import numpy as np

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'build', 'data')

if __name__ == '__main__':

  # Read the data dictionary from stdin
  dict_df = pd.read_csv(
    sys.stdin, 
    keep_default_na=False, 
    dtype={ 'row_condition' : 'object' })
  
  # Get all of the files needed to generate the output
  files = dict_df.source_file.unique()

  data_df_list = [] 
  for f in files: 
    data_df_list.append(
      pd.read_csv(
        os.path.join(DATA_DIR, f),
        dtype={ 
          'leaidC': 'object', 
          'name': 'object' 
        }
      )
    )
  
  # Two types of files

  # A. Identifier is unique
  #     - pull the columns from the file
  output_a_df_list = []
  for i, df in enumerate(data_df_list):
    copy_df = dict_df.loc[
      (dict_df['source_file'] == files[i]) & (dict_df['row_condition'] == '')
    ]
    if not copy_df.empty:
      values_df = df[copy_df.column.values]
      values_df.columns = copy_df.output_column.values
      values_df.set_index('id', inplace=True)
      output_a_df_list.append(values_df)
  output_a_df = pd.concat(output_a_df_list, axis=1)

  # B. Identifier is not unique in the file
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

output_df.to_csv(sys.stdout, index_label='id')
