class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.7.tar.gz"
  sha256 "636d5c754143803aececb10da89df33638bec78504d4bba7c1621d9371eea1ca"
  license "MIT"

  # Dependencias
  # depends_on "ruby" if MacOS.version <= :mojave

  def install
    # Instalar la gema xcodeproj
    # system "gem", "install", "xcodeproj"

    bin.install "gula"
    (share/"gula-support").install "scripts"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
