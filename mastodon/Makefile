SCRIPTS=summarize.py analyze.py

DEFAULT:
	@echo "Nothing to do."

check:
	# First install pylint
	sudo apt-get -q install -y pylint
	for src in $(SCRIPTS); do \
		pylint $$src; \
		exitcode=$$?; \
		if [ $$exitcode -ne 0 ]; then \
			exit $$exitcode; \
		fi; \
	done
