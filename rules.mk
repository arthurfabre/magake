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
# Settings - Default values
#############

# Worker function whose output should be eval()'d
# See set_default
define _set_default
ifndef $1
  $1:=$2
else ifeq ($(origin $1),default)
  $1:=$2
else
  $1:=$($1)
endif
endef

# Set a var to a default value if it isn't defined,
# or has a default make definition.
# Every variable will [re]defined as simply expanded.
#
# Params:
# 		1: Variable name
# 		2: Default value
define set_default
$(eval $(call _set_default,$1,$2))
endef

# Verbosity: 1 to enable
$(call set_default,V,0)

# Path to magake (realtive to the makefile)
$(call set_default,MM_DIR,$(dir $(lastword $(MAKEFILE_LIST))))

# Path to source directory
$(call set_default,SRC_DIR,src/)

# Source file extensions
$(call set_default,SRC_EXT,c s cc cpp)

# Path(s) to additional includes
$(call set_default,INCLUDE_DIRS,)

# Additional symbols to define
$(call set_default,SYMBOLS,)

# Object directory. A subdirectory will be created per architecture
$(call set_default,BIN_DIR,bin/)

# OutputName. @ represents the name of the directory containing this makefile
$(call set_default,OUTPUT_NAME,@.elf)

# Libraries
$(call set_default,LIBRARIES,)

# CrossCompile options
$(call set_default,CROSS_COMPILE,)

# C pre-pre-processor to use
$(call set_default,CPPP,./$(MM_DIR)cppp.py)

# C Options. Will be passed to C and C++ compiler
# TODO - Passed to linker too?
$(call set_default,C_OPTS,-Wall -O3 -Werror -pedantic)

# ASM compiler to use
$(call set_default,AS,$(CROSS_COMPILE)gcc -x assembler-with-cpp)
$(call set_default,AS_OPTS,)

# C Compiler to use
$(call set_default,CC,$(CROSS_COMPILE)gcc)
$(call set_default,CC_OPTS,-std=c11)

# C++ Compiler to use
$(call set_default,CXX,$(CROSS_COMPILE)g++)
$(call set_default,CXX_OPTS,-std=c++14)

# Objcopy to use
$(call set_default,OBJCOPY,$(CROSS_COMPILE)objcopy)
$(call set_default,OBJCOPY_OPTS,)

# Linker to use
$(call set_default,LD,$(CROSS_COMPILE)g++)
$(call set_default,LD_OPTS,)
$(call set_default,PLD_OPTS,)

#############
# Variables
#############

# Set recipe command prefix based on verbosity
ifeq ($(strip $V),0)
  Q:=@
else
  Q:=
endif

# Options to generate dependency information. Passed to C and C++ compiler
# MD: Generate a file with makefile style dependencies along with the object files
# MP; Generate bogus empty rules for every dependency so that deleting them doesn't break make
DEPENDS_OPTS=-MD -MP

# Object dir
OBJ_DIR:=$(BIN_DIR)$(shell $(CC) -dumpmachine)/

# Get the object name from a set of source files
# Params: 1: List of source files
define objectify
$(addprefix $(OBJ_DIR),$(foreach ext, $(SRC_EXT),$(patsubst %.$(ext),%.o,$(filter %.$(ext),$1))))
endef

# temp variable to store find command syntax 
FIND_DIRS:=$(foreach ext, $(SRC_EXTENSIONS),-o -name '*.$(ext)')

# Source files
SOURCES:=$(shell find $(SRC_DIR) $(wordlist 2, $(words $(FIND_DIRS)),$(FIND_DIRS)))

# Library directeries we need to pass to the linker
LIB_DIRS:=

# Include directories (use isystem to treat the includes as system headers, supressing warnings)
# TODO - Make this a function instead?
INCLUDES:=$(addprefix -I,$(SRC_DIR))

# Object files
OBJECTS:=$(call objectify,$(SOURCES))

# Generated dependecy files to include
DEPENDS:=$(OBJECTS:.o=.d)

# Name of the directory we're currently in
CURDIR_NAME:=$(lastword $(subst /, ,$(CURDIR)))

# Name of the final output files
OUTPUT:=$(OBJ_DIR)$(subst @,$(CURDIR_NAME),$(OUTPUT_NAME))

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
$(OUTPUT): $(LIB_$1)

# Make lib depend on it's object files and header files
# Header files are order only so they're not linked
$(LIB_$1): $(call objectify,$(addprefix $1/,$2)) | $(addprefix $(OBJ_DIR)include/$1/,$4)

# Expose private includes only when building lib
$(LIB_$1): INCLUDES=$(addprefix -I,$1 $(addprefix $1/,$3))

# Define symbols for library build
$(LIB_$1): SYMBOLS=$(addprefix -D,$5)

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
$(eval LIB_$1:=$(OBJ_DIR)$1.lib)$(LIB_$1)$(eval $(call _lib_src,$1,$2,$3,$4,$5))
endef


define _lib_bin
# Add library dir to search path
LIB_DIRS+= $1/

# Add fudged headers as OBJ dependency so they're not built before we fudge them
# Order only is sufficient for clean builds, non-clean builds have real dependency info
$(OBJECTS): | $(OBJ_DIR)include/$1

# Rule to symlink include dir into the one we actually use
$(OBJ_DIR)include/$1: $(wildcard $1/$2*.h) | $$$$(@D)/.dirtag
	ln -s ../../../../$1/$2 $$@
endef

# Expose a binary library
# Params: 1: Path to toplevel library dir (no trailing slash)
# 		  2: Public include dir to expose
#
# NOTE: THis doesn't link it in, add it to $(LIBRARIES) (this allows the rather finicky library linking order to be controlled)
define lib_bin
$(eval $(call _lib_bin,$1,$2))
endef

#############
# Includes
#############

# Autogenerated dependency info. Might not exist.
-include $(DEPENDS)

INCLUDES+=$(addprefix -isystem,$(OBJ_DIR)include/lib)

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
$(OBJ_DIR)include/%.h: %.h | $$(@D)/.dirtag
	@echo "Preprocessing $< into $@"
	$Q$(CPPP) $(SYMBOLS) $(INCLUDES) $< -o $@

# Make an object file from an asm file
$(OBJ_DIR)%.o: %.s | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	$Q$(AS) $(AS_OPTS) -o $@ $<

# Make an object file from a C source file, and generate dependecy information.
$(OBJ_DIR)%.o: %.c | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	$Q$(CC) $(C_OPTS) $(DEPENDS_OPTS) $(CC_OPTS) $(SYMBOLS) $(INCLUDES) -c $< -o $@

# Make an object file from a C++ source file, and generate dependecy information.
# Accept both .cpp and .cc files
$(OBJ_DIR)%.o: %.cpp | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	$Q$(CXX) $(C_OPTS) $(DEPENDS_OPTS) $(CXX_OPTS) $(SYMBOLS) $(INCLUDES) -c $< -o $@
$(OBJ_DIR)%.o: %.cc | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	$Q$(CXX) $(C_OPTS) $(DEPENDS_OPTS) $(CXX_OPTS) $(SYMBOLS) $(INCLUDES) -c $< -o $@

# Partial linking hackery. These are really .o's, but it's easier to have a different extension to keep the rules seperate
$(OBJ_DIR)%.lib: | $$(@D)/.dirtag
	@echo "Partially linking $^ into $@"
	$Q$(LD) $(PLD_OPTS) -nostdlib -r $^ -o $@

# Make an elf file from all the objects
$(OBJ_DIR)%.elf: $(OBJECTS)
	@echo "Linking $^ into $@"
	$Q$(LD) $(LD_OPTS) $(addprefix -L,$(LIB_DIRS)) $^ $(addprefix -l,$(LIBRARIES)) -o $@

# Make a hex file from a binary
$(OBJ_DIR)%.hex: $(OBJ_DIR)%.elf
	@echo "Creating hex $@"
	$Q$(OBJCOPY) $(OBJCOPY_OPTS) -O ihex $^ $@

# Build target
# TODO - Get rid of this target
build: $(OUTPUT)

# Target to create a directory
%.dirtag:
	-$Qmkdir -p $(@D)
	$Qtouch $@

# Clean target
.PHONY:clean
clean:
	@echo "Deleting all compiled files and removing build directory $(BIN_DIR)"
	$Qrm -rf $(BIN_DIR)
