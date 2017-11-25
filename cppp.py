#!/usr/bin/env python3

# The MIT License (MIT)
#
# Copyright (c) 2017 Arthur Fabre <arthur@arthurfabre.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Hackery to pre-pre-process a C/CPP header file
#
# This only:
#
# #define's whatever is set on the command line at the top,
# and #undef's at the bottom of the generated file
#
# Expands #include's if the include file can be found in the include search path
# This doesn't quite mimick the pre-processor, as we don't track include guards
# and instead prevent files from being included in a loop.

import os
import sys
import argparse
import re

# Regular expression for matching #include statements
# Allows pretty liberal use of whitespace
INC_RE = re.compile('\s*#\s*include\s*(?:<([^>]+)>|"([^"]+)")')

# Returns None if no #include found, name of file otherwise
def match_include(line):
    m = INC_RE.match(line)

    if m:
        return (m.group(1) if m.group(1) else m.group(2)).strip()
    else:
        return None

# Returns None if the file couldn't be found, path to file otherwise
def find_path(name, includes):
    for d in includes:
        src_path = os.path.join(d, name)

        if os.path.isfile(src_path):
            return src_path

    return None

# Returns None if no #include found, path to file otherwise
def find_include(line, includes):
    name = match_include(line)

    if not name:
        return False

    return find_path(name, includes)

# Expand all the #includes that match a known header
def expand(r, w, includes, past):
    # Always search current directory of header
    full_includes = includes + [os.path.dirname(r.name)]

    w.write('#line 1 "%s"\n' % r.name)
    line_no = 0

    for line in r:
        line_no += 1

        path = find_include(line, full_includes)
        if path:
            if path not in past:
                with open(path, 'r') as inc:
                    expand(inc, w, includes, past + [path])

            w.write('#line %d "%s"\n' % (line_no, r.name))
            continue

        w.write(line)

def process(r, w, includes, symbols):
    for sym, val in symbols.items():
        if val != '':
            w.write('#define %s %s\n' % (sym, val))
        else:
            w.write('#define %s\n' % sym)

    expand(r, w, includes, [])

    for sym in symbols:
        w.write('#undef %s\n' % sym)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Pre-pre-process a header file, expanding found #include\'s, and wrapping the file with #define\'s / #undef\'s for provided symbols')

    parser.add_argument('header', type=argparse.FileType('r'), help='Pre-pre-process file header')
    parser.add_argument('-o', dest='output', type=argparse.FileType('w'), default=sys.stdout, metavar='file', help='Place the output in file (default: stdout)')
    parser.add_argument('-I', dest='includes', action='append', metavar='dir', help='Add dir to the include search path (directory relative to header is always searched)')
    parser.add_argument('-D', dest='symbols', action='append', metavar='sym[=val]', help='Define sym as val' )

    args = parser.parse_args()

    process(args.header, args.output, args.includes, dict((sym.split("=") if '=' in sym else (sym, "")) for sym in args.symbols))
