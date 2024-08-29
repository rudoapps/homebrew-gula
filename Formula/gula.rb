class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.13.tar.gz"
  sha256 "6906718f3df0046b1b926e904a8a7cd3b385b6e831dbd21d6a580aeea84b11f6"
  license "MIT"

  # Dependencias
  # depends_on "ruby" if MacOS.version <= :mojave

  def install
    # Instalar la gema xcodeproj
    # system "gem", "install", "xcodeproj"

    bin.install "gula"
    (share/"support/scripts").install "scripts"
  end

  def post_install
    bin.install_symlink share/"support/scripts" => "gula-scripts"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
