ACME ?= acme
SOURCES = main.asm defs.asm ui.asm net.asm telnet.asm term.asm ansi.asm \
          charmaps.asm session.asm book.asm wic64.h wic64.asm
SCENARIOS = 1 2 3 4 5 6 7 8 9 10

build/telnet.prg: $(SOURCES)
	@mkdir -p build
	$(ACME) -f cbm -r build/telnet.lst -o $@ main.asm

# Test builds: fake network and scripted keys (see test/fake_net.asm)
test: $(SCENARIOS:%=build/test%.prg)

build/test%.prg: $(SOURCES) test/fake_net.asm test/scenarios.asm
	@mkdir -p build
	$(ACME) -f cbm -DTEST=1 -DSCENARIO=$* -o $@ main.asm

clean:
	rm -rf build

.PHONY: test clean
