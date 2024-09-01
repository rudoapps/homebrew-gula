class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.17.tar.gz"
  sha256 "07a72eead2bd76bd476ee1496da541c51c18dde6be18b4bcfb97d1c6f7c9ac84"
  license "MIT"

  # Dependencias
  depends_on "ruby" if MacOS.version <= :mojave
  depends_on "jq" # Añade jq como una dependencia

  def install
    # Instalar la gema xcodeproj
    system "gem", "install", "xcodeproj" if MacOS.version <= :mojave
    
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
