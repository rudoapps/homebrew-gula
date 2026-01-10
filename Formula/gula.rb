class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.165.tar.gz"
  sha256 "2efb1a35e6a8d7a2091992910b934a50facf403c26a3aaca1acd89e02c6dd105"
  license "MIT"

  depends_on "jq"

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
