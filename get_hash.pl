#!/usr/bin/env perl
# 
# Copyright © 2010, Thomas Nathan Menari <t@menari.eu>
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
#     * Neither the name of Thomas Nathan Menari nor the names of its
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
# Author Thomas Nathan Menari
# Version: 1
###############################################################################
# THE SCRIPT NEEDS TO BE RUN AS THE ROOT USER WITH A PRIVALEGED ROLE.  
# THIS CAN BE EMULATED USING THE PFEXEC COMMAND.  THE USER ABLE TO DO THIS IS
# USUALLY DEFINED ON INSTALLTION ALONG WITH THE ROOT PASSWORD.
###############################################################################
# This script will open the shadow file, find the root salted password and 
# escape all special characters.
###############################################################################

use strict;
use warnings;

open FILE, "/etc/shadow" or die "Error opening shadow file: $!";

for my $line (<FILE>) {
    chomp $line;
    if ($line =~ /^root:/) {
	my @parts = split /:/, $line;
	$parts[1] =~ s/(\W)/\\$1/g;
	print "$parts[1]\n";
    }
}
