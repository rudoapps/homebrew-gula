class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.171.tar.gz"
  sha256 "511a2b515c15457020fb6a8f800a4533189f6ddb1aa991855ba5c2fc3c33824d"
  license "MIT"

  depends_on "jq"
  depends_on "glow" => :recommended  # For better markdown/table rendering

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
