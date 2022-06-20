#!/usr/bin/perl

# TODO: Buffer the results and sort them by timestamp

use strict;
use warnings;

my $timestamp = undef;
my @lines = ();
my %duplicates = ();
my $total_hits = 0;
my $total_miss = 0;

sub flush_entry {
    my ($label, $t, @l) = @_;

    if (!@l) {
	print "MISSING LINES?\n";
    } else {
	my $combined = join("\n", @lines) . "\n";
	if (defined($duplicates{$combined})) {
	    $total_hits++;
	    return;
	} else {
	    $total_miss++;
	    $duplicates{$combined} = 1;
	}
	print "$t\n";
	print "$_\n" foreach @l;
    }
}

open(my $log, '-|', 'git -C ~/.history log -p') ||
    die "Could not run 'git log' command: $!\n";
while (<$log>) {
    chomp;
    if (/^(\+\+\+|---) [ab]\/.bash_history$/) {
	next;
    }
    if (/^\+(#\d+)$/) {
	if (defined($timestamp)) {
	    flush_entry("1", $timestamp, @lines);
	    @lines = ();
	}
	$timestamp = $1;
	next;
    }
    if (/^\+(.*)/) {
	push @lines, $1;
	next;
    }
    if (defined($timestamp)) {
	flush_entry("2", $timestamp, @lines);
	@lines = ();
	$timestamp = undef;
    }
}
close($log);
if (@lines > 0) {
    flush_entry("3", $timestamp, @lines);
}

print STDERR "HITS: $total_hits; MISS: $total_miss\n";
