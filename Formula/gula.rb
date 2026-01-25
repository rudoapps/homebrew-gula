class Gula < Formula
  desc "CLI para desarrollo móvil"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/v0.0.218.tar.gz"
  sha256 "3d176d0af77d54ebdc77723083dd2ba0d01a53c03e18ee2170733a21674aa1e3"
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
