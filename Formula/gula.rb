class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.159.tar.gz"
  sha256 "c08691dd8c0ecffd92ee8f21cbe1b4f47cdc69b3349a9d76df2cbb3891a96b2a"
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
