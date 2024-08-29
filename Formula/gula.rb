class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.9.tar.gz"
  sha256 "c12e74f36bd7f17d90e04e5218ec4f6cc058563fd1c4c9d7b8072dc762521384"
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
