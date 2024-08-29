class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.11.tar.gz"
  sha256 "1ae82cceacd9af33ec12646cd311955a2973af3fc5f741777d3189d6e544f7c6"
  license "MIT"

  # Dependencias
  # depends_on "ruby" if MacOS.version <= :mojave

  def install
    # Instalar la gema xcodeproj
    # system "gem", "install", "xcodeproj"

    bin.install "gula"
    (share/"support").install "scripts"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
