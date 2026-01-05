class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.140.tar.gz"
  sha256 "508412cb0a8a40f3a6e3168d8d7a489d4f30c56032227722d631a02851ad6dea"
  license "MIT"

  depends_on "jq"
  depends_on "gum"

  def install
    # Instalar script principal
    bin.install "gula"

    # Instalar scripts en opt/gula/scripts (donde el script los busca)
    prefix.install "scripts"
  end

  test do
    system "#{bin}/gula", "--help"
  end
end
