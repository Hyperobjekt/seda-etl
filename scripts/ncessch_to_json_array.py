import os
import sys
import csv
import json
import pandas as pd
import numpy as np

if __name__ == '__main__':

  # Read the data dictionary from stdin
  data_df = pd.read_csv(sys.stdin, converters={
      'ncessch': '{:0>12}'.format
    })
  ids = data_df["ncessch"].tolist()
  output = json.dumps(ids)
  print(output)