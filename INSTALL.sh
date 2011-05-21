#!/bin/bash
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
# Version: 1.7
###############################################################################
# THE SCRIPT NEEDS TO BE RUN AS THE ROOT USER WITH A PRIVALEGED ROLE.  
# THIS CAN BE EMULATED USING THE PFEXEC COMMAND.  THE USER ABLE TO DO THIS IS
# USUALLY DEFINED ON INSTALLTION ALONG WITH THE ROOT PASSWORD.  THIS SCRIPT 
# NEEDS ROOT PERMISSIONS TO MOVE SYSTEM FILES.
###############################################################################
# This script will do the following:
# * Move nessesary resources to /tmp then unpackage them.
# * Start the network setup script to set up virtual network.
# * Move template files to /var/zone_templates (creating dir if it's not there)
# * Sets up global zone as NIS master
# * Install configuration file.
# * Start the zone setup script to create master zone.
# * Rename old `pkg` command and replace it with new `pkg` script
#       and ensures the permissions and owners are correct.
# * Cleans up downloaded files.
###############################################################################
# CHANGELOG
# v1.7
#    Introduced better error checking.  Script now traps signals and cleans up 
#    after itself.
#
# v1.6.1
#    Added support for get_hash.pl
#
# v1.6
#    Script now sets global zone up as NIS master
#
# v1.5
#    Script no longer downloads other scripts, but moves them from pwd to /tmp
#
# v1.4.5
#    Added net folder to downloads and cleanup list
#
# v1.4.3
#    Modified to use diss-web instead of beleg-ia.  beleg-ia is MY home server.
#    diss-web is another VM which we can use for the demonstration.  In real
#    life this would be a corperate web server of this script would be modified
#    to read off a CD.
#
# v1.4.2
#    Added variables for config file location, network_setup and zone_setup
#    script locations and ECHO to point to /usr/gnu/bin/echo.
#
# v1.4.1
#    Added zone_creator to download/unpackage.
#
# v1.4
#    Script now installs config file in /etc/vaes.conf and adds properties.
#
# v1.3
#    Removed need for pfexec.  User must now run script as root or use pfexec
#    themselves.  This means they consciously decide to use this script.
#
# v1.2.1
#    Cleaned up formatting.
#
# v1.2
#    Added a check to make sure network setup script did not fail.
#
# v1.1
#    Added usage function and echo commands telling the user what 
#    the script is doing and when it has finished.
# 
# v1.0
#    Basic functionality implemented.
###############################################################################

#Error checking on
set -e

usage(){
	echo "Usage:"
	echo "    pfexec bash INSTALL.sh"
	echo ""
	echo "THE SCRIPT NEEDS TO BE RUN AS THE ROOT USER WITH A PRIVALEGED ROLE."
	echo "THIS CAN BE EMULATED USING THE PFEXEC COMMAND."
	echo "THE USER ABLE TO DO THIS IS USUALLY DEFINED ON INSTALLTION ALONG"
	echo "WITH THE ROOT PASSWORD.  THIS SCRIPT NEEDS ROOT PERMISSIONS TO MOVE"
	echo "SYSTEM FILES."
}

#Abort proceedure - Used if script is intrrupted/fails
#May print errors!
abort(){
	echo "ABORTING!  Please take note of any warnings!"
	#If pkg-manage exists, rename it to pkg
	if [[ -a /usr/bin/pkg-manage ]]; then
		rm /usr/bin/pkg
		mv /usr/bin/pkg-manage /usr/bin/pkg
	fi
	
	#Call cleanup to clear away temp files
	cleanup
	
	#Remove contents of /var/vaes
	rm -rf /var/vaes
	
	#Remove config file
	rm $CONFIG_FILE
	
	#Uninstall NIS & related things
	pkg uninstall SUNWyp
	domainname 
	rm /etc/defaultdomain
	cp /etc/nsswitch.files /etc/nsswitch.conf
	zfs set sharenfs=off rpool/export/home
	cat /etc/auto_home | grep -v "`hostname`:/export/home" > /tmp/auto_home
	mv /tmp/auto_home /etc/auto_home
	
	#Delete zones dir
	POOL=`zfs list | awk '{ print $1 }' | grep "export" | sed 's/\([a-zA-Z]*\)\/.*/\1/g' | head -1`
	zfs destroy -Rf $POOL/export/vaes-zones
	
	#Undo zones
	bash /tmp/zone_setup.sh abort
	
	#Undo networking
	bash /tmp/network_setup.sh abort
}

#Cleanup - A function so that temp files can be cleanup half way through if
# script fails.
cleanup(){
	$ECHO -n "Cleaning up......................................."
	#chmod is used so the user isn't asked if they want to 
	#override any read-only permissions
	chmod -R 700 /tmp/zone_templates
	chmod -R 700 /tmp/pkg
	chmod -R 700 /tmp/net
	
	rm /tmp/zone_templates.tar
	rm -r /tmp/zone_templates
	rm /tmp/pkg.tar
	rm -r /tmp/pkg
	rm /tmp/network_setup.sh
	rm /tmp/zone_setup.sh
	rm /tmp/net.tar
	rm -r /tmp/net
	rm /tmp/custom_ypinit.sh
	rm /tmp/get_hash.pl
	echo "[done]"
}

trap 'abort' 1 2 3 15

############# VARIABLES #############
CONFIG_FILE="/etc/vaes.conf"
NETWORK_SETUP="/tmp/network_setup.sh"
ZONE_SETUP="/tmp/zone_setup.sh"
ECHO="/usr/gnu/bin/echo"
#####################################

echo "--------------------------"
echo "Installing V.A.E.S."
echo "--------------------------"

$ECHO -n "Checking for root..............................."
AMIROOT=`whoami`
if [[ $AMIROOT =~ root ]]; then
	echo "all is well" > /dev/null
else
	echo "[failed]"
	usage
	echo "Quitting"
	exit 1
fi
echo "..[done]"

PWD=`pwd`

#Download templates and scripts
$ECHO -n "Moving files......................................"
mv zone_templates.tar.bz2 /tmp/zone_templates.tar.bz2
mv pkg.tar.bz2 /tmp/pkg.tar.bz2
mv zone_setup.sh.bz2 /tmp/zone_setup.sh.bz2
mv network_setup.sh.bz2 /tmp/network_setup.sh.bz2
mv net.tar.bz2 /tmp/net.tar.bz2
mv custom_ypinit.sh.bz2 /tmp/custom_ypinit.sh.bz2
mv get_hash.pl.bz2 /tmp/get_hash.pl.bz2
echo "[done]"

#bunzip2 and untar files
$ECHO -n "Unpackaging files................................."
cd /tmp #Needed to stop folders being untared to pwd
bunzip2 /tmp/zone_templates.tar.bz2
tar -xf /tmp/zone_templates.tar
bunzip2 /tmp/pkg.tar.bz2 
tar -xf /tmp/pkg.tar
bunzip2 /tmp/zone_setup.sh.bz2
bunzip2 /tmp/network_setup.sh.bz2
bunzip2 /tmp/net.tar.bz2 
tar -xf /tmp/net.tar
bunzip2 /tmp/custom_ypinit.sh.bz2
bunzip2 /tmp/get_hash.pl.bz2
cd $PWD
echo "[done]"

#Move templates to /var/vaes/zone_templates
ZONEDIR="/var/vaes/zone_templates"
$ECHO -n "Creating templates directory......................"
mkdir -p $ZONEDIR
mv /tmp/zone_templates/* $ZONEDIR
echo "[done]"

#Move client ypinit to /var/vaes/scripts
SCRIPT_DIR="/var/vaes/scripts"
$ECHO -n "Creating scripts directory........................"
mkdir -p $SCRIPT_DIR
mv /tmp/pkg/custom_ypinit_client.sh $SCRIPT_DIR
echo "[done]"

#Put config file in place, set new owner
$ECHO -n "Installing configuration file....................."
cp /tmp/pkg/vaes.conf $CONFIG_FILE
chown root:root $CONFIG_FILE
chmod 700 $CONFIG_FILE
echo "[done]"

#Setup network
bash $NETWORK_SETUP

#Make global zone NIS server
$ECHO -n "Installing NIS package............................"
pkg install SUNWyp > /tmp/yp_install_progress 2>&1
echo "[done]"
$ECHO -n "Setting domain name..............................."
domainname vaes-domain
domainname > /etc/defaultdomain
echo "[done]"
$ECHO -n "Touching files...................................."
cd /etc
touch ethers bootparams netgroup
cd $PWD
echo "[done]"
$ECHO -n "Making host use NIS..............................."
cp /etc/nsswitch.nis /etc/nsswitch.conf
echo "[done]"

$ECHO -n "Configuring automount maps........................"
HOST=`hostname`
$ECHO -e "*\t$HOST:/export/home/&" >> /etc/auto_home
echo "[done]"

$ECHO -n "Sharing home dirs................................."
zfs set sharenfs=rw rpool/export/home
svcadm enable nfs/server
echo "[done]"

$ECHO -n "Running init script..............................."
VNIC_IP=`ifconfig global_vnic1 | grep inet | awk '{ print $2 }'`
/tmp/custom_ypinit.sh -m $VNIC_IP
echo "[done]"

#Setup master zone
bash $ZONE_SETUP

#Rename pkg command and replace with new pkg script
$ECHO -n "Uninstalling old pkg command......................"
PKG_CURRENT=`which pkg`
PKG_NEW=`echo $PKG_CURRENT | sed 's/\(.*\)\/\([^/]*\)/\1\/pkg-manage/'`
mv $PKG_CURRENT $PKG_NEW
echo "[done]"

$ECHO -n "Installing new pkg command........................"
mv /tmp/pkg/pkg $PKG_CURRENT
chmod 700 $PKG_CURRENT
chown root:bin $PKG_CURRENT
echo "[done]"

#Add any properties needed to /etc/vaes.conf
$ECHO -n "Adding properties to config file.................."
$ECHO -e "ZONE-DIR=$ZONEDIR" >> $CONFIG_FILE
$ECHO -e "OLD-PKG=$PKG_NEW" >> $CONFIG_FILE
$ECHO -e "MY-PKG=$PKG_CURRENT" >> $CONFIG_FILE
$ECHO -e "SCRIPT-DIR=$SCRIPT_DIR" >> $CONFIG_FILE
echo "[done]"

#Change permissions of /etc/vaes.conf
$ECHO -n "Change permissions to config file................."
chmod 500 $CONFIG_FILE
chown root:root $CONFIG_FILE
echo "[done]"

#Call cleanup
cleanup

echo "--------------------------"
echo "Installation finished"
echo "--------------------------"