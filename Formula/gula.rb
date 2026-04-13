class Gula < Formula
  desc "CLI para desarrollo móvil"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/v0.0.355.tar.gz"
  sha256 "caf1f1048ba2d0ed229c94b8a4a1dd2e2d2c21dee545e1be5bd6be4ca1bf67a5"
  license "MIT"

  depends_on "go" => :build
  depends_on "jq"
  depends_on "python@3.12"  # Required by gula ai (CLI agent)
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
