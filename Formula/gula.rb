class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.86.tar.gz"
  sha256 "33b2d30781e7fddee77f1dc5268fc14732e8bb70682285773e66d58007a57a2d"
  license "MIT"

  # Dependencias
  depends_on "ruby"
  depends_on "jq" # Añade jq como una dependencia
  
  def install
    bin.install "gula"
    (share/"support/scripts").install "scripts"
    
    # Instalar xcodeproj en el directorio de homebrew
    ENV["GEM_HOME"] = libexec
    system Formula["ruby"].opt_bin/"gem", "install", "xcodeproj", "--no-document", "--quiet"
    
    # Crear wrapper script que use las gemas instaladas
    (bin/"gula").unlink
    (bin/"gula").write <<~EOS
      #!/bin/bash
      export GEM_HOME="#{libexec}"
      export GEM_PATH="#{libexec}"
      exec "#{buildpath}/gula" "$@"
    EOS
    (bin/"gula").chmod 0755
  end

  def post_install
    bin.install_symlink share/"support/scripts" => "gula-scripts"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
