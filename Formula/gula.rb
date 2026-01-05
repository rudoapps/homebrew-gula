class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.143.tar.gz"
  sha256 "b2a371bab76da10ba211b118242c64c3adec9623b38b5fdfd144350d95caa280"
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
