#------------------------------------------------------------------------------
#                             EXPORTED VARIABLES                               
#------------------------------------------------------------------------------
# Used by nested Makefils (mbedtls, fatfs, iio)
export CFLAGS
export CC
export AR

#------------------------------------------------------------------------------
#                     PLATFORM SPECIFIC INITIALIZATION                               
#------------------------------------------------------------------------------
# Initialize copy_fun and remove_fun
# Initialize CCES_HOME to default, if directory not found show error
#	WINDOWS
ifeq ($(OS), Windows_NT)
copy_fun = powershell Copy-Item $(1) $(2)
remove_fun = powershell Remove-Item -cf:\$$false -Force -Recurse -ErrorAction Ignore -Path $(1)
#cces works to but has no console output
CCES = ccesc
CCES_HOME ?= $(wildcard C:/Analog\ Devices/CrossCore*)
ifeq ($(CCES_HOME),)
$(error $(ENDL)$(ENDL)CCES_HOME not found at c:/Analog Devices/[CrossCore...]\
		$(ENDL)$(ENDL)\
Please run command "set CCES_HOME=c:\Analog Devices\[CrossCore...]"$(ENDL)\
Ex: set CCES_HOME=c:\Analog Devices\[CrossCore...] Embedded Studio 2.8.0$(ENDL)$(ENDL))
endif
#	LINUX
else
copy_fun = cp $(1) $(2)
remove_fun = rm -rf $(1)

CCES = cces
CCES_HOME ?= $(wildcard /opt/analog/cces/*)
ifeq ($(CCES_HOME),)
$(error $(ENDL)$(ENDL)CCES_HOME not found at /opt/analog/cces/[version_number]\
		$(ENDL)$(ENDL)\
		Please run command "export CCES_HOME=[cces_path]"$(ENDL)\
		Ex: export CCES_HOME=/opt/analog/cces/2.9.2$(ENDL)$(ENDL))
endif
endif

#Set PATH variables where used binaries are found
COMPILER_BIN = $(CCES_HOME)/ARM/gcc-arm-embedded/bin
OPENOCD_SCRIPTS = $(CCES_HOME)/ARM/openocd/share/openocd/scripts
OPENOCD_BIN = $(CCES_HOME)/ARM/openocd/bin
CCES_EXE = $(CCES_HOME)/Eclipse
export PATH := $(CCES_EXE):$(OPENOCD_SCRIPTS):$(OPENOCD_BIN):$(COMPILER_BIN):$(PATH)

#------------------------------------------------------------------------------
#                           ENVIRONMENT VARIABLES                              
#------------------------------------------------------------------------------
#SHARED to use in src.mk
PLATFORM		= aducm3029
PROJECT			= $(realpath .)
NO-OS			= $(realpath ../..)
DRIVERS			= $(NO-OS)/drivers
INCLUDE			= $(NO-OS)/include
PLATFORM_DRIVERS	= $(NO-OS)/drivers/platform/$(PLATFORM)

#USED IN MAKEFILE
PROJECT_NAME		= $(notdir $(PROJECT))
PROJECT_BUILD		= $(PROJECT)/project
WORKSPACE		= $(NO-OS)/projects

PLATFORM_TOOLS		= $(NO-OS)/tools/scripts/platform/$(PLATFORM)

SRCS_CONFIG		= $(PROJECT)/src.mk
BINARY			= $(PROJECT_BUILD)/Release/$(PROJECT_NAME)
HEX			= $(PROJECT)/$(PROJECT_NAME).hex

# New line variable
define ENDL


endef

#------------------------------------------------------------------------------
#                           COMPILE FLAGS                              
#------------------------------------------------------------------------------

CFLAGS += -O2 -ffunction-sections -fdata-sections -DCORE0 -DNDEBUG -D_RTE_ \
	-D__ADUCM3029__ -D__SILICON_REVISION__=0xffff\
	-Wall -c -mcpu=cortex-m3 -mthumb

CC = arm-none-eabi-gcc
AR = arm-none-eabi-ar

#------------------------------------------------------------------------------
#                           MAKEFILE SOURCES                              
#------------------------------------------------------------------------------

include src.mk

#	MBEDTLS
#If network dir is included, mbedtls will be used
USE_MBEDTLS_LIB = $(if $(findstring $(NO-OS)/network, $(SRC_DIRS)),y)

ifeq ($(USE_MBEDTLS_LIB),y)
CFLAGS += -I $(NO-OS)/network/transport \
	-D MBEDTLS_CONFIG_FILE='"noos_mbedtls_config.h"'\ 

LIB_FLAGS += -append-switch linker -L=$(NO-OS)/libraries/mbedtls/library\
	    -append-switch linker -lmbedtls \
	    -append-switch linker -lmbedx509 \
	    -append-switch linker -lmbedcrypto

INCLUDE_DIRS += $(NO-OS)/libraries/mbedtls/include
MAKE_MBEDTLS = $(MAKE) -C $(NO-OS)/libraries/mbedtls lib
endif

#	FATFS
USE_FATFS_LIB = $(if $(findstring $(NO-OS)/libraries/fatfs, $(SRC_DIRS)),y)

ifeq ($(USE_FATFS_LIB),y)
SRC_DIRS := $(filter-out $(NO-OS)/libraries/fatfs, $(SRC_DIRS))
CFLAGS += -I$(DRIVERS)/sd-card -I$(INCLUDE)

LIB_FLAGS += -append-switch linker -L=$(NO-OS)/libraries/fatfs \
	    -append-switch linker -lfatfs

INCLUDE_DIRS += $(NO-OS)/libraries/fatfs/source
MAKE_FATFS = $(MAKE) -C $(NO-OS)/libraries/fatfs
endif

#------------------------------------------------------------------------------
#                           UTIL FUNCTIONS                              
#------------------------------------------------------------------------------


#If path == $(PROJECT)* -> relative_path
#else -> noos/relative_path
get_relative_path = $(if $(findstring $(PROJECT), $1),\
			$(patsubst $(PROJECT)/%,%,$1),\
			noos/$(patsubst $(NO-OS)/%,%,$1))

#Get text needed to link a file or folder to the project
get_src_link_flag =-link $1 $(call get_relative_path,$1)

#Get text add -I flag to compiler
get_include_link_flag =-append-switch compiler -I=$1

#ALL directories containing a .h file
INCLUDE_DIRS += $(sort $(foreach dir, $(INCS),$(dir $(dir))))
#Flags for each include dir
INCLUDE_FLAGS = $(foreach dir, $(INCLUDE_DIRS),$(call get_include_link_flag,$(dir)))
#Flags for each linked resource
SRC_FLAGS = $(foreach dir,$(SRC_DIRS),$(call get_src_link_flag,$(dir)))

#------------------------------------------------------------------------------
#                           RULES                              
#------------------------------------------------------------------------------

# Build project Release Configuration
PHONY := all
all: $(HEX)

test:
	@echo $(SRC_DIRS)

$(HEX): build
	arm-none-eabi-objcopy -O ihex $(BINARY) $(HEX)



PHONY += libs
libs:
	$(MAKE_MBEDTLS)
	$(MAKE_FATFS)

PHONY += build
build: libs project
	$(CCES) -nosplash -application com.analog.crosscore.headlesstools \
		-data $(WORKSPACE) \
		-project $(PROJECT_NAME) \
		-build Release

PHONY += update
update: project
	$(CCES) -nosplash -application com.analog.crosscore.headlesstools \
		-data $(WORKSPACE) \
		-project $(PROJECT_NAME) \
		$(INCLUDE_FLAGS) $(SRC_FLAGS) $(LIB_FLAGS)

# Upload binary to target
PHONY += run
run: build
#This way will not work if the rest button is press or if a printf is executed
	-openocd \
	-s $(OPENOCD_SCRIPTS) -f interface/cmsis-dap.cfg \
	-s $(PLATFORM_TOOLS) -f aducm3029.cfg \
	-c init \
	-c "program  $(subst \,/,$(BINARY)) verify" \
	-c "arm semihosting enable" \
	-c "reset run" \
	-c "resume" \
	-c "resume" \
	-c "resume" \
	-c "resume" \
	-c "resume" \
	-c "resume" \
	-c "resume" \
	-c "resume" \
	-c "resume" \
	-c exit

#Command when semihosting bug is fixed: https://labrea.ad.analog.com/browse/CCES-22274
#	openocd \
#	-f interface\cmsis-dap.cfg \
#	-s $(PLATFORM_TOOLS) -f aducm3029.cfg \
#	-c "program  $(subst \,/,$(BINARY)) verify reset exit"



#Create new project with platform driver and utils source folders linked
project: project.target
	$(call create_target, $@)
	$(CCES) -nosplash -application com.analog.crosscore.headlesstools \
		-command projectcreate \
		-data $(WORKSPACE) \
		-project $(PROJECT_BUILD) \
		-project-name $(PROJECT_NAME) \
		-processor ADuCM3029 \
		-type Executable \
		-revision any \
		-language C \
		-config Release \
		-remove-switch linker -specs=rdimon.specs
#Overwrite system.rteconfig file with one that enables all DFP feautres neede by noos
	$(call copy_fun, $(PLATFORM_TOOLS)/system.rteconfig, $(PROJECT_BUILD))
#Adding pinmux plugin (Did not work to add it in the first command) and update project
	$(CCES) -nosplash -application com.analog.crosscore.headlesstools \
 		-command addaddin \
 		-data $(WORKSPACE) \
 		-project $(PROJECT_NAME) \
 		-id com.analog.crosscore.ssldd.pinmux.component \
		-version latest \
		-regensrc
#The default startup_ADuCM3029.c has compiling errors
	$(call copy_fun, $(PLATFORM_TOOLS)/startup_ADuCM3029.c, \
			$(PROJECT_BUILD)/RTE/Device/ADuCM3029 )
#Remove default files from projectsrc
	$(call remove_fun, $(PROJECT_BUILD)/src)
	$(MAKE) update

# Remove workspace data and project directory
PHONY += clean_all
clean_all:
	$(MAKE) clean
	-$(call remove_fun, $(WORKSPACE)/.metadata)
	-$(call remove_fun, $(PROJECT_BUILD))
	-$(call remove_fun, *.target)

# Remove project binaries
PHONY += clean
clean:
	-$(call remove_fun, $(PROJECT_BUILD)/Release)
	-$(call remove_fun, $(HEX))
	-$(MAKE) -C $(NO-OS)/libraries/mbedtls clean
	-$(MAKE) -C $(NO-OS)/libraries/fatfs clean
#	$(CCES) -nosplash -application com.analog.crosscore.headlesstools \
 	-data $(WORKSPACE) \
 	-project $(PROJECT_NAME) \
 	-cleanOnly all


# Rebuild porject. SHould we delete project and workspace or just a binary clean?
PHONY += re
re: clean all

PHONY += ra
ra: clean_all
	$(MAKE) all

#Creates .taget file
create_target =  @echo This shouldn't be removed or edited > $1.target

#This rule is should be empty. Used for rules that should run onece
%.target: ;

.PHONY: $(PHONY)