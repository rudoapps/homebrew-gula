class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.18.tar.gz"
  sha256 "0639b6445ccb703df2e5c373376d5ffd59e08e67d0599679c7232c00efcdb2eb"
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
