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
# Version: 1.4
###############################################################################
# THE SCRIPT NEEDS TO BE RUN AS THE ROOT USER WITH A PRIVALEGED ROLE.  
# THIS CAN BE EMULATED USING THE PFEXEC COMMAND.  THE USER ABLE TO DO THIS IS
# USUALLY DEFINED ON INSTALLTION ALONG WITH THE ROOT PASSWORD.  THIS SCRIPT 
# NEEDS ROOT PERMISSIONS TO CREATE VIRTUAL NETWORKS 
# USING `dladm` AND STARTS IPV4 FORWARDING
###############################################################################
# This script does the following:
# * Looks for current IP addresses used
# * Derives suitable free subnet to use
# * Creates virtual switch (etherstub)
# * Creates virtual NIC (VNIC) and attaches to switch
# * Sets up IPv4 forwarding in global zone (to forward traffic from VAE zones)
# * Plumbs VNIC
# * Finds default gateway
# * Adds new route to the routing table
###############################################################################
# CONFIGURATION
#Global-zone   app1   app2
#   |         |      |     
# vnic1   vnic2   vnic3
#   |     |         |
#   |     ||--------|
#   switch-1-----------------etc....
###############################################################################
# CHANGELOG
# v1.4
#    Introduced better error checking.  Script now traps signals and cleans up 
#    after itself.
#
# v1.3
#    Added new script to bring up virtual network on reboots.  Script
#    now creates a service within SMF.
#
# v1.2
#    Changed the way script identifies used subnets.  It now uses a similar
#    maths to that of UNIX permissions, if a desired subnet isn't available
#    then a 1, 2, 4 or 8 is added to a variable, a case statement then 
#    decides what subnet to use, or if user intervention is needed.
#
# v1.1.1
#    Added variables for config file location and ECHO to point to 
#    /usr/gnu/bin/echo.
#
# v1.1
#    Removed need for pfexec.  User must now run script as root or use pfexec
#    themselves.  Because this is called from INSTALL.sh,
#    we shouldn't have to worry.
#
# v1.0
#    Functionaly completed
#
# v0.6
#    Added echo commands to print out what is happening and if it completes.
#    Also added mechanism which created a file if the script fails/aborts,
#    INSTALL.sh should check for this file and also quit.
#    Discovered the subnet finder is flawed, if values are submitted in
#    correct order, we might choose a subnet that is not actually free.
#    HOWEVER: We will keep this as it will be easier to say that script 
#    only works for machines on one subnet (multiple NICS can be used
#    but only on same subnet)
# 
# v0.5
#    Script can find IP addresses
#    Switch and VNIC creation are implemented, VNIC is plumbed with IP address
#    and ipv4-forwarding is enabled on the global zone
###############################################################################

#Error checking on
#set -e

abort(){
	echo "Aborting/uninstalling network setup"
	svcadm disable site/bring_up_virt_net
	/var/svc/manifest/site/bring_up_virt_net.xml
	#REMOVE SERVICE
	svcadm disable svc:/network/ipv4-forwarding:default
	ifconfig $VNIC unplumb
	#DELTET VNIC
	#DELETE ETHERSTUB
	exit 1
}

trap 'abort' 1 2 3 15

if [[ $1 =~ "abort" ]]; then
	abort
fi

############# VARIABLES #############
CONFIG_FILE="/etc/vaes.conf"
ECHO="/usr/gnu/bin/echo"
#####################################

#Find IP subnets currently in use
# Set up array for all IP addresses
$ECHO -n "Finding suitable subnet for virtual network......."
IPADDRS=""
COUNTER=0

#Find all IP addresses being used
for EACH in `ifconfig -a`; do
   # Look for four sets of grouped numbers separated by periods.
   # Groups are between 1 and 3 digets in size and consist of numbers only.
   # I.E. A standard IP address
   IPADDRS[$COUNTER]=`echo $EACH | egrep [0-9]\{1,3\}"\."[0-9]\{1,3\}"\."[0-9]\{1,3\}"\."[0-9]\{1,3\}`
   
   # If something was found, increment counter
   if [[ ${IPADDRS[$COUNTER]} ]]; then
      COUNTER=$(( $COUNTER + 1 ))
   fi
done

# Find suitable subnet
# Variables for desired subnets
DESIRED_SUBNET1="10.0.1"
DESIRED_SUBNET2="10.0.0"
DESIRED_SUBNET3="192.168.1"
DESIRED_SUBNET4="192.168.0"
# USEDSUBNET will be used to calculate what subnets are used
USEDSUBNET=0
#SUBNET is what subnet we will use
SUBNET="0.0.0.0"

#Find free subnet
#Assumes that a subnet is only used once
for EACH in ${IPADDRS[*]}; do
	
	if [[ $EACH =~ $DESIRED_SUBNET1 ]]; then
		USEDSUBNET=$(( $USEDSUBNET + 1 ))
	fi
	
	if [[ $EACH =~ $DESIRED_SUBNET2 ]]; then
		USEDSUBNET=$(( $USEDSUBNET + 2 ))
	fi
	
	if [[ $EACH =~ $DESIRED_SUBNET3 ]]; then
		USEDSUBNET=$(( $USEDSUBNET + 4 ))
	fi
	
	if [[ $EACH =~ $DESIRED_SUBNET4 ]]; then
			USEDSUBNET=$(( $USEDSUBNET + 8 ))
	fi
	
done

case $USEDSUBNET in
	0) SUBNET=`echo $DESIRED_SUBNET1` ;;
	1) SUBNET=`echo $DESIRED_SUBNET2` ;;
	2) SUBNET=`echo $DESIRED_SUBNET1` ;;
	3) SUBNET=`echo $DESIRED_SUBNET3` ;;
	4) SUBNET=`echo $DESIRED_SUBNET1` ;;
	5) SUBNET=`echo $DESIRED_SUBNET2` ;;
	6) SUBNET=`echo $DESIRED_SUBNET1` ;;
	7) SUBNET=`echo $DESIRED_SUBNET4` ;;
	8) SUBNET=`echo $DESIRED_SUBNET1` ;;
	9) SUBNET=`echo $DESIRED_SUBNET2` ;;
	10) SUBNET=`echo $DESIRED_SUBNET1` ;;
	11) SUBNET=`echo $DESIRED_SUBNET3` ;;
	12) SUBNET=`echo $DESIRED_SUBNET1` ;;
	13) SUBNET=`echo $DESIRED_SUBNET2` ;;
	14) SUBNET=`echo $DESIRED_SUBNET1` ;;
	15) SUBNET="" ;;
	*) SUBNET="" ;;
esac

# If a subnet wasn't found, SUBNET will have a zero length.
# Test for that now, if it is zero length, ask user to enter a subnet
# WARNING: As of yet (V0.5), there is no error checking for incorrect entries!
if [[ -z $SUBNET ]]; then
	echo "Cannot find a suitable subnet."
	echo "If you know of one, please type it in.  It should take the form:"
	echo "XXX.XXX.XXX"
	echo "Where X is a digit.  Leave off last group and fourth period!"
	echo "Please enter now, if you are unsure, enter 'exit' to quit:"
	read SUBNET
	if [[ -z $SUBNET ]]; then
		echo "Finding suitable subnet for virtual network.............[failed]"
		echo "Aborting"
		exit 1
	fi
	if [[ $SUBNET =~ "exit" ]]; then
		echo "Finding suitable subnet for virtual network.............[failed]"
		echo "Aborting"
		exit 1
	fi
	echo "Finding suitable subnet for virtual network.................[failed]"
else
	echo "[done]"
fi

SWITCH="global2applications_switch1"
VNIC="global_vnic1"
IPADDRESS=`echo $SUBNET.1`

#Create one virtual switch
$ECHO -n "Creating virtual switch..........................."
dladm create-etherstub $SWITCH
echo "[done]"

#Create virtual NIC and attach it to switch
$ECHO -n "Creating virtual NIC.............................."
dladm create-vnic -l $SWITCH $VNIC
echo "[done]"

#Plumb virtual NIC
$ECHO -n "Plumbing virtual NIC.............................."
ifconfig $VNIC plumb $IPADDRESS up
echo "[done]"

#Enable IPv4 forwarding
$ECHO -n "Setting up IPv4 forwarding........................"
svcadm enable svc:/network/ipv4-forwarding:default
echo "[done]"

#Find default gateway
$ECHO -n "Finding default gateway..........................."
#Use netstat to print out routing table.  We will use first entry in the table
#which happens to be the 5th line in the second column.
GATEWAY=`netstat -rn | awk '{ print $2 }' | head -5 | tail -1`
echo "[done]"

#Add route
$ECHO -n "Adding new route.................................."
route -q add $SUBNET.0 $GATEWAY > /dev/null
echo "[done]"

#Add directory for IP directory
$ECHO -n "Setting up IP database directory.................."
mkdir -p /var/vaes/ips
echo "[done]"

#Set up db
$ECHO -n "Setting up IP database............................"
touch /var/vaes/ips/db
chmod 700 /var/vaes/ips/db
for EACH in `seq 1 200`; do
	echo "$SUBNET.$EACH" >> /var/vaes/ips/db
done

#Add to DB
cat /var/vaes/ips/db | sed "s/$SUBNET.1$/$SUBNET.1=$VNIC/g" > /var/vaes/ips/db2
mv /var/vaes/ips/db2 /var/vaes/ips/db
echo "[done]"

#Put bring_up_virt_net.sh script in /bin
$ECHO -n "Copying virtual network script...................."
cp /tmp/net/bring_up_virt_net.sh /bin/bring_up_virt_net.sh
echo "[done]"

#Put service description to make bring_up_virt_net.sh run on startup
$ECHO -n "Creating new service to bring up virtual network.."
cp /tmp/net/bring_up_virt_net.xml /var/svc/manifest/site/bring_up_virt_net.xml
svccfg import /var/svc/manifest/site/bring_up_virt_net.xml
echo "[done]"

#Activate service
$ECHO -n "Activating new service............................"
svcadm enable site/bring_up_virt_net
echo "[done]"

#Add any properties needed to $CONFIG_FILE
$ECHO -n "Adding properties to config file.................."
$ECHO -e "VIRTUAL-SUBNET=$SUBNET" >> $CONFIG_FILE
$ECHO -e "GLOBAL-VNIC=$VNIC" >> $CONFIG_FILE
$ECHO -e "GLOBAL-SWITCH=$SWITCH" >> $CONFIG_FILE
$ECHO -e "GATEWAY=$GATEWAY" >> $CONFIG_FILE
$ECHO -e "IP-DIR=/var/vaes/ips" >> $CONFIG_FILE
$ECHO -e "IP-DB=/var/vaes/ips/db" >> $CONFIG_FILE
echo "[done]"

exit 0