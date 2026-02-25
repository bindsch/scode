PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
LIBDIR  = $(PREFIX)/lib/scode
SHAREDIR = $(PREFIX)/share/scode
EXAMPLESDIR = $(SHAREDIR)/examples

.PHONY: install uninstall test test-js lint

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

test-js:
	@if ! command -v node >/dev/null 2>&1; then \
		echo "WARNING: test-js SKIPPED — node not found" >&2; \
		[ -z "$(SCODE_REQUIRE_JS_TESTS)" ] || exit 1; \
	elif ! node -e 'const v=process.versions.node.split(".").map(Number); if(v[0]<18||(v[0]===18&&v[1]<13))process.exit(1)' 2>/dev/null; then \
		echo "WARNING: test-js SKIPPED — node >= 18.13 required for --test runner" >&2; \
		[ -z "$(SCODE_REQUIRE_JS_TESTS)" ] || exit 1; \
	elif ! [ -d node_modules ]; then \
		echo "WARNING: test-js SKIPPED — node_modules missing (run npm install)" >&2; \
		[ -z "$(SCODE_REQUIRE_JS_TESTS)" ] || exit 1; \
	else \
		SCODE_TEST=1 node --test test/no-sandbox.test.js; \
	fi

test: lint test-js
	bats test/
