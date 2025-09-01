class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.73 .tar.gz"
  sha256 "987d10f6eb18757d6bb23ac068f3c154b5372b55fe854d64db6f2740566e7cf1"
  license "MIT"

  # Dependencias
  depends_on "ruby"
  depends_on "jq" # Añade jq como una dependencia

  def install
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
