pls = $(shell find . -type f -iname '*.pl')

all : check

check : test syntax

syntax : $(pls)

test :
	prove --verbose --recurse

$(pls) :
	perl -c $@

.PHONY : all check syntax test $(pls)
