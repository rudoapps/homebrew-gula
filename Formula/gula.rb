class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.142.tar.gz"
  sha256 "84dd28256653d669bd8adb14082f5fbf392d8b7ebadda9d9fb0dd4cd392b485e"
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
