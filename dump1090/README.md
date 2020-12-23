## Dump1090 glue scripts

*  `tracking.pl` - Takes the `*.json` files that `dump1090` updates regularly and does three things:
   *  Log lines on stdout, for nosy people like myself.
   *  Sends a signal to a local Hubitat Elevated endpoint, which can then do with that as it sees fit. For instance I was sending notifications to my phone for a while, which got old fairly quickly.
   *  Send statistics to a local InfluxDB instance, about signals, planes.
