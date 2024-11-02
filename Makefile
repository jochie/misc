FOLDERS=ds200 dump1090 influxdb mastodon Wordpress

DEFAULT:
	@echo "Nothing to do here."

check:
	perl -c analyse-edid
	for dir in $(FOLDERS); do \
		make -C $$dir check; \
		if [ $$? -ne 0 ]; then \
			exit $$?; \
		fi; \
	done

distcheck:
	@echo "Nothing to do here."
