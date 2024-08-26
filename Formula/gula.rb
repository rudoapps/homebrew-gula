class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.2.tar.gz"
  sha256 "1199b79486bb208830ee28d441cebd206abf4a787ce4dd8ab3d1ce0b372d508b"
  license "MIT"

  def install
    bin.install "gula"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
