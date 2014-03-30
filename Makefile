SUBDIRS = c++ perl5

subdirs : $(SUBDIRS)

$(SUBDIRS) :
	$(MAKE) -C $@

.PHONY : subdirs $(SUBDIRS)
