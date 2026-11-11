# Homebrew formula for axclick. This file is the source of truth; scripts/release-formula.sh
# fills in the version and checksum and copies it to the 5uvarna/homebrew-tap repository.
class Axclick < Formula
  desc "Click anything on your Mac with the keyboard"
  homepage "https://github.com/5uvarna/axclick"
  url "https://github.com/5uvarna/axclick/archive/refs/tags/v@VERSION@.tar.gz"
  sha256 "@SHA256@"
  license "GPL-3.0-only"
  head "https://github.com/5uvarna/axclick.git", branch: "main"

  depends_on macos: :ventura

  def install
    ENV["AXCLICK_ADHOC"] = "1"
    system "./build.sh"
    prefix.install "build/axclick.app"
    bin.install "build/axclick"
  end

  def caveats
    <<~EOS
      To start the axclick menu bar app:
        open #{opt_prefix}/axclick.app

      To find it in your Applications folder and Spotlight:
        ln -sf #{opt_prefix}/axclick.app ~/Applications/axclick.app

      On first launch axclick asks for Accessibility access. Homebrew builds are
      signed ad hoc, so after each `brew upgrade axclick` turn axclick off and on
      again in System Settings > Privacy & Security > Accessibility.
    EOS
  end

  test do
    assert_match "usage: axclick", shell_output("#{bin}/axclick 2>&1", 1)
    assert_path_exists prefix/"axclick.app/Contents/MacOS/axclick"
  end
end
