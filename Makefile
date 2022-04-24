FOLDERS=Wordpress ds200 dump1090 influxdb

DEFAULT:
	@echo "Nothing to do here."

check:
	perl -c analyse-edid
	for dir in $(FOLDERS); do
		make -C $dir check
	done
