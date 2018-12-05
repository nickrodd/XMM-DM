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

The code is a combination of bash and Python. The code requires installation of both the [XMM-SAS](https://xmm-tools.cosmos.esa.int/external/xmm_user_support/documentation/sas_usg/USG/) and [HEADAS](https://heasarc.nasa.gov/lheasoft/) softwares. In addition the python modules [numpy](http://www.numpy.org/), [astropy](http://www.astropy.org/), [h5py](https://www.h5py.org/), [beautifulsoup4](https://pypi.org/project/beautifulsoup4/), and [pandas](https://pandas.pydata.org/) are required.

To use the code, first establish the directories where the XMM tools are installed and the output data should be written in `set_dirs.sh`. Then to process all exposures associated with an observation with ID `obsID`, use

```
./dl2dat.sh $obsID
```

The code will then process the observation if possible, and explain why if not. The output data in h5py format, along with a summary of the processing will be stored in `xmmdata/obsID`, where `xmmdata` is defined in `set_dirs.sh`.

Two words of caution regarding the code:

- More recent versions of the XMM-SAS package are shipped with their own python installation, that is loaded along with the tools. This will replace your default python environment and does not contain some of the packages required to run this processing code. This problem can be avoided by commenting out the lines loading python within the `setsas.sh`, `setsas.csh`, `sas-setup.sh`, and `sas-setup.csh` files within the SAS directory.
- The processing code can be run in parallel across a number of observations. Nevertheless, one obstacle to running a large number in parallel is that the XMM-SAS tools write and edit several common files that are independent of the observation ID, which will lead to a crash if two observations reach this point simultaneously. We have found making a unique copy of the XMM-SAS tools for each observation ID significantly increases the number of IDs that can be processed in parallel.


## Supplementary Data for [1812.0xxxxx](https://arxiv.org/abs/1812.0xxxx)

In `SuppData/Fiducial_Exposures.csv` we provide the full list of 1,397 exposures used in the fiducial 3.5 keV line analysis of [1812.0xxxxx](https://arxiv.org/abs/1812.0xxxx). For each exposure, the following information is provided: 

1. `Observation ID`: the 10 digit identifier for this observation.
2. `Camera`: the camera this exposure was collected with, MOS1, MOS2, or PN.
3. `Exposure Identifier`: the unique identifier for this exposure given the camera and observation ID.
4. `Exposure Time (ks)`: the length of this exposure [ks].
5. `Galactic l (degrees)`: the location of this exposure in galactic longitude [deg].
6. `Galactic b (degree)`: the location of this exposure in galactic latitude [deg].
7. `Target Type`: the intended target of the observation.
