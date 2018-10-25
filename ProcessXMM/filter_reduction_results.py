import os
from glob import glob
import re
import h5py
import numpy as np

# Change directory to the XMM Data directory
# Here we have many folders named obsID
# where obsID is a 10 digit number
xmm_data_dir = '/nfs/turbo/bsafdi/xmm-data/'
os.chdir(xmm_data_dir)

# Get a list of all the obsIDs in the relevant folder
# This line takes a list of all the files and folders in xmm_data_dir
# and removes entries which are not 10 digit numbers
obsID_list = np.array(filter(lambda dirname: re.match(r'[0-9]{10}', dirname), glob('*')))

# Clear the list of bad obsIDs (ones that didn't complete) for rewriting below
BS_dir = xmm_data_dir + 'Blank_Sky/'
with open(BS_dir + 'bad_obsdetprefs.txt','a+') as f:
    f.truncate(0)
    
# Initialize list of completed obsdetprefs
obsdetpref_list = []

# Initialize list of their exposure times (for ranking)
exp_list = []

for obsID in obsID_list:
    # Change directory to the relevant observation folder
    obsID_dir = xmm_data_dir + obsID
    os.chdir(obsID_dir)

    # Define file names to open later
    mos_exp_file = obsID_dir + '/' + 'mos_exposures.txt'
    pn_exp_file = obsID_dir + '/' + 'pn_exposures.txt'
    
    # Read off the exposure numbers
    # Each of these exposures should have an associated data file
    # If the file doesn't exist, there are no exposures for that detector
    if os.path.isfile(mos_exp_file):
        with open(mos_exp_file,'r') as mos_file:
            # Reads out each line into a new element of a list
            mos_exposures = [line.strip().upper() for line in mos_file]
    else:
        mos_exposures = []
    if os.path.isfile(pn_exp_file):
        with open(pn_exp_file,'r') as pn_file:
            pn_exposures = [line.strip().upper() for line in pn_file]
    else:
        pn_exposures = []

    # Add the detector in front of the prefix
    # This gives the exposure information
    for exp in mos_exposures:
        # Define some identifying strings
        detpref = 'mos' + exp.upper()
        obsdetpref = obsID + detpref
        
        # Check if the data reduction completed
        out_file = obsID_dir + '/' + detpref + '_processed.h5'

        if os.path.isfile(out_file):
            obsdetpref_list.append(obsdetpref)
            processed_data = h5py.File(out_file, 'r')
            exp = processed_data['exp'].value
            exp_list.append(exp)
            processed_data.close()
        else:
            # Write the obsdetpref to the list of bad observations
            with open(BS_dir + 'bad_obsdetprefs.txt','a+') as f:
                f.write(obsdetpref + '\n')
                
    for exp in pn_exposures:
        # Define some identifying strings
        detpref = 'pn' + exp.upper()
        obsdetpref = obsID + detpref
        
        # Load in the results of the data reduction
        out_file = obsID_dir + '/' + detpref + '_processed.h5'
        
        if os.path.isfile(out_file):
            obsdetpref_list.append(obsdetpref)
            processed_data = h5py.File(out_file, 'r')
            exp = processed_data['exp'].value
            exp_list.append(exp)
            processed_data.close()
        else:
            # Write the obsdetpref to the list of bad observations
            with open(BS_dir + 'bad_obsdetprefs.txt','a+') as f:
                f.write(obsdetpref + '\n')

# Rank the list by exposure times
print exp_list[:5]
print obsdetpref_list[:5]
ranked_obsdetpref_list = [obsdetpref for _,obsdetpref in sorted(zip(exp_list,obsdetpref_list))]
ranked_obsdetpref_list = ranked_obsdetpref_list[::-1]
print ranked_obsdetpref_list[:5]

# Save the list of obsdetprefs here
ranked_observations = BS_dir + 'ranked_observations.h5'

# Save the collective data to a .h5 file in the Blank Sky directory
h5f = h5py.File(ranked_observations, 'w')
h5f.create_dataset('obsdetpref_list',data=ranked_obsdetpref_list)
