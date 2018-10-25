# XMM-DM

**Tools for processing XMM-Newton data and supplementary data for a 3.5 keV analysis**

[![arXiv](https://img.shields.io/badge/arXiv-18xx.0xxxx%20-green.svg)](https://arxiv.org/abs/18xx.0xxxx)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

![limit_3p5](https://github.com/nickrodd/XMM-DM/blob/master/SuppData/limit_final.png "3.5 keV limit from XMM-Newton")

XMM-DM is a repository containing the important code used in [18xx.0xxxxx](https://arxiv.org/pdf/18xx.0xxxx.pdf), and the supplementary data for the analysis.
That analysis performed a search for the 3.5 keV line resulting from dark matter (DM) decay in data collected by the [XMM-Newton](https://www.cosmos.esa.int/web/xmm-newton) X-ray space telescope.

## Authors

-  Chris Dessert; dessert at umich dot edu
-  Nicholas Rodd; nrodd at berkeley dot edu
-  Benjamin Safdi; bsafdi at umich dot edu

## Processing XMM-Newton data

A central aspect of the analysis performed in  was processing a large number of XMM-Newton datasets. 
In `ProcessXMM` we provide the code written for this purpose.

## Supplementary Data for [18xx.0xxxxx](https://arxiv.org/pdf/18xx.0xxxx.pdf)

In `SuppData` we present the supplementary data associated with the 3.5 keV line analysis in [18xx.0xxxxx](https://arxiv.org/pdf/18xx.0xxxx.pdf). 
In detail, we include:

1. `obslist`: the full list of observations included in the analysis. 
