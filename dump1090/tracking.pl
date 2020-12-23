#!/usr/bin/perl

# Assumes flightware use this pattern in their URLs:
# http://flightaware.com/live/modes/<hex>/redirect


use strict;
use warnings;

use JSON::PP;

$ENV{TZ} = 'America/Los_Angeles';

my $pi = atan2(1,1) * 4;

# 1 Read receiver coordinates from /run/dump1090-mutability/receiver.json
# 2 Read the plane coordinates from /run/dump1090-mutability/aircraft.json
# 3 See which ones are within a given threshold, and below a certain altitude

# my $host = qx(hostname -f); chomp($host);
# Hardcoded, for InfluxDB reasons:
my $host = "rpi-dump1090";

# curl -s -XPOST 'http://a.b.c.d:8086/write?db=servers' --data-raw "$(/root/hardware_monitor)"
my $influx_endpoint = "http://a.b.c.d:8086";
my $influx_database = "dump1090";

my $hubitat_endpoint = "http://a.b.c.e";

my $influx_counter_ascent  = 0;
my $influx_counter_descent = 0;
my $influx_counter_passing = 0;
my $influx_counter_near = 0;
my %influx_groups = ();

my $dump1090_dir = '/run/dump1090-mutability/';
my $receiver_file = $dump1090_dir . 'receiver.json';
my $aircraft_file = $dump1090_dir . 'aircraft.json';

# Distance threshold in km
my $distance_threshold = 2.0;

# Altitude threshold in ft
# Arbitrarily picked 5000, as I was able to hear some planes near that for sure
my $altitude_threshold = 5000;

local $/ = undef;
$| = 1;

my %hex_seen = ();

while (1) {
    my $output = 0;
    my $last_upload = 0;
    my $last_check = 0;

    print '.';

    if (time() >= $last_check + 5) {
	$last_check = time();
	my $changes = 0;

	my $r_fd;

	if (!open($r_fd, '<', $receiver_file)) {
	    print STDERR localtime().": Could not open receivers file ($receiver_file): $!\n";
	    sleep(1);
	    next;
	}
	my $receiver_blob = <$r_fd>;
	close($r_fd);

	if (!open($r_fd, '<', $aircraft_file)) {
	    print STDERR localtime().": Could not open aircraft file ($aircraft_file): $!\n";
	    sleep(1);
	    next;
	}
	my $aircraft_blob = <$r_fd>;
	close($r_fd);

	my $receiver_json = decode_json($receiver_blob);
	my $aircraft_json = decode_json($aircraft_blob);

	my %craft_hash = ();
	foreach my $craft (@{ $aircraft_json->{aircraft} }) {
	    if (defined($craft->{hex})) {
		$craft_hash{$craft->{hex}} = $craft;
	    }
	}

	foreach my $hex (keys %hex_seen) {
	    if (defined($craft_hash{$hex})) {
		my $craft = $craft_hash{$hex};
		my $dist = distance($receiver_json->{lat}, $receiver_json->{lon},
				    $craft->{lat}, $craft->{lon}, "K");
		# We're still nearby
		next if $dist <= $distance_threshold && $craft->{altitude} <= $altitude_threshold;
	    }
	    delete $hex_seen{$hex};
	    if (!$output) {
		print "\n";
		$output = 1;
	    }
	    $influx_counter_near--;
	    print localtime().": Purged $hex from 'seen' cache. Counter now $influx_counter_near.\n";
	    $changes++;
	}


	foreach my $craft (@{ $aircraft_json->{aircraft} }) {
	    next if !defined($craft->{hex});
	    next if defined($hex_seen{$craft->{hex}});

	    if (defined($craft->{lat}) && defined($craft->{lon})) {
		my $dist = distance($receiver_json->{lat}, $receiver_json->{lon},
				    $craft->{lat}, $craft->{lon}, "K");
	    
		next if $dist > $distance_threshold || $craft->{altitude} > $altitude_threshold;

		$hex_seen{$craft->{hex}} = time();
		$influx_counter_near++;
		$changes++;
		if (!$output) {
		    print "\n";
		    print localtime()." [$ENV{TZ}]:\n";
		    $output = 1;
		}
		print "CRAFT: Flight ".($craft->{flight} || "N/A")." ".($craft->{category} || "Unknown type")."; http://flightaware.com/live/modes/$craft->{hex}/redirect\n";
		print "  ".($craft->{lat} || "-")."  latitude, ".($craft->{lon} || "-")." longitude, distance $dist km, altitude $craft->{altitude}, vertical rate: $craft->{vert_rate}\n";
		print "  Counter now: $influx_counter_near.\n";
		my $identifier = ($craft->{flight} || $craft->{hex} || "N/A");
		$identifier =~ s/\s+$//g;
		$identifier =~ s/^\s+//g;

		my $group;

		if ($identifier =~ /^([A-Z]+)(\d+)$/) {
		    my %prefix_translations = (
			SWA => 'Southwest',
			DAL => 'Delta',
			SKW => 'SkyWest Airlines',
			AAL => 'American Airlines',
			EJA => 'NetJets Aviation',
			CAL => 'China Airlines',
			ASA => 'Alaska Airlines',
			FDX => 'FedEx',
			UPS => 'UPS'
		    );
		    if (defined($prefix_translations{$1})) {
			$identifier = "$prefix_translations{$1} $2";
			$group = $1;
		    } else {
			$group = "OTHER";
		    }
		} else {
		    $group = "OTHER";
		}
		$identifier =~ s/ /%20/g;

		$influx_groups{$group}++;
		if ($craft->{vert_rate} < 0) {
		    $influx_counter_descent++;
		    print "  Descent = $influx_counter_descent\n";
		    system("curl -s '$hubitat_endpoint/apps/api/325/trigger/setGlobalVariable=dump1090:$identifier%20landing?access_token=37bc82e5-1ebc-42a9-96ce-16e63187e14a'");
		} elsif ($craft->{vert_rate} > 0) {
		    $influx_counter_ascent++;
		    print "  Ascent = $influx_counter_ascent\n";
		    system("curl -s '$hubitat_endpoint/apps/api/325/trigger/setGlobalVariable=dump1090:$identifier%20leaving?access_token=37bc82e5-1ebc-42a9-96ce-16e63187e14a'");
		} else {
		    $influx_counter_passing++;
		    print "  Passing = $influx_counter_passing\n";
		    system("curl -s '$hubitat_endpoint/apps/api/325/trigger/setGlobalVariable=dump1090:$identifier%20passing?access_token=37bc82e5-1ebc-42a9-96ce-16e63187e14a'");
		}
	    }
	}
	if ($changes > 0) {
	    open(my $fd, '>', 'aircraft.influxdb.new') ||
		die "Could not open 'aircraft.influxdb.new: $!\n";
	    print $fd "aircraft,host=$host,direction=ascent value=$influx_counter_ascent\n";
	    print $fd "aircraft,host=$host,direction=descent value=$influx_counter_descent\n";
	    print $fd "aircraft,host=$host,direction=passing value=$influx_counter_passing\n";
	    print $fd "aircraft,host=$host,direction=nearby value=$influx_counter_near\n";
	    foreach my $group (sort keys %influx_groups) {
		print $fd "aircraft,host=$host,group=$group value=$influx_groups{$group}\n";
	    }
	    close($fd);

	    rename("$ENV{HOME}/aircraft.influxdb.new", "$ENV{HOME}/aircraft.influxdb");
	}
    }
    if (time() >= $last_upload + 60) {
	$last_upload = time();
	system("curl -s '$influx_endpoint/write?db=$influx_database' --data-raw \"\$(cat $ENV{HOME}/aircraft.influxdb)\"");
    }
    sleep(1);
}

# From https://www.geodatasource.com/developers/perl
#
#:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::                                                                         :::
#:::  This routine calculates the distance between two points (given the     :::
#:::  latitude/longitude of those points). It is being used to calculate     :::
#:::  the distance between two locations using GeoDataSource(TM) products    :::
#:::                                                                         :::
#:::  Definitions:                                                           :::
#:::    South latitudes are negative, east longitudes are positive           :::
#:::                                                                         :::
#:::  Passed to function:                                                    :::
#:::    lat1, lon1 = Latitude and Longitude of point 1 (in decimal degrees)  :::
#:::    lat2, lon2 = Latitude and Longitude of point 2 (in decimal degrees)  :::
#:::    unit = the unit you desire for results                               :::
#:::           where: 'M' is statute miles (default)                         :::
#:::                  'K' is kilometers                                      :::
#:::                  'N' is nautical miles                                  :::
#:::                                                                         :::
#:::  Worldwide cities and other features databases with latitude longitude  :::
#:::  are available at https://www.geodatasource.com                         :::
#:::                                                                         :::
#:::  For enquiries, please contact sales@geodatasource.com                  :::
#:::                                                                         :::
#:::  Official Web site: https://www.geodatasource.com                       :::
#:::                                                                         :::
#:::            GeoDataSource.com (C) All Rights Reserved 2018               :::
#:::                                                                         :::
#:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

sub distance {
    my ($lat1, $lon1, $lat2, $lon2, $unit) = @_;
    if (($lat1 == $lat2) && ($lon1 == $lon2)) {
	return 0;
    }
    else {
	my $theta = $lon1 - $lon2;
	my $dist = sin(deg2rad($lat1)) * sin(deg2rad($lat2)) + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * cos(deg2rad($theta));
	$dist  = acos($dist);
	$dist = rad2deg($dist);
	$dist = $dist * 60 * 1.1515;
	if ($unit eq "K") {
	    $dist = $dist * 1.609344;
	} elsif ($unit eq "N") {
	    $dist = $dist * 0.8684;
	}
	return ($dist);
    }
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function get the arccos function using arctan function   :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub acos {
    my ($rad) = @_;
    my $ret = atan2(sqrt(1 - $rad**2), $rad);
    return $ret;
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function converts decimal degrees to radians             :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub deg2rad {
    my ($deg) = @_;
    return ($deg * $pi / 180);
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#:::  This function converts radians to decimal degrees             :::
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
sub rad2deg {
    my ($rad) = @_;
    return ($rad * 180 / $pi);
}

# print distance(32.9697, -96.80322, 29.46786, -98.53506, "M") . " Miles\n";
# print distance(32.9697, -96.80322, 29.46786, -98.53506, "K") . " Kilometers\n";
# print distance(32.9697, -96.80322, 29.46786, -98.53506, "N") . " Nautical Miles\n";
