class Gula < Formula
  desc "CLI para desarrollo móvil"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/v0.0.318.tar.gz"
  sha256 "71f9030a041e3bdca14ac1a58fb4c92746690079b99ecdf11775c0f34eed27e4"
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
