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

.PHONY: install uninstall check-prefix test test-js lint coverage release-pins check-pins

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

coverage: lint
	@command -v kcov >/dev/null 2>&1 || { echo "kcov is required for shell coverage" >&2; exit 1; }
	@command -v node >/dev/null 2>&1 || { echo "node >= 22 is required" >&2; exit 1; }
	@test -x node_modules/.bin/c8 || { echo "node_modules missing (run npm ci)" >&2; exit 1; }
	@set -eu; \
		shell_cov="$$(mktemp -d /tmp/scode-shell-coverage.XXXXXX)"; \
		node_cov="$$(mktemp -d /tmp/scode-node-coverage.XXXXXX)"; \
		trap 'rm -rf "$$shell_cov" "$$node_cov"' EXIT INT TERM; \
		NODE_V8_COVERAGE="$$node_cov" SCODE_TEST=1 node --test test/no-sandbox.test.js; \
		NODE_V8_COVERAGE="$$node_cov" \
		SCODE_COVERAGE_TARGET="$(CURDIR)/scode" \
		SCODE_COVERAGE_DIR="$$shell_cov" \
		SCODE_KCOV_BINARY="$$(command -v kcov)" \
		SCODE_UNDER_TEST="$(CURDIR)/test/kcov-scode-wrapper.bash" \
		bats test/; \
		coverage_json="$$(find "$$shell_cov" -name coverage.json -print -quit)"; \
		node -e 'const fs=require("fs"); const p=process.argv[1]; const d=JSON.parse(fs.readFileSync(p)); const n=Number(d.percent_covered); console.log(`Shell line coverage: $${n.toFixed(2)}% ($${d.covered_lines}/$${d.total_lines})`); if(n<80) process.exit(1)' "$$coverage_json"; \
		node_modules/.bin/c8 report --temp-directory="$$node_cov" --all \
			--include='lib/no-sandbox.js' --reporter=text \
			--check-coverage --lines=80 --functions=80 --branches=80 --statements=80

# Rewrite the README install pins (commit + artifact checksums) from the
# release tag. Run after tagging; see docs/RELEASE-GATE.md.
release-pins:
	./scripts/release-pins.sh update

# Verify the README pins match the release tag without modifying anything.
check-pins:
	./scripts/release-pins.sh check
