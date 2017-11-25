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

# temp variable to store find command syntax 
FIND_DIRS:=$(foreach ext, $(SRC_EXTENSIONS),-o -name '*.$(ext)')

# Source files
SOURCES:=$(shell find $(SRCDIR) $(wordlist 2, $(words $(FIND_DIRS)),$(FIND_DIRS)))

# Include directories (use isystem to treat the includes as system headers, supressing warnings)
INCLUDES:=$(addprefix -isystem ,$(LIBDIRS)) $(addprefix -I ,$(INCLUDEDIRS) $(SRCDIR) $(GEN_SRCDIR))

# Library sub directeries we need to pass to the linker
LIBSUBDIRS:=$(foreach LIBDIR,$(LIBDIRS),$(wildcard $(LIBDIR)*))

# Object files from "normal" source files
OBJECTS:=$(patsubst $(SRCDIR)%,$(OBJDIR)%,$(foreach ext, $(SRC_EXTENSIONS),$(patsubst %.$(ext),%.o,$(filter %.$(ext),$(SOURCES)))))
# Object files from auto-generated source files
OBJECTS:=$(OBJECTS) $(patsubst $(GEN_SRCDIR)%,$(OBJDIR)%,$(foreach ext, $(SRC_EXTENSIONS),$(patsubst %.$(ext),%.o,$(filter %.$(ext),$(GEN_SOURCES)))))

# Generated dependecy files to include
DEPENDS:=$(OBJECTS:.o=.d)

# Name of the directory we're currently in
CURDIR_NAME:=$(lastword $(subst /, ,$(CURDIR)))

# Name of the final output files
OUTPUT_NAME:=$(subst @,$(CURDIR_NAME),$(OUTPUT_NAME))

ifeq ($(strip $(TYPE)),debug)
  C_OPTS+= -g
endif

# Source code search path. Allows us to deal with auto-generated code in $(OBJDIR)
VPATH:=$(GEN_SRCDIR):$(SRCDIR)

# Kludge tp make the GEN_SRCDIR if we're building, as VPATH won't consider directories that don't exist yet
ifneq ($(MAKECMDGOALS),clean)
  $(shell mkdir -p $(GEN_SRCDIR))
endif

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
# Includes
#############

-include $(DEPENDS)

#############
# Rules
#############

# Make an object file from an asm file
$(OBJDIR)%.o: %.s | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	@$(AS) $(AS_OPTS) -o $@ $<

# Make an object file from a C source file, and generate dependecy information.
$(OBJDIR)%.o: %.c $(SOURCE_DEPS) | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	@$(CC) $(C_OPTS) $(DEPENDS_OPTS) $(CC_OPTS) $(C_SYMBOLS) $(INCLUDES) -c $< -o $@

# Make an object file from a C++ source file, and generate dependecy information.
$(OBJDIR)%.o: %.cpp $(SOURCE_DEPS) | $$(@D)/.dirtag
	@echo "Compiling $< into $@"
	@$(CPP) $(C_OPTS) $(DEPENDS_OPTS) $(CPP_OPTS) $(C_SYMBOLS) $(INCLUDES) -c $< -o $@

# Make an elf file from all the objects
$(OBJDIR)%.elf: $(OBJECTS)
	@echo "Linking $^ into $@"
	@$(LD) $(LD_OPTS) -Wl,-Map=$(@:.elf=.map) $(addprefix -L,$(LIBSUBDIRS)) $^ $(addprefix -l,$(LIBRARIES)) -o $@

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
