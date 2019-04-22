# Structuring Scatterplot Data

## County Data

Challenge: Allow users plot a large number of county variables but keep file sizes reasonable and allow requesting data on demand.

Solution: Break data for each variable and its identifier into a separate file.  Request data as needed and cache it in the local app state once it has loaded.  Create a meta file that contains the non-data fields (like name, size, etc.)

Output structure:

```
- scatterplot/
  |
  - meta/
      districts.csv
      counties.csv
  - districts/
      all_avg.csv
      all_grd.csv
      ...
  - counties/
      all_avg.csv
      all_grd.csv
      ...
```


## School Data

Challenge: there are 70,000+ school data points it is too resource intensive to load, parse, and render them all at once on the front end.

Solution:
  - **For national data:** For each variable pairing, reduce the number of points by keeping only a single point within a given radius. There are usually ~10,000 points in these files after reduction.  The meta data needs to be included in each file because the schools are different in each one, and loading the meta data for all 70,000 schools at once is too much.
  - **For state data:** Data is structured the same way as it is for districts and counties, but each state's data is in its own file (whereas districts and counties are all contained in a single file).  Each state folder contains a meta file for all the schools in the state, and then a single file for each metric.

Output structure:

```
- scatterplot/
  |
  - meta/
    |
    - schools/
        01.csv
        02.csv
        ...
  - schools/
        all_avg.csv
        all_coh.csv
        ...
        - reduced/
            all_avg-all_grd.csv
            all_avg-all_coh.csv
        - 01/
            all_avg.csv
            all_coh.csv
            ...
        - 02/
            all_avg.csv
            all_coh.csv
            ...
```


