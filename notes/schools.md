# Structuring School Data

Challenge: there are 70,000+ data points it is too resource intensive to load, parse, and render them all at once

Solution:
  - **For national data:** For each variable pairing, reduce the number of points by keeping only a single point within a given radius. There are usually ~10,000 points in these files after reduction.  The meta data needs to be included in each file because the schools are different in each one, and loading the meta data for all 70,000 schools at once is too much.
  - **For state data:** Data is structured the same way as it is for districts and counties, but each state's data is in its own file (whereas districts and counties are all contained in a single file).  Each state folder contains a meta file for all the schools in the state, and then a single file for each metric.