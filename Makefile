FOLDERS=ds200 dump1090 influxdb mastodon Wordpress

DEFAULT:
	@echo "Nothing to do here."

check:
	perl -c analyse-edid
	for dir in $(FOLDERS); do \
		make -C $$dir check; \
		exitcode=$$?; \
		if [ $$exitcode -ne 0 ]; then \
			exit $$exitcode; \
		fi; \
	done

distcheck:
	@echo "Nothing to do here."
