class BrainZsh < Formula
  desc "Context-aware CLI layer for Zsh — project detection, AI routing, error parsing"
  homepage "https://github.com/frogboynayeem/brain.zsh"
  url "https://github.com/frogboynayeem/brain.zsh/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "eb4323987b43d71703f79764d2e8845ff0454c293223a2c13c7589b483e72763"
  license "MIT"
  head "https://github.com/frogboynayeem/brain.zsh.git", branch: "main"

  depends_on "zsh"

  def install
    pkgshare.install "brain.zsh"
    pkgshare.install Dir["ai/"]
    pkgshare.install Dir["core/"]
    pkgshare.install Dir["layouts/"]
    pkgshare.install Dir["utils/"]
    pkgshare.install "terminal-os.zsh"
    pkgshare.install "LICENSE"
  end

  def caveats
    <<~EOS
      Add the following to your ~/.zshrc:

        source "#{opt_pkgshare}/brain.zsh"

      Then reload your shell:

        source ~/.zshrc

      Or open a new terminal. Then type `brain` to get started.
    EOS
  end

  test do
    assert_match "brain", shell_output("zsh -c 'source #{opt_pkgshare}/brain.zsh && brain help'")
  end
end
