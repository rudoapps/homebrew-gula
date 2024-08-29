class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.6.tar.gz"
  sha256 "4622a0a1b45dfb52288dd2d664582a1e834f07881a1983d39d474e9f0c60ebad"
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
