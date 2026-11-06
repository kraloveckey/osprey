#!/usr/bin/env bash
# Rewrites Formula/osprey.rb and Casks/osprey.rb with the real SHA-256 of the
# release archives. Run by .github/workflows/release.yml after a release is
# published; can also be run by hand:
#   scripts/update_homebrew.sh 1.0.0 path/to/downloaded/assets
set -euo pipefail

VERSION="${1:?usage: update_homebrew.sh <version> <assets-dir>}"
DIR="${2:?usage: update_homebrew.sh <version> <assets-dir>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

sha() {
    local file="$DIR/$1"
    [ -f "$file" ] || { echo "missing release asset: $1" >&2; exit 1; }
    if command -v sha256sum >/dev/null; then sha256sum "$file" | cut -d' ' -f1
    else shasum -a 256 "$file" | cut -d' ' -f1; fi
}

MAC_ARM=$(sha osprey-macos-arm64.tar.gz)
MAC_X86=$(sha osprey-macos-x86_64.tar.gz)
LINUX_X86=$(sha osprey-linux-x86_64.tar.gz)
LINUX_ARM=$(sha osprey-linux-arm64.tar.gz)
APP_ZIP=$(sha Osprey-macOS-arm64.zip)

BASE="https://github.com/kraloveckey/osprey/releases/download/v#{version}"

cat > "$ROOT/Formula/osprey.rb" <<RUBY
class Osprey < Formula
  desc "Hardware telemetry and system monitor CLI for macOS and Linux"
  homepage "https://github.com/kraloveckey/osprey"
  version "$VERSION"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "$BASE/osprey-macos-arm64.tar.gz"
      sha256 "$MAC_ARM"
    else
      url "$BASE/osprey-macos-x86_64.tar.gz"
      sha256 "$MAC_X86"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "$BASE/osprey-linux-arm64.tar.gz"
      sha256 "$LINUX_ARM"
    else
      url "$BASE/osprey-linux-x86_64.tar.gz"
      sha256 "$LINUX_X86"
    end
  end

  def install
    bin.install "osprey"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/osprey --version")
  end
end
RUBY

cat > "$ROOT/Casks/osprey.rb" <<RUBY
cask "osprey" do
  version "$VERSION"
  sha256 "$APP_ZIP"

  url "https://github.com/kraloveckey/osprey/releases/download/v#{version}/Osprey-macOS-arm64.zip"
  name "Osprey"
  desc "Native hardware telemetry, system monitor & desktop HUD for macOS"
  homepage "https://github.com/kraloveckey/osprey"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Osprey.app"
  binary "#{appdir}/Osprey.app/Contents/MacOS/osprey-cli", target: "osprey"

  zap trash: [
    "~/Library/Preferences/com.kraloveckey.osprey.plist",
    "~/Library/Application Support/Osprey",
  ]
end
RUBY

echo "Homebrew formula and cask updated for v$VERSION"
