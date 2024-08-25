class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"  # Reemplaza con tu URL
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.1.tar.gz"  # URL del tarball de tu versión
  sha256 "773b457607040c4e42ef94a0217099535bb23c69b9ad519f969265fd6de2fcf7"  # El checksum SHA256 de tu archivo tar.gz
  license "MIT"  # O la licencia que corresponda

  def install
    bin.install "gula"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
