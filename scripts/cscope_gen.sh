#!/bin/sh
find . -type f -a \
        \( -name '*.py' \
	-o -name '*.cpp' \
	-o -name '*.cc' \
	-o -name '*.c' \
	-o -name '*.hpp' \
	-o -name '*.h' \
	-o -name '*.asm' \) \
	> cscope.files

# -b: just build
# -q: create inverted index
cscope -b -q
