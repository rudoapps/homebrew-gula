class Gula < Formula
  desc "CLI para desarrollo móvil y agente IA"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/v0.0.210.tar.gz"
  sha256 "c2da6cd99067f2a5ac0570e008bc405979cd430079a9217399d19cd296922ce9"
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

    # Compilar e instalar gula-ai (Go TUI)
    cd "gula-ai" do
      system "go", "build", *std_go_args(ldflags: "-s -w"), "-o", bin/"gula-ai", "./cmd/gula-ai"
    end
  end

  test do
    system "#{bin}/gula", "--help"
  end
end
