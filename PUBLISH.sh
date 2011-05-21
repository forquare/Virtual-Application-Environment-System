#!/bin/sh
# 
# Copyright © 2010, Ben Lavery
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#        this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright notice,
#        this list of conditions and the following disclaimer in the documentation
#        and/or other materials provided with the distribution.
#     * Neither the name of hashbang0.com nor the names of its
#       contributors may be used to endorse or promote products derived from
#       this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE 
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, 
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE 
# USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Author Ben Lavery
# Version: 1
###############################################################################
# The script will call BUILD_DOWNLOADS.sh the upload the bz2 files and 
# INSTALL.bash to the dissertation website.
# It will also turn key folders/files containing scripts or templates into 
# Tape ARchives (tar files) then compress them using bzip2 compression.
# Script will echo when it is starting and when it has finished each action.
###############################################################################

stats(){
	NOF=0
	
	echo "Calculating lines coded"
	NOL=0
	NOLNC=0
	NOBL=0
	for EACH in `find . | grep -vi svn | grep -vi metadata`; do
		if [[ `file $EACH` =~ "text" ]]; then
			LINES=`cat $EACH | egrep -v "$^" | wc -l`
			NOL=$(( $NOL + $LINES ))
			
			LINES=`cat $EACH | grep -v "#" | egrep -v "$^" | wc -l`
			NOLNC=$(( $NOLNC + $LINES ))
			
			LINES=`cat $EACH | egrep "$^" | wc -l`
			NOBL=$(( $NOBL + $LINES ))
			
			NOF=$(( $NOF + 1 ))
		fi
	done

	echo "Stats:"
	echo "    Total number of lines: $NOL"
	echo "    Total number of lines (less comments): $NOLNC"
	echo "    Total number of comments: $(( $NOL - $NOLNC ))"
	echo "    Total number of blank line: $NOBL"
	echo "    Accross $NOF files"
}

if [[ $1 =~ "stats" ]]; then
	stats
	exit 0
fi

#Generate final packaged name (VAES + timestamp)
NAME=`date | awk '{ print $2$3$4"-"$5 }' | sed 's/:/-/g'`
NAME=`echo vaes-$NAME.tar`

#########################################
tar -cf build/pkg.tar pkg
tar -cf build/zone_templates.tar zone_templates
tar -cf build/net.tar net
cp zone_setup.sh build/zone_setup.sh
cp network_setup.sh build/network_setup.sh
cp INSTALL.sh build/INSTALL.sh
cp custom_ypinit.sh build/custom_ypinit.sh
cp get_hash.pl build/get_hash.pl

cd build

bzip2 pkg.tar
bzip2 zone_templates.tar
bzip2 zone_setup.sh
bzip2 network_setup.sh
bzip2 net.tar
bzip2 custom_ypinit.sh
bzip2 get_hash.pl

tar -cf $NAME *
bzip2 $NAME
#########################################

scp $NAME.bz2 admin@diss-web:/web/diss/

rm *

cd ../

stats

date