CXXFLAGS          = -Wall -Wextra -Werror -Wfatal-errors --std=c++11 $(addprefix -I,$(includedirs))
FIND              = find
SHELL             = /bin/sh
deps              = $(objects:%.o=%.d)
exe               = $(outdir)/exe
includedirs       = "$(srcdir)" lib/bugeye/
objects           = $(addprefix $(outdir)/,$(srcs:$(srcdir)/%=%.o))
outdir            = out
srcdir            = src
srcs             := $(shell $(FIND) $(srcdir)/ -type f -iname '*.cpp')

all : check

check : run

clean :
	rm -frv "$(outdir)"

compile : $(exe)

run : $(exe)
	$(exe)

.PHONY : all check clean compile run

$(exe) : $(objects)
	$(CXX) $(LDFLAGS) $(objects) $(LOADLIBES) $(LDLIBS) -o $(exe)

$(outdir) :
	mkdir -pv "$@"

$(outdir)/%.o : $(srcdir)/% | $(outdir)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -MD -MF "$(@:%.o=%.d)" -D_TEST -c "$<" -o "$@"

-include $(deps)
