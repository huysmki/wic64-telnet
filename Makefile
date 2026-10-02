ACME ?= acme
# VICE: x64sc and c1541 from the PATH, or a VICE 3.10+ in /Applications
VICE_BIN = $(firstword $(wildcard /Applications/vice-*/bin))
VICE ?= $(if $(VICE_BIN),$(VICE_BIN)/x64sc,x64sc)
C1541 ?= $(if $(VICE_BIN),$(VICE_BIN)/c1541,c1541)
SOURCES = main.asm defs.asm ui.asm net.asm telnet.asm term.asm ansi.asm scrollback.asm screen80.asm \
          charmaps.asm session.asm book.asm wic64.h wic64.asm
SCENARIOS = 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19
DISK_SCENARIOS = 7 8

build/telnet.prg: $(SOURCES)
	@mkdir -p build
	$(ACME) -f cbm -r build/telnet.lst -o $@ main.asm

# Test builds: fake network and scripted keys (see test/fake_net.asm)
test: $(SCENARIOS:%=build/test%.prg)

build/test%.prg: $(SOURCES) test/fake_net.asm test/scenarios.asm
	@mkdir -p build
	$(ACME) -f cbm -DTEST=1 -DSCENARIO=$* -l build/test$*.lbl -o $@ main.asm

# Runs every test build in VICE and compares the screen and what was
# sent with test/expected/. Screenshots end up in build/test<n>.png.
check: test
	@$(C1541) -format "test,01" d64 build/test.d64 >/dev/null
	@fail=0; for n in $(SCENARIOS); do \
	    disk=; case " $(DISK_SCENARIOS) " in *" $$n "*) disk="--disk build/test.d64";; esac; \
	    VICE="$(VICE)" python3 tools/run_test.py build/test$$n.prg build/test$$n.lbl \
	        build/test$$n.txt --png build/test$$n.png $$disk || exit 1; \
	    if cmp -s build/test$$n.txt test/expected/test$$n.txt; then echo "test$$n ok"; \
	    else echo "test$$n FAILED: diff test/expected/test$$n.txt build/test$$n.txt"; fail=1; fi; \
	done; exit $$fail

# Accepts the results of the last check as expected (look at them first)
expected:
	@mkdir -p test/expected
	cp $(SCENARIOS:%=build/test%.txt) test/expected/

clean:
	rm -rf build

.PHONY: test check expected clean
