## InfluxDB helper scripts

*  `cron.text` - Example cron entries for the helper scripts
*  `fping.hosts` - Text file with a ist of hostnames or IP addresses to ping, used by `fping_influxdb.pl`
*  `fping_influxdb.pl` - Take the list of hosts, feed to `fping`, and adapt output to be in a suitable form
*  `hardware_monitor` - Look for temperature information under `/sys/class/hwmon/hwmon*` directories
