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
# Version: 1.2
###############################################################################
# THE SCRIPT NEEDS TO BE RUN AS THE ROOT USER WITH A PRIVALEGED ROLE.  
# THIS CAN BE EMULATED USING THE PFEXEC COMMAND.  THE USER ABLE TO DO THIS IS
# USUALLY DEFINED ON INSTALLTION ALONG WITH THE ROOT PASSWORD.  THIS SCRIPT 
# NEEDS ROOT PERMISSIONS TO CREATE ZONES
###############################################################################
# This script does the following:
# * Creates new ZFS dataset on zpool that export is on
# * Sets up a VNIC for the template zone
# * Personalises configuration files
# * Creates zone
# * Installes zone
# * Copies config files into zone
# * Boots zone
# * Halts zone
# * Cleans up after itself
###############################################################################
# CHANGELOG
# v2
#    Introduced better error checking.  Script now traps signals and cleans up 
#    after itself.
#
# v1.1
#    Bug fixed whereby password was causing sed expression to fail resulting
#    in an empty sysidcfg file.  This meant that zones weren't being 
#    configured.
#
# v1.0
#    Files has all functionality it needs
###############################################################################

#Error checking on
set -e

abort(){
	rm /tmp/master-template
	rm /tmp/master-sysidcfg
	zoneadm -z template uninstall -F
	zonecfg -z template delete -F
	#DELETE VNIC
	
	exit 1
}

trap 'abort' 1 2 3 15

if [[ $1 =~ "abort" ]]; then
	abort
fi

############# VARIABLES #############
CONFIG_FILE="/etc/vaes.conf"
ECHO="/usr/gnu/bin/echo"
TEMPLATE_LOCATION="/export/vaes-zones/template"
ZONE_TEMPLATES="/var/vaes/zone_templates"
#####################################


#Added to show the user that nothing has stopped when installing
twirl(){
	while true; do
		$ECHO -e -n "|"
		sleep 0.1
		$ECHO -e -n "\b"
		sleep 0.1
		$ECHO -e -n "/"
		sleep 0.1
		$ECHO -e -n "\b"
		sleep 0.1
		$ECHO -e -n "-"
		sleep 0.1
		$ECHO -e -n "\b"
		sleep 0.1
		$ECHO -e -n "\\"
		sleep 0.1
		$ECHO -e -n "\b"
		
		DONE=`cat /tmp/zone_install_progress | grep -i "Installation completed"`
		if [[ $DONE =~ "Installation completed" ]]; then
			$ECHO -e -n "\b"
			$ECHO -e -n "."
			break
		fi
		
	done
}

#Find pool that export is on.  By default it is rpool.
$ECHO -n "Finding zpool with export on......................"
POOL=`zfs list | awk '{ print $1 }' | grep "export" | sed 's/\([a-zA-Z]*\)\/.*/\1/g' | head -1`
echo "[done]"

#Set up ZFS dataset /export/vaes-zones
$ECHO -n "Creating initial dataset for zones................"
zfs create $POOL/export/vaes-zones
echo "[done]"

#Set up VNIC
$ECHO -n "Setting up VNIC..................................."
SWITCH="global2applications_switch1"
VNIC="template1"
FREEIP=`cat /var/vaes/ips/db | grep -v "=" | head -1`
dladm create-vnic -l $SWITCH $VNIC
echo "[done]"

#Create temp config files, modify values as needed
$ECHO -n "Modifying config files............................"
cat $ZONE_TEMPLATES/master-zone.cfg | sed 's/<NAME>/template/g' | \
sed "s/<NIC>/$VNIC/g" | sed 's/autoboot=true/autoboot=false/g' > /tmp/master-template

ROOT_HASH=`perl /tmp/get_hash.pl`
DOMAINNAME=`domainname`
MASTER_NAME=`hostname`
MASTER_ADDRESS=`ifconfig global_vnic1 | grep inet | awk '{ print $2 }'`
#Default route is FREEIP address, but with 1
DEFAULT_ROUTE=`echo $FREEIP | sed 's/\.[0-9]\{1,3\}$/.1/g'`

cat $ZONE_TEMPLATES/master-sysidcfg.cfg | \
sed "s/<NAME>/template/g" | \
sed "s/<IP-ADDRESS>/$FREEIP/g" | \
sed "s/<DEFAULT-ROUTE>/$DEFAULT_ROUTE/g" | \
sed "s/<PASS>/$ROOT_HASH/g" | \
sed "s/<DOMAINNAME>/$DOMAINNAME/g" | \
sed "s/<MASTER-NAME>/$MASTER_NAME/g" | \
sed "s/<MASTER-ADDRESS>/$MASTER_ADDRESS/g" > /tmp/master-sysidcfg
echo "[done]"

#Create zone config
$ECHO -n "Configuring zone.................................."
zonecfg -z template -f /tmp/master-template
echo "[done]"

#Install zone
$ECHO -n "Installing zone (may take a while)................"
#Turn of error checking here
set +e
#Install zone and show twirling cursor
zoneadm -z template install > /tmp/zone_install_progress 2>&1 &
twirl
#Turn error checking back on
set -e
echo "[done]"

#Add properties to config file
$ECHO -n "Adding properties to config file.................."
$ECHO -e "MASTER-ZONE=$TEMPLATE_LOCATION" >> $CONFIG_FILE
$ECHO -e "ZONE-HOME=/export/vaes-zones/" >> $CONFIG_FILE
$ECHO -e "ROOT-HASH=$ROOT_HASH" >> $CONFIG_FILE
echo "[done]"

#Cleanup
$ECHO -n "Cleaning up......................................."
rm /tmp/master-template
rm /tmp/master-sysidcfg
echo "[done]"

exit 0