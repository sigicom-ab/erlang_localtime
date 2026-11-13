# Regenerates ../include/tz_database.hrl from the IANA tz database.
#
#   make                       # latest release -> ../include/tz_database.hrl
#                              # (does nothing if already at the latest release)
#   make FORCE=1               # regenerate even if already at the latest release
#   make TZ_VERSION=2026e      # a specific release
#   make test                  # fetch the committed release's data, run the eunit suite
#
# The latest release is the one named in $(IANA_URL)/tzdb/version.  The data
# is compiled with zic from the tzcode of the same release (built locally, so
# the output does not depend on the zic shipped by the OS).  The generator
# reads the POSIX TZ footer of each compiled TZif file and cross-checks it
# against zdump.

IANA_URL := https://data.iana.org/time-zones
OUT      ?= ../include/tz_database.hrl
HRL      := ../include/tz_database.hrl

# The release the committed database was generated from (its header line
# "%% version 2026f on ...").
COMMITTED_VERSION := $(shell sed -n 's/^%% version \([^ ]*\) on .*/\1/p' $(HRL))

TZCODE_VERSION ?= $(TZ_VERSION)
TZDATA         := tzdata$(TZ_VERSION)
BUILD          := build
TZCODE         := $(BUILD)/tzcode$(TZCODE_VERSION)
ZIC            := $(TZCODE)/zic
ZDUMP          := $(TZCODE)/zdump
ZONEINFO       := $(BUILD)/zoneinfo-$(TZ_VERSION)

SOURCES  := africa antarctica asia australasia etcetera europe northamerica southamerica backward
TZ_FILES := $(addprefix $(TZDATA)/,$(SOURCES))

# Targets that work on one release need TZ_VERSION.
need_version = $(if $(TZ_VERSION),,$(error TZ_VERSION is not set))

.PHONY: all generate zoneinfo tools test clean

ifdef TZ_VERSION
all: generate
else
all:
	@v=$$(curl -fsS $(IANA_URL)/tzdb/version) || v=; \
	case "$$v" in \
	  [0-9][0-9][0-9][0-9][a-z]*) ;; \
	  *) echo "could not fetch latest tz version from $(IANA_URL)/tzdb/version; pass TZ_VERSION=..." >&2; exit 1;; \
	esac; \
	if [ "$$v" = "$(COMMITTED_VERSION)" ] && [ -z "$(FORCE)" ]; then \
	  echo "already at $$v (FORCE=1 to regenerate)"; \
	else \
	  $(MAKE) generate TZ_VERSION=$$v; \
	fi
endif

generate: $(OUT)

$(OUT): tz_gen.erl $(ZONEINFO)/.stamp $(ZDUMP)
	$(need_version)
	escript tz_gen.erl --version $(TZ_VERSION) --tzdata $(TZDATA) \
	  --zoneinfo $(ZONEINFO) --zdump $(ZDUMP) -o $@

zoneinfo: $(ZONEINFO)/.stamp
$(ZONEINFO)/.stamp: $(ZIC) $(TZ_FILES)
	$(need_version)
	rm -rf $(ZONEINFO)
	$(ZIC) -d $(ZONEINFO) $(TZ_FILES)
	touch $@

$(TZ_FILES): | $(TZDATA)

tools: $(ZIC) $(ZDUMP)
$(ZIC) $(ZDUMP): | $(TZCODE)/Makefile
	$(MAKE) -C $(TZCODE) zic zdump

# tzcode's Makefile needs the data files present to compute its version.
$(TZCODE)/Makefile:
	$(need_version)
	mkdir -p $(TZCODE)
	curl -fsSL $(IANA_URL)/releases/tzcode$(TZCODE_VERSION).tar.gz | tar xzf - -C $(TZCODE)
	curl -fsSL $(IANA_URL)/releases/tzdata$(TZCODE_VERSION).tar.gz | tar xzf - -C $(TZCODE)

tzdata%:
	mkdir -p $@
	curl -fsSL $(IANA_URL)/releases/$@.tar.gz | tar xzf - -C $@ || { rm -rf $@; exit 1; }

# Everything test/tz_gen_tests.erl needs (the release the committed database
# was generated from), then the whole eunit suite.
test:
	$(if $(COMMITTED_VERSION),,$(error no version found in the header of $(HRL)))
	$(MAKE) tools zoneinfo TZ_VERSION=$(COMMITTED_VERSION) TZCODE_VERSION=$(COMMITTED_VERSION)
	cd .. && rebar3 eunit

clean:
	rm -rf $(BUILD) tzdata*/
