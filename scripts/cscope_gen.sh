#!/bin/sh
find . -name '*.py' \
	-o -name '*.cpp' \
	-o -name '*.cc' \
	-o -name '*.c' \
	-o -name '*.hpp' \
	-o -name '*.h' \
	-o -name '*.asm' \
	> cscope.files

# -b: just build
# -q: create inverted index
cscope -b -q
