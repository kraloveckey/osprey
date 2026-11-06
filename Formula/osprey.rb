class Osprey < Formula
  desc "Hardware telemetry and system monitor CLI for macOS and Linux"
  homepage "https://github.com/kraloveckey/osprey"
  version "1.0.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/kraloveckey/osprey/releases/download/v#{version}/osprey-macos-arm64.tar.gz"
    else
      url "https://github.com/kraloveckey/osprey/releases/download/v#{version}/osprey-macos-x86_64.tar.gz"
    end
    sha256 :no_check
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/kraloveckey/osprey/releases/download/v#{version}/osprey-linux-arm64.tar.gz"
    else
      url "https://github.com/kraloveckey/osprey/releases/download/v#{version}/osprey-linux-x86_64.tar.gz"
    end
    sha256 :no_check
  end

  def install
    bin.install "osprey"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/osprey --version")
  end
end
