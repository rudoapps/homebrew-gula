class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.4.tar.gz"
  sha256 "3c3443085006509265c95d5d3ef6d0707dd0b7c9e55f35108b7bc6015c4698a5"
  license "MIT"

  def install
    bin.install "gula"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
