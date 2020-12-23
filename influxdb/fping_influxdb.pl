#!/usr/bin/perl

use strict;
use warnings;

my $host = qx(hostname -f); chomp($host);

open(my $fping, '-|', 'fping -B 1 -r0 -O 0 -Q 10 -p 1000 -D -c10 -e -n -f /root/fping.hosts 2>&1') ||
    die "Failed to start fping: $!\n";
while (<$fping>) {
    chomp;
    if (/^(\S+)\s+: \S+ = (\d+)\/(\d+)\/([^%]+)%, \S+ = (\d+(?:\.\d+)?)\/(\d+(?:\.\d+)?)\/(\d+(?:\.\d+)?)/) {
	printf "ping,host=%s,target=%s loss=%.2f,lat_min=%.2f,lat_avg=%.2f,lat_max=%.2f\n", $host, $1, $4, $5, $6, $7;
    }
}
close($fping);
