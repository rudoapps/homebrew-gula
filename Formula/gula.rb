class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.155.tar.gz"
  sha256 "9574f57156226ea978b1cf0bd7f40e12a8d1f634a89af3ca345b3a0e40081d84"
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
