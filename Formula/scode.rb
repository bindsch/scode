class Scode < Formula
  desc "Safe sandbox wrapper for AI coding harnesses"
  homepage "https://github.com/bindsch/scode"
  url "https://github.com/bindsch/scode.git", tag: "v0.1.0"
  license "MIT"

  head "https://github.com/bindsch/scode.git", branch: "main"

  on_linux do
    depends_on "bubblewrap"
  end

  def install
    bin.install "scode"
    (lib/"scode").install "lib/no-sandbox.js"
    (pkgshare/"examples").install Dir["examples/*.yaml"]
  end

  test do
    # Version and file presence
    assert_match(/^scode \d+\.\d+\.\d+$/, shell_output("#{bin}/scode --version").strip)
    assert_predicate lib/"scode/no-sandbox.js", :exist?
    assert_predicate pkgshare/"examples/sandbox.yaml", :exist?
    assert_predicate pkgshare/"examples/sandbox-strict.yaml", :exist?
    assert_predicate pkgshare/"examples/sandbox-paranoid.yaml", :exist?
    assert_predicate pkgshare/"examples/sandbox-permissive.yaml", :exist?
    assert_predicate pkgshare/"examples/sandbox-cloud-eng.yaml", :exist?

    # Help output covers key flags and subcommands
    help = shell_output("#{bin}/scode --help")
    assert_match "--strict", help
    assert_match "--no-net", help
    assert_match "--trust", help
    assert_match "audit", help

    # Dry-run generates a sandbox profile without errors
    system bin/"scode", "--dry-run", "-C", testpath, "--", "true"

    # Strict + no-net dry-run
    system bin/"scode", "--dry-run", "--strict", "--no-net", "-C", testpath, "--", "true"

    # Audit subcommand parses denial patterns
    (testpath/"deny.log").write "deny(file-read-data) /tmp/brew-test-path\n"
    assert_match "/tmp/brew-test-path", shell_output("#{bin}/scode audit #{testpath}/deny.log")
  end
end
