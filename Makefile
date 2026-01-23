PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
LIBDIR  = $(PREFIX)/lib/scode
SHAREDIR = $(PREFIX)/share/scode
EXAMPLESDIR = $(SHAREDIR)/examples

.PHONY: install uninstall test lint

install:
	install -d "$(BINDIR)"
	install -d "$(LIBDIR)"
	install -d "$(EXAMPLESDIR)"
	install -m 755 scode "$(BINDIR)/scode"
	install -m 644 lib/no-sandbox.js "$(LIBDIR)/no-sandbox.js"
	install -m 644 examples/*.yaml "$(EXAMPLESDIR)/"

uninstall:
	rm -f "$(BINDIR)/scode"
	rm -f "$(LIBDIR)/no-sandbox.js"
	rm -f "$(EXAMPLESDIR)"/*.yaml
	rmdir "$(EXAMPLESDIR)" 2>/dev/null || true
	rmdir "$(SHAREDIR)" 2>/dev/null || true
	rmdir "$(LIBDIR)" 2>/dev/null || true

lint:
	shellcheck scode

test: lint
	bats test/
