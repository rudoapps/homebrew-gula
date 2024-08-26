class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.2.tar.gz"
  sha256 "773b457607040c4e42ef94a0217099535bb23c69b9ad519f969265fd6de2fcf7"
  license "MIT"

  def install
    bin.install "gula"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
