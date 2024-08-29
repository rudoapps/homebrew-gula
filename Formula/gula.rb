class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.10.tar.gz"
  sha256 "2263563fafea2e9a7a084809d26c1ec7f5bbac1c08fbd454c60c0b0fc100eb12"
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
