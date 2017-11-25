# The MIT License (MIT)
#
# Copyright (c) 2015 Arthur Fabre <arthur@arthurfabre.com>
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

#############
# Generic makefile settings for C, CPP, and ASM.
#
# Supports automatic dependecy generation, cross compiling, and other bits of magic.
# Expects to be using the GNU C Compiler, or a compatible compiler.
#
# A seperate directory is created in the bin directory for every architecture.
#
# Dependecies are generated at compile time - we only need updated dependecy information for the next build.
#
# Directory makefiles should include settings.mk first. 
# They can then override / append the variables defined in the Settings section
#
# They should then include rules.mk
# They can then override / create new build rules
#
#############

#############
# Make options
#############

# Set the shell to be bash
SHELL:=/bin/bash

# Sane exit / error reporting options for bash
# errexit: exit bash with $? if $? != 0
# pipefail: a | b will exit with the first $? != 0 instead of the $? of b
export SHELLOPTS:=errexit:pipefail

# Delete target files on error
.DELETE_ON_ERROR:

# Don't spawn a seperate shell for every recipe comand
.ONESHELL:

# Disable built in suffix rules
.SUFFIXES:

# Disable builtin pattern rules
MAKEFLAGS+=-r

# Enable secondary expansion
.SECONDEXPANSION:

# Set default target
.DEFAULT_GOAL:=build

# Don't delete intermediate files
.SECONDARY:

#############
# Variables
#############

# Object dir
OBJDIR:=$(BINDIR)$(shell $(CC) -dumpmachine)/

# Get the object name from a set of source files
# Params: 1: List of source files
define objectify
$(addprefix $(OBJDIR),$(foreach ext, $(SRC_EXTENSIONS),$(patsubst %.$(ext),%.o,$(filter %.$(ext),$1))))
endef

# temp variable to store find command syntax 
FIND_DIRS:=$(foreach ext, $(SRC_EXTENSIONS),-o -name '*.$(ext)')

# Source files
SOURCES:=$(shell find $(SRCDIR) $(wordlist 2, $(words $(FIND_DIRS)),$(FIND_DIRS))) $(EXTRA_SOURCES)

# Library sub directeries we need to pass to the linker
LIBSUBDIRS:=

# Partially linked library objects
LIB_OBJECTS:=

# Include directories (use isystem to treat the includes as system headers, supressing warnings)
INCLUDES:=$(addprefix -I,$(INCLUDEDIRS) $(SRCDIR))

# Object files
OBJECTS:=$(call objectify,$(SOURCES))

# Generated dependecy files to include
DEPENDS:=$(OBJECTS:.o=.d)

# Name of the directory we're currently in
CURDIR_NAME:=$(lastword $(subst /, ,$(CURDIR)))

# Name of the final output files
OUTPUT_NAME:=$(subst @,$(CURDIR_NAME),$(OUTPUT_NAME))

ifeq ($(strip $(TYPE)),debug)
  C_OPTS+= -g
endif

#############
# Library support
#############

# Real worker function
# Params: See lib_src
# Expands to: Lots of junk
define _lib_src
# Add lib to lists of things to link
LIB_OBJECTS+= $(LIB_$1)

# Make lib depend on it's object files and header files
$(LIB_$1): $(call objectify,$(addprefix $1/,$2)) $(addprefix $(OBJDIR)include/$1/,$4)

$(LIB_$1): OBJECTS=$(call objectify,$(addprefix $1/,$2))

# Expose private includes only when building lib
$(LIB_$1): INCLUDES=$(addprefix -I,$1 $(addprefix $1/,$3))

# Define symbols for library build
$(LIB_$1): C_SYMBOLS=$(addprefix -D,$5)

# Add fudged headers as OBJ dependency so they're not built before we fudge them
# Order only is sufficient for clean builds, non-clean builds have real dependency info
$(OBJECTS): | $(LIB_$1)
endef

# Magic to include / embed a library's source
# Params: 1: Path to toplevel library dir (no trailing slash)
#         2: List of source files
#         3: List of private include dirs (required for internal library building)
#         4: List of headers to expose
#         5: List of required preprocessor symbols
#
# Expands to the name of the target generated for the library (which can be used to set target-specific overrides for things like C_FLAGS)
define lib_src
$(eval LIB_$1:=$(OBJDIR)$1.lib)$(LIB_$1)$(eval $(call _lib_src,$1,$2,$3,$4,$5))
endef


define _lib_bin
# Add library dir to search path
LIBSUBDIRS+= $1/

# Add fudged headers as OBJ dependency so they're not built before we fudge them
# Order only is sufficient for clean builds, non-clean builds have real dependency info
$(OBJECTS): | $(OBJDIR)include/$1

# Rule to symlink include dir into the one we actually use
$(OBJDIR)include/$1: $(wildcard $1/$2*.h) | $$$$(@D)/.dirtag
	ln -s ../../../../$1/$2 $$@
endef

# TODO - Expose a binary library
# Params: 1: Path to toplevel library dir (no trailing slash)
# 		  2: Public include dir to expose
#
# NOTE: THis doesn't link it in, add it to $(LIBRARIES) (this allows the rather finicky library linking order to be controlled)
define lib_bin
$(eval $(call _lib_bin,$1,$2))
endef


# TODO - Include a systen library
define lib_sys
endef

#############
# Includes
#############

# Autogenerated dependency info. Might not exist.
-include $(DEPENDS)

# TODO
# For every lib-dir, include *.mk
INCLUDES+=$(addprefix -isystem,$(OBJDIR)include/lib)

#############
# Debug
#############

#$(info OUTPUT_NAME=$(OUTPUT_NAME))
#$(info OBJECTS=$(OBJECTS))
#$(info SOURCES=$(SOURCES))
#$(info INCLUDES=$(INCLUDES))
#$(info DEPENDS=$(DEPENDS))
#$(info C_OPTS=$(C_OPTS))
#$(info LIBSUBDIRS=$(LIBSUBDIRS))

#############
# Rules
#############

# Build a pre-pre-processed header from a source header
$(OBJDIR)include/%.h: %.h | $$(@D)/.dirtag
	@echo "Preprocessing $< into $@"
	@./cppp.py $(C_SYMBOLS) $(INCLUDES) $< $@

# Make an object file from an asm file
$(OBJDIR)%.o: %.s | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	@$(AS) $(AS_OPTS) -o $@ $<

# Make an object file from a C source file, and generate dependecy information.
$(OBJDIR)%.o: %.c | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	@$(CC) $(C_OPTS) $(DEPENDS_OPTS) $(CC_OPTS) $(C_SYMBOLS) $(INCLUDES) -c $< -o $@

# Make an object file from a C++ source file, and generate dependecy information.
# Accept both .cpp and .cc files
$(OBJDIR)%.o: %.cpp | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	@$(CPP) $(C_OPTS) $(DEPENDS_OPTS) $(CPP_OPTS) $(C_SYMBOLS) $(INCLUDES) -c $< -o $@
$(OBJDIR)%.o: %.cc | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	@$(CPP) $(C_OPTS) $(DEPENDS_OPTS) $(CPP_OPTS) $(C_SYMBOLS) $(INCLUDES) -c $< -o $@

# Partial linking hackery. These are really .o's, but it's easier to have a different extension to keep the rules seperate
$(OBJDIR)%.lib: | $$(@D)/.dirtag
	@echo "Partially linking $(OBJECTS) into $@"
	@$(PLD) -r $(OBJECTS) -o $@

# Make an elf file from all the objects
$(OBJDIR)%.elf: $(OBJECTS) $(LIB_OBJECTS)
	@echo "Linking $^ into $@"
	@$(LD) $(LD_OPTS) $(addprefix -L,$(LIBSUBDIRS)) $(OBJECTS) $(LIB_OBJECTS) $(addprefix -l,$(LIBRARIES)) -o $@

# Make a hex file from a binary
$(OBJDIR)%.hex: $(OBJDIR)%.elf
	@echo "Creating hex $@"
	@$(OBJCOPY) $(OBJCOPY_OPTS) -O ihex $^ $@

# Build target
build: $(OBJDIR)$(OUTPUT_NAME)

# Target to create a directory
%.dirtag:
	@-mkdir -p $(@D)
	@touch $@

# Clean target
.PHONY:clean
clean:
	@echo "Deleting all compiled files and removing build directory $(BINDIR)"
	@rm -rf $(BINDIR)
