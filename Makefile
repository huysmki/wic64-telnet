ACME ?= acme
# VICE: x64sc and c1541 from the PATH, or a VICE 3.10+ in /Applications
VICE_BIN = $(firstword $(wildcard /Applications/vice-*/bin))
VICE ?= $(if $(VICE_BIN),$(VICE_BIN)/x64sc,x64sc)
C1541 ?= $(if $(VICE_BIN),$(VICE_BIN)/c1541,c1541)
SOURCES = main.asm defs.asm ui.asm net.asm receive.asm telnet.asm term.asm ansi.asm scrollback.asm screen80.asm \
          charmaps.asm session.asm book.asm xfer.asm crash.asm crash_report.asm directory.asm \
          wic64.h wic64.asm
SCENARIOS = 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27
DISK_SCENARIOS = 7 8 20 21 22 23 24 25 26 27 26 27
# Files the download scenarios save on the test disk: name:expected .bin
DOWNLOADS = xmts:test20 punt,s:test21 auto,s:test22 one,s:test23a two:test23b
# Files put on the test disk just before a scenario: scenario:name:file
DISK_FILES = 24:telnet.cfg:build/wtb1.cfg 25:telnet.cfg:build/wtb2.cfg \
             27:junk:build/wtb1.cfg
# Files read from the test disk just after a scenario, compared with
# their .bin: scenario:name:expected
SAVED_FILES = 24:telnet.cfg:test24 25:telnet.cfg:test25

build/telnet.prg: $(SOURCES)
	@mkdir -p build
	$(ACME) -f cbm -r build/telnet.lst -o $@ main.asm

# Test builds: fake network and scripted keys (see test/fake_net.asm)
test: $(SCENARIOS:%=build/test%.prg)

build/test%.prg: $(SOURCES) test/fake_net.asm test/scenarios.asm
	@mkdir -p build
	$(ACME) -f cbm -DTEST=1 -DSCENARIO=$* -l build/test$*.lbl -o $@ main.asm

# Benchmarks (see test/bench.asm): cycles per byte the server sends
BENCHES = 1 2 3 4

bench: $(BENCHES:%=build/bench%.prg)
	@for n in $(BENCHES); do \
	    VICE="$(VICE)" python3 tools/run_test.py build/bench$$n.prg build/bench$$n.lbl \
	        build/bench$$n.txt || exit 1; \
	done

build/bench%.prg: $(SOURCES) test/fake_net.asm test/bench.asm build/bench_frames.bin
	$(ACME) -f cbm -DTEST=1 -DBENCH=$* -l build/bench$*.lbl -o $@ main.asm

build/bench_frames.bin: tools/bench_data.py
	python3 tools/bench_data.py build

build/wtb%.cfg: test/wtb%.asm
	@mkdir -p build
	$(ACME) -f cbm -o $@ $<

# Runs every test build in VICE and compares the screen and what was
# sent with test/expected/, and the downloaded files with their .bin.
# Screenshots end up in build/test<n>.png.
check: test build/wtb1.cfg build/wtb2.cfg
	@$(C1541) -format "test,01" d64 build/test.d64 >/dev/null
	@fail=0; for n in $(SCENARIOS); do \
	    disk=; case " $(DISK_SCENARIOS) " in *" $$n "*) disk="--disk build/test.d64";; esac; \
	    for f in $(DISK_FILES); do case $$f in $$n:*) f=$${f#*:}; \
	        $(C1541) build/test.d64 -delete "$${f%%:*}" >/dev/null 2>&1; \
	        $(C1541) build/test.d64 -write "$${f#*:}" "$${f%%:*}" >/dev/null 2>&1;; \
	    esac; done; \
	    VICE="$(VICE)" python3 tools/run_test.py build/test$$n.prg build/test$$n.lbl \
	        build/test$$n.txt --png build/test$$n.png $$disk || exit 1; \
	    if cmp -s build/test$$n.txt test/expected/test$$n.txt; then echo "test$$n ok"; \
	    else echo "test$$n FAILED: diff test/expected/test$$n.txt build/test$$n.txt"; fail=1; fi; \
	    for f in $(SAVED_FILES); do case $$f in $$n:*) f=$${f#*:}; e=$${f#*:}; rm -f build/$$e.bin; \
	        $(C1541) build/test.d64 -read "$${f%%:*}" build/$$e.bin >/dev/null 2>&1; \
	        if cmp -s build/$$e.bin test/expected/$$e.bin; then echo "$$e file ok"; \
	        else echo "$$e file FAILED: cmp test/expected/$$e.bin build/$$e.bin"; fail=1; fi;; \
	    esac; done; \
	done; \
	for d in $(DOWNLOADS); do \
	    n=$${d##*:}; rm -f build/$$n.bin; \
	    $(C1541) build/test.d64 -read "$${d%%:*}" build/$$n.bin >/dev/null 2>&1; \
	    if cmp -s build/$$n.bin test/expected/$$n.bin; then echo "$$n file ok"; \
	    else echo "$$n file FAILED: cmp test/expected/$$n.bin build/$$n.bin"; fail=1; fi; \
	done; exit $$fail

# Accepts the results of the last check as expected (look at them first)
expected:
	@mkdir -p test/expected
	cp $(SCENARIOS:%=build/test%.txt) test/expected/
	cp $(foreach d,$(DOWNLOADS) $(SAVED_FILES),build/$(lastword $(subst :, ,$(d))).bin) test/expected/

clean:
	rm -rf build

.PHONY: test bench check expected clean
