# SPDX-License-Identifier: GPL-3.0-or-later
# Calendar chronology belongs to this provider. Common owns the stable C ABI and shared runtime.
.DEFAULT_GOAL := all
CC ?= gcc
CXX ?= g++
PKG_CONFIG ?= pkg-config
BUILD_DIR ?= build
RESOURCE_NAME := International Fixed Calendar
COMMON_DIR := common
COMMON_REVISION := 7499fb1c81d95a11a06224c9a33c19bb71bd996d
COMMON_VERSION := 1.19.80
COMMON_BUILD_DIR := $(abspath $(BUILD_DIR))/common
COMMON_ARCHIVE := $(COMMON_BUILD_DIR)/libinfiltratr-common.a
DEPENDENCIES := glib-2.0
C_SOURCES := $(shell find src -type f -name '*.c' | LC_ALL=C sort)
CXX_SOURCES := $(shell find src -type f -name '*.cpp' | LC_ALL=C sort)
C_OBJECTS := $(patsubst src/%.c,$(BUILD_DIR)/obj/%.o,$(C_SOURCES))
CXX_OBJECTS := $(patsubst src/%.cpp,$(BUILD_DIR)/obj/%.o,$(CXX_SOURCES))
EMBEDDED_TRANSLATIONS := $(BUILD_DIR)/embedded-translations.c
EMBED_OBJECT := $(BUILD_DIR)/obj/embedded-translations.o
EMBED_TOOL := $(BUILD_DIR)/embed-translations
MO_FILES := $(patsubst i18n/%.po,$(BUILD_DIR)/mo/%.mo,$(wildcard i18n/*.po))
TARGET := $(BUILD_DIR)/$(RESOURCE_NAME).so
DEP_CFLAGS := $(shell $(PKG_CONFIG) --cflags $(DEPENDENCIES))
DEP_LIBS := $(shell $(PKG_CONFIG) --libs $(DEPENDENCIES))
CPPFLAGS += -I$(COMMON_DIR)/include -Iinclude -Isrc -Isrc/support -Isrc/calendars -Isrc/calendars/engine \
  -include include/provider-config.h -DGETTEXT_PACKAGE=\"infiltrator-calendar-international-fixed\" \
  -Dg_dgettext=infiltratr_embedded_dgettext -DU_DISABLE_RENAMING=1 \
  -DGLIB_VERSION_MIN_REQUIRED=GLIB_VERSION_2_74 -DGLIB_VERSION_MAX_ALLOWED=GLIB_VERSION_2_74
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -fPIC -fvisibility=hidden -ffunction-sections -fdata-sections \
  -Wall -Wextra -Wpedantic -Werror -Wformat=2 -Wshadow -Wstrict-prototypes \
  -Wmissing-prototypes -fstack-protector-strong -fno-common \
  -ffile-prefix-map=$(CURDIR)=. -fdebug-prefix-map=$(CURDIR)=.
CXXFLAGS += $(filter-out -std=c11 -Wstrict-prototypes -Wmissing-prototypes,$(CFLAGS)) -std=c++17
LDLIBS += $(DEP_LIBS) -lm -ldl -pthread
.PHONY: common-check all check audit-authorities clean release deb native-deb
common-check:
	@test -f "$(COMMON_DIR)/VERSION" || { echo "Missing Common: git submodule update --init" >&2; exit 1; }
	@grep -qx "$(COMMON_VERSION)" "$(COMMON_DIR)/VERSION" || { echo "Wrong Common version" >&2; exit 1; }
	@if test -e "$(COMMON_DIR)/.git"; then git -C "$(COMMON_DIR)" rev-parse HEAD | grep -qx "$(COMMON_REVISION)" || { echo "Common pin mismatch" >&2; exit 1; }; fi
	@test ! -d include/infiltratr || { echo "Copied Common headers forbidden" >&2; exit 1; }
$(COMMON_ARCHIVE): common-check
	@mkdir -p "$(COMMON_BUILD_DIR)"
	$(MAKE) -C "$(COMMON_DIR)" CC="$(CC)" BUILD_DIR="$(COMMON_BUILD_DIR)" CFLAGS="$(CFLAGS) -Wno-missing-profile" all
$(BUILD_DIR)/obj/%.o: src/%.c
	@mkdir -p "$(@D)"
	$(CC) $(CPPFLAGS) $(CFLAGS) $(DEP_CFLAGS) -c "$<" -o "$@"
$(BUILD_DIR)/obj/%.o: src/%.cpp
	@mkdir -p "$(@D)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(DEP_CFLAGS) -c "$<" -o "$@"
$(EMBED_TOOL): common/calendar-tools/embed_translations.cpp
	@mkdir -p "$(@D)"
	$(CXX) -std=c++17 -O2 -Wall -Wextra -Werror "$<" -o "$@"
$(BUILD_DIR)/mo/%.mo: i18n/%.po
	@mkdir -p "$(@D)"
	msgfmt --check -o "$@" "$<"
$(EMBEDDED_TRANSLATIONS): $(EMBED_TOOL) $(MO_FILES) i18n/LINGUAS
	$(EMBED_TOOL) i18n/LINGUAS $(BUILD_DIR)/mo "$@"
$(EMBED_OBJECT): $(EMBEDDED_TRANSLATIONS)
	@mkdir -p "$(@D)"
	$(CC) $(CPPFLAGS) $(CFLAGS) $(DEP_CFLAGS) -c "$<" -o "$@"
all: $(COMMON_ARCHIVE) $(C_OBJECTS) $(CXX_OBJECTS) $(EMBED_OBJECT)
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) -shared $(C_OBJECTS) $(CXX_OBJECTS) $(EMBED_OBJECT) $(COMMON_ARCHIVE) \
	  -Wl,--version-script=exports.map -Wl,-z,defs -Wl,--gc-sections \
	  $(LDFLAGS) -o "$(TARGET)" $(LDLIBS)
check: all
	bash common/calendar-tools/check.sh "$(TARGET)"
audit-authorities: all
	bash common/calendar-tools/check.sh "$(TARGET)" --authorities
clean:
	rm -rf "$(BUILD_DIR)"
release:
	bash common/calendar-tools/build.sh release
deb:
	bash common/calendar-tools/build.sh deb --profile portable
native-deb:
	bash common/calendar-tools/build.sh deb --profile aggressive
