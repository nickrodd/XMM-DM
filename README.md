# XMM-DM

**Tools for processing XMM-Newton data and supplementary data for a 3.5 keV analysis**

[![arXiv](https://img.shields.io/badge/arXiv-1812.0xxxx%20-green.svg)](https://arxiv.org/abs/1812.0xxxx)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

![limit_3p5](https://github.com/nickrodd/XMM-DM/blob/master/SuppData/limit_final.png "3.5 keV limit from XMM-Newton")

XMM-DM is a repository containing the data-reduction code used in [1812.0xxxxx](https://arxiv.org/abs/1812.0xxxx), and the supplementary data for the analysis.
That analysis performed a search for the 3.5 keV line resulting from dark matter (DM) decay in data collected by the [XMM-Newton](https://www.cosmos.esa.int/web/xmm-newton) X-ray space telescope.

## Authors

-  Chris Dessert; dessert at umich dot edu
-  Nicholas Rodd; nrodd at berkeley dot edu
-  Benjamin Safdi; bsafdi at umich dot edu

## Processing XMM-Newton Data

A central aspect of the analysis performed in [1812.0xxxxx](https://arxiv.org/abs/1812.0xxxx) was processing a large number of XMM-Newton datasets. In `ProcessXMM` we provide the code written for this purpose.


## Supplementary Data for [1812.0xxxxx](https://arxiv.org/abs/1812.0xxxx)

In `SuppData/Fiducial_Exposures.csv` we provide the full list of 1,397 exposures used in the fiducial 3.5 keV line analysis of [1812.0xxxxx](https://arxiv.org/abs/1812.0xxxx). For each exposure, the following information is provided: 

1. `Observation ID`: the 10 digit identifier for this observation.
2. `Camera`: the camera this exposure was collected with, MOS1, MOS2, or PN.
3. `Exposure Identifier`: the unique identifier for this exposure given the camera and observation ID.
4. `Exposure Time (ks)`: the length of this exposure [ks].
5. `Galactic l (degrees)`: the location of this exposure in galactic longitude [deg].
6. `Galactic b (degree)`: the location of this exposure in galactic latitude [deg].
7. `Target Type`: the intended target of the observation.
