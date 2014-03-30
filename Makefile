SUBDIRS = c++

subdirs: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@

.PHONY: subdirs $(SUBDIRS)
