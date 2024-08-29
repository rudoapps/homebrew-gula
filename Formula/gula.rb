class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.5.tar.gz"
  sha256 "9d58a82ce7dbdb2c4e304e2a04cf9a68fe6b372e3df559b1dadc569a24cfc827"
  license "MIT"

  # Dependencias
  # depends_on "ruby" if MacOS.version <= :mojave

  def install
    # Instalar la gema xcodeproj
    # system "gem", "install", "xcodeproj"

    bin.install "gula"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
