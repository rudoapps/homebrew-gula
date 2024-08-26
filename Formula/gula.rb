class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.3.tar.gz"
  sha256 "3725d0eb799bdf7381a7c438e91e698f76ddf3bf2d5396034e93ddec4732d3a1"
  license "MIT"

  def install
    bin.install "gula"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
