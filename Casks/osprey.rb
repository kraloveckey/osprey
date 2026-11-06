cask "osprey" do
  version "1.0.0"
  sha256 :no_check

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
