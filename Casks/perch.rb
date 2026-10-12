# Perch's own tap is this repository:
#   brew tap cryptowizard0/perch https://github.com/cryptowizard0/perch
#   brew install --cask cryptowizard0/perch/perch
# The full name matters: Homebrew loads casks from a non-official tap only once trusted, and installing by full
# name trusts this cask (`brew install --cask perch` is refused).
# The app is ad-hoc signed, not notarized: macOS asks once (System Settings → Privacy & Security → Open Anyway).
# Installing changes no agent config; that happens only when you click Connect in the notch.
# scripts/package-release.sh sets version and sha256.
cask "perch" do
  version "0.4.0"
  sha256 "de42366861944cb05f87dcb779ec1434b5b69067d3f6d037dfe31ad62ce4ddb3"

  url "https://github.com/cryptowizard0/perch/releases/download/v#{version}/perch-#{version}-macos-arm64.zip"
  name "Perch"
  desc "Notch panel for AI coding agent sessions"
  homepage "https://github.com/cryptowizard0/perch"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Perch.app"
  # A script that runs ~/.perch/bin/perch, which the app installs on first open without the quarantine flag
  # (the bundled binary itself is killed when run quarantined from a shell).
  binary "#{appdir}/Perch.app/Contents/Resources/bin/perch"

  # `perch uninstall` from ~/.perch/bin (the app installs it on first open; never opened, nothing to remove).
  # brew runs this on upgrade and reinstall too, where it would disconnect every agent: skip it when the brew
  # process running it is an upgrade or a reinstall.
  uninstall quit:   "dev.perch.app",
            script: {
              executable:   "/bin/sh",
              args:         [
                "-c",
                'case "$(ps -o command= -p "$PPID")" in *" upgrade"*|*" reinstall"*) exit 0 ;; esac; ' \
                'p="$HOME/.perch/bin/perch"; [ ! -x "$p" ] || "$p" uninstall',
              ],
              must_succeed: false,
            }

  # `uninstall` has already run `perch uninstall`; this is the rest of `perch uninstall --purge`.
  zap trash: [
    "~/.perch",
    "~/Library/Preferences/dev.perch.app.plist",
  ]
end
