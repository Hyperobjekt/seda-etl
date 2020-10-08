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
    'states': 2,
    'counties': 5,
    'districts': 7,
    'schools': 12
}

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'build')
STATES_FILE = os.path.join(BASE_DIR, 'static', 'states.csv')

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
    # df = df.loc[df[col] != '-999'].copy()
    # df.dropna(subset=[col],inplace=True) # COMMENTED OUT TO KEEP DATA WITHOUT NAMES (03/11/20)
    if region == 'schools':
        df[col] = df[col].str.replace(
            'elem sch$|el$', 'elementary', case=False)
        df[col] = df[col].str.replace(' sch$| school$', '', case=False)
    # df[col] = df[col].str.title()
    return df


def clean_city_name(df, col='city'):
    """Title case all city names
    """
    df[col] = df[col].str.title()
    return df


def clean_numbers(df, precision=3):
    """Return data frame with "unavailable" numeric value removed
    and rounded numbers
    """
    # df = df.replace(-999, np.nan)
    df = df.round(precision)
    return df


def clean_flags(df, cols):
    """Convert all flag columns to int"""
    print("CLEANING FLAGS", file=sys.stderr)
    for col in cols:
        df[col].astype(int)
    return df


def clean_data(df, region, precision=3):
    """Strips unavailable data markers, round number cols and 
    cleans up names.
    """
    if 'id' in df.columns:
        df = clean_id(df, region)
    if 'name' in df.columns:
        df = clean_name(df, region)
    if 'state' in df.columns:
        df = add_state_name(df, 'state')
    if 'city' in df.columns:
        df = clean_city_name(df, 'city')
    # round numbers
    df = clean_numbers(df, precision)
    # rural, urban, suburban, town flags
    if 'r' in df.columns:
        df = df.astype({"r": int, "u": int, "s": int, "t": int})
    # charter, magnet flags
    if 'ch' in df.columns:
        df = df.astype({"ch": int, "mg": int})
    return df


def add_state_name(df, abbrCol='state'):
    """Adds the full state name to the dataframe based on
    a column with the abbreviation
    """
    states_df = pd.read_csv(
        STATES_FILE, usecols=['state_name', 'state'])
    return pd.merge(df, states_df, left_on=abbrCol, right_on='state', how='left')


if __name__ == '__main__':

    region = sys.argv[1]
    dtypes = get_dtypes_dict(region)

    # Read the data dictionary from stdin
    data_df = pd.read_csv(sys.stdin, dtype=dtypes)

    output_df = clean_data(data_df, region)
    output_df.to_csv(sys.stdout, index=False)
