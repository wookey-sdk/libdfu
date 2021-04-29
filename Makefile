###################################################################
# About the library name and path
###################################################################

# library name, without extension
LIB_NAME ?= libdfu

# project root directory, relative to app dir
PROJ_FILES = ../../
# library name, with extension
LIB_FULL_NAME = $(LIB_NAME).a

# SDK helper Makefiles inclusion
-include $(PROJ_FILES)/m_config.mk
-include $(PROJ_FILES)/m_generic.mk

# use an app-specific build dir
APP_BUILD_DIR = $(BUILD_DIR)/libs/$(LIB_NAME)

###################################################################
# About the compilation flags
###################################################################

CFLAGS := $(LIBS_CFLAGS)
CFLAGS += -MMD -MP -O3

#############################################################
# About library sources
#############################################################


SRC_DIR = .
SRC = $(wildcard $(SRC_DIR)/*.c)
OBJ = $(patsubst %.c,$(APP_BUILD_DIR)/%.o,$(SRC))
DEP = $(OBJ:.o=.d)

OUT_DIRS = $(dir $(OBJ))

# file to (dist)clean
# objects and compilation related
TODEL_CLEAN += $(OBJ)
# targets
TODEL_DISTCLEAN += $(APP_BUILD_DIR)

##########################################################
# generic targets of all libraries makefiles
##########################################################

.PHONY: app doc

default: all

all: $(APP_BUILD_DIR) lib

doc:
	$(Q)$(MAKE) BUILDDIR=../$(APP_BUILD_DIR)/doc  -C doc html latexpdf

show:
	@echo
	@echo "\tAPP_BUILD_DIR\t=> " $(APP_BUILD_DIR)
	@echo
	@echo "C sources files:"
	@echo "\tSRC_DIR\t\t=> " $(SRC_DIR)
	@echo "\tSRC\t\t=> " $(SRC)
	@echo "\tOBJ\t\t=> " $(OBJ)
	@echo

lib: $(APP_BUILD_DIR)/$(LIB_FULL_NAME)

$(APP_BUILD_DIR)/%.o: %.c
	$(call if_changed,cc_o_c)

# lib
$(APP_BUILD_DIR)/$(LIB_FULL_NAME): $(OBJ)
	$(call if_changed,mklib)
	$(call if_changed,ranlib)

$(APP_BUILD_DIR):
	$(call cmd,mkdir)

-include $(DEP)
-include $(TESTSDEP)

#####################################################################
# Frama-C
#####################################################################

# This variable is to be overriden by local shell environment variable to
# compile and use frama-C targets
# by default, FRAMAC target is deactivated, it can be activated by overriding
# the following variable value with 'y' in the environment.
FRAMAC_TARGET ?= n

ifeq (y,$(FRAMAC_TARGET))

# some FRAMAC arguments may vary depending on the FRAMA-C version (Calcium, Scandium...)
# Here we support both Calcium (20) and Scandium (21) releases
FRAMAC_VERSION=$(shell frama-c -version|cut -d'.' -f 1)
FRAMAC_RELEASE=$(shell frama-c -version|sed -re 's:^.*\((.*)\)$:\1:g')

#
# INFO: Using Frama-C, the overall flags are not directly used as they are targetting
# arm-none-eabi architecture which is not handled by framaC. Instead, we used
# a 32bits target with custom CFLAGS to handle Frama-C compilation step.
# As a consequence, include paths need to be set here as above CFLAGS are dissmissed.
# Below variables are used to handle Wookey SDK in-tree vs out-of-tree Frama-C compilation,
# which permits to:
# - run Frama-C on an autonomous extract of the overall Wookey firmware, out of the Wookey SDK tree
# - run Frama-C directly in the SDK tree, on the same set of software
# The difference is mostly the dependencies paths. The advantage of such an effort is
# to simplify the begining of the Frama-C integration, by detecting and including the necessary
# dependencies only. In a second step only, the dependencies, if they are anotated or updated,
# are pushed back to their initial position in their initial repositories.
# For libxDCI, the dependencies are:
# - the USB device driver (we have chosen the USB OTG HS (High Speed) driver
# - the libstd, which is the tiny libc implementation of the Wookey environment, including the
#   userspace part of the syscalls.
# - some generated headers associated to the target plateform associated to the driver
# - EwoK kernel exported headers

# This is the Wookey micro-libC API directory. This directory is used by all libraries and driver
# and defines all prototypes and C types used nearly everywhere in the Wookey project.
LIBSTD_API_DIR ?= $(PROJ_FILES)/libs/std/api

# This is the Wookey USB control plane library directory. This directory is used by all USB class
# implementations such as HID.
LIBUSB_DIR ?= $(PROJ_FILES)/libs/usbctrl/api

# dir of USBOTG-HS sources (direct compilation from here bypassing local Makefile)
# this path is using the Wookey repositories structure hierarchy. Another hierarchy
# can be used by overriding this variable in the environment.
USBOTGHS_DIR ?= $(PROJ_FILES)/drivers/socs/$(SOC)/usbotghs/api

# This is the device specification header path generated by the Wookey SDK JSON layout.
# The following variable is using the standard Wookey SDK directories structure but
# can be overriden in case of out of tree execution.
# This directory handle both device specifications and devlist header (per device
# unique identifier table).
# INFO: this directory MUST contains a subdir named "generated" which contains these
# two files.
USBOTGHS_DEVHEADER_PATH ?= $(PROJ_FILES)/layouts/boards/wookey

# This is the EwoK kernel exported headers directory. These headers are requested by the libstd
# itself and thus by upper layers, including drivers and libraries.
EWOK_API_DIR ?= $(PROJ_FILES)/kernel/src/C/exported

SESSION     := framac/results/frama-c-rte-eva-wp-ref.session
EVA_SESSION := framac/results/frama-c-rte-eva.session
TIMESTAMP   := framac/results/timestamp-calcium_wp-eva.txt
JOBS        := $(shell nproc)
# Does this flag could be overriden by env (i.e. using ?=)
TIMEOUT     := 15

FRAMAC_GEN_FLAGS:=\
			-absolute-valid-range 0x40040000-0x40044000 \
			-no-frama-c-stdlib \
	        -warn-left-shift-negative \
	        -warn-right-shift-negative \
	        -warn-signed-downcast \
	        -warn-signed-overflow \
	        -warn-unsigned-downcast \
	        -warn-unsigned-overflow \
	        -warn-invalid-pointer \
			-kernel-msg-key pp \
			-cpp-extra-args="-nostdinc -I framac/include  -I $(LIBUSB_DIR) -I $(LIBSTD_API_DIR) -I $(EWOK_API_DIR) -I $(USBOTGHS_DIR) -I $(USBOTGHS_DEVHEADER_PATH)"  \
		    -rte \
		    -instantiate

FRAMAC_EVA_FLAGS:=\
		  -eva -main main -eva-slevel 400 \
		    -eva-slevel-function  dfu_exec_automaton:400 \
		    -eva-domains symbolic-locations\
		    -eva-domains equality \
		    -eva-split-return auto \
		    -eva-partition-history 2 \
		    -eva-use-spec usbctrl_declare \
		    -eva-use-spec usbctrl_initialize \
		    -eva-use-spec usbctrl_declare_interface \
		    -eva-use-spec usbctrl_start_device \
		    -eva-use-spec wmalloc \
		    -eva-use-spec dfu_backend_write \
		    -eva-use-spec dfu_backend_read \
		    -eva-use-spec dfu_backend_eof \
		    -eva-use-spec queue_create \
		    -eva-use-spec queue_is_empty \
		    -eva-use-spec queue_enqueue \
		    -eva-use-spec queue_dequeue \
		    -eva-log a:frama-c-rte-eva.log

ifeq (22,$(FRAMAC_VERSION))
FRAMAC_WP_SUPP_FLAGS=-wp-check-memory-model
else
FRAMAC_WP_SUPP_FLAGS=
endif

FRAMAC_WP_PROVERS ?= alt-ergo


FRAMAC_WP_FLAGS:=\
	        -wp \
			-wp-model "Typed+ref+int" \
			-wp-literals \
			-wp-prover script,$(FRAMAC_WP_PROVERS)\
			$(FRAMAC_WP_SUPP_FLAGS)\
			-wp-timeout $(TIMEOUT) \
			-wp-log a:frama-c-rte-eva-wp.log


frama-c-parsing:
	frama-c framac/entrypoint.c dfu*.c \
		 -c11 \
		 -no-frama-c-stdlib \
		 -cpp-extra-args="-nostdinc -I framac/include -I $(LIBUSB_DIR)/api -I $(LIBUSB_DIR) -I $(LIBSTD_API_DIR) -I $(EWOK_API_DIR) -I $(USBOTGHS_DIR) -I $(USBOTGHS_DEVHEADER_PATH)"

frama-c-eva:
	frama-c framac/entrypoint.c dfu*.c -c11 \
		    $(FRAMAC_GEN_FLAGS) \
			$(FRAMAC_EVA_FLAGS) \
			-save $(EVA_SESSION)

frama-c:
	frama-c framac/entrypoint.c dfu*.c -c11 \
		    $(FRAMAC_GEN_FLAGS) \
			$(FRAMAC_EVA_FLAGS) \
		    -then \
			$(FRAMAC_WP_FLAGS) \
			-save $(SESSION) \
			-time $(TIMESTAMP)

frama-c-instantiate:
	frama-c framac/entrypoint.c dfu*.c -c11 -machdep x86_32 \
			$(FRAMAC_GEN_FLAGS) \
			-instantiate

frama-c-gui:
	frama-c-gui -load $(SESSION)

endif
