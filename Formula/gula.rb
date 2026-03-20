class Gula < Formula
  desc "CLI para desarrollo móvil"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/v0.0.257.tar.gz"
  sha256 "b0690e991d33489e2c2f82d62bd83671ba9031e0d2d66bde3962088679363c1a"
  license "MIT"

  depends_on "go" => :build
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
