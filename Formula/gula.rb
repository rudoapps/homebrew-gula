class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/v0.0.208.tar.gz"
  sha256 "64382c1b9c449779ae98b2f60fdac2ca489142b0d44d5b9176f3a0b61b6469a5"
  license "MIT"

  depends_on "jq"
  depends_on "glow" => :recommended  # For better markdown/table rendering

  def install
    # Instalar script principal
    bin.install "gula"

    # Instalar VERSION file (single source of truth for version)
    prefix.install "VERSION"

    # Instalar scripts en opt/gula/scripts (donde el script los busca)
    prefix.install "scripts"
  end

  test do
    system "#{bin}/gula", "--help"
  end
end
