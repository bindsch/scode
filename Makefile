PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
LIBDIR  = $(PREFIX)/lib/scode
SHAREDIR = $(PREFIX)/share/scode
EXAMPLESDIR = $(SHAREDIR)/examples
EXAMPLE_FILES = \
	examples/sandbox.yaml \
	examples/sandbox-strict.yaml \
	examples/sandbox-paranoid.yaml \
	examples/sandbox-permissive.yaml \
	examples/sandbox-cloud-eng.yaml \
	examples/sandbox-grok.yaml

# Shell line-coverage floor for `make coverage-gate`, matching the JavaScript
# gate. Coverage is collected with kcov on macOS and on Linux and gated over
# the two reports merged: each platform skips the other's runtime-sandbox
# tests, so a single report understates what the suite exercises. Code no
# platform can measure (the closed-descriptor engine launcher, which closes
# kcov's reporting descriptor and execs) is bracketed with
# SCODE_COVERAGE_EXCLUDE_START/END so it leaves the denominator instead of
# being counted as permanently missed; the runtime suites still launch
# through it.
SHELL_COVERAGE_MIN ?= 80
# Floor applied to this platform's report alone at the end of `make coverage`;
# the default 0 only reports the number.
COVERAGE_SINGLE_MIN ?= 0

.PHONY: install uninstall check-prefix test test-js lint coverage coverage-gate release-pins check-pins

check-prefix:
	@case '$(PREFIX)' in \
		'') echo "PREFIX must not be empty" >&2; exit 1 ;; \
		'/') echo "PREFIX=/ is unsafe and not supported" >&2; exit 1 ;; \
		'~'*) echo "PREFIX must be shell-expanded; use PREFIX=\$$HOME/.local" >&2; exit 1 ;; \
	esac

install: check-prefix
	install -d "$(BINDIR)"
	install -d "$(LIBDIR)"
	install -d "$(EXAMPLESDIR)"
	install -m 755 scode "$(BINDIR)/scode"
	install -m 644 lib/no-sandbox.js "$(LIBDIR)/no-sandbox.js"
	install -m 644 LICENSE "$(SHAREDIR)/LICENSE"
	install -m 644 $(EXAMPLE_FILES) "$(EXAMPLESDIR)/"

uninstall: check-prefix
	rm -f "$(BINDIR)/scode"
	rm -f "$(LIBDIR)/no-sandbox.js"
	rm -f "$(SHAREDIR)/LICENSE"
	rm -f $(addprefix "$(EXAMPLESDIR)/",$(notdir $(EXAMPLE_FILES)))
	rmdir "$(EXAMPLESDIR)" 2>/dev/null || true
	rmdir "$(SHAREDIR)" 2>/dev/null || true
	rmdir "$(LIBDIR)" 2>/dev/null || true

lint:
	shellcheck scode

test-js:
	@command -v node >/dev/null 2>&1 || { echo "node >= 22 is required" >&2; exit 1; }
	@node -e 'if (Number(process.versions.node.split(".")[0]) < 22) process.exit(1)' \
		|| { echo "node >= 22 is required" >&2; exit 1; }
	@test -d node_modules || { echo "node_modules missing (run npm ci)" >&2; exit 1; }
	SCODE_TEST=1 node --test test/no-sandbox.test.js

test: lint test-js
	bats test/

# Collect coverage on this platform: kcov for the shell (the report lands in
# coverage/shell-<platform>.cobertura.xml, beside a .source-sha256 sidecar
# naming the scode it measured) and c8 for lib/no-sandbox.js. The shell
# floor is NOT enforced here: macOS and Linux each skip the other's
# runtime-sandbox tests, so one platform's report understates what the suite
# exercises. `coverage-gate` enforces it over the merged reports (CI collects
# on both and gates once); COVERAGE_SINGLE_MIN=80 gates this report alone.
coverage: lint
	@command -v kcov >/dev/null 2>&1 || { echo "kcov is required for shell coverage" >&2; exit 1; }
	@command -v node >/dev/null 2>&1 || { echo "node >= 22 is required" >&2; exit 1; }
	@test -x node_modules/.bin/c8 || { echo "node_modules missing (run npm ci)" >&2; exit 1; }
	@set -eu; \
		platform="$$(uname -s | tr '[:upper:]' '[:lower:]')"; \
		shell_cov="$$(mktemp -d /tmp/scode-shell-coverage.XXXXXX)"; \
		node_cov="$$(mktemp -d /tmp/scode-node-coverage.XXXXXX)"; \
		trap 'rm -rf "$$shell_cov" "$$node_cov"' EXIT INT TERM; \
		mkdir -p coverage; \
		NODE_V8_COVERAGE="$$node_cov" SCODE_TEST=1 node --test test/no-sandbox.test.js; \
		NODE_V8_COVERAGE="$$node_cov" \
		SCODE_COVERAGE_TARGET="$(CURDIR)/scode" \
		SCODE_COVERAGE_DIR="$$shell_cov" \
		SCODE_KCOV_BINARY="$$(command -v kcov)" \
		SCODE_UNDER_TEST="$(CURDIR)/test/kcov-scode-wrapper.bash" \
		bats test/; \
		report="$$(find "$$shell_cov" -name cobertura.xml -print -quit)"; \
		[ -n "$$report" ] || { echo "kcov produced no cobertura report" >&2; exit 1; }; \
		cp "$$report" "coverage/shell-$$platform.cobertura.xml"; \
		shasum -a 256 scode | cut -d' ' -f1 > "coverage/shell-$$platform.cobertura.xml.source-sha256"; \
		node scripts/coverage-gate.js "$(COVERAGE_SINGLE_MIN)" "coverage/shell-$$platform.cobertura.xml"; \
		node_modules/.bin/c8 report --temp-directory="$$node_cov" --all \
			--include='lib/no-sandbox.js' --reporter=text \
			--check-coverage --lines=80 --functions=80 --branches=80 --statements=80

# Enforce the shell floor over every collected report (a line counts when any
# platform hit it). CI runs this once with the macOS and Linux artifacts. A
# report whose sidecar names a different scode than the one in the tree is
# refused, so a stale report cannot lift the result.
COVERAGE_REPORTS ?= $(wildcard coverage/shell-*.cobertura.xml)
coverage-gate:
	@[ -n "$(COVERAGE_REPORTS)" ] || { echo "no coverage/shell-*.cobertura.xml to gate (run make coverage first)" >&2; exit 1; }
	@node scripts/coverage-gate.js "$(SHELL_COVERAGE_MIN)" $(COVERAGE_REPORTS)

# Rewrite the README install pins (commit + artifact checksums) from the
# release tag. Run after tagging; see docs/RELEASE-GATE.md.
release-pins:
	./scripts/release-pins.sh update

# Verify the README pins match the release tag without modifying anything.
check-pins:
	./scripts/release-pins.sh check
