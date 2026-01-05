class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.141.tar.gz"
  sha256 "a6d4fd4f20c67d652b98e8f4498451901f429c332d636d032125d3082748e2a2"
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
