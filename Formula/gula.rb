class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.88.tar.gz"
  sha256 "16022bcbd275eadaae07a1810182659d4df801dc40219b83d8a6d224edd57ebd"
  license "MIT"

  # Dependencias
  depends_on "ruby"
  depends_on "jq" # Añade jq como una dependencia
  
  def install
    bin.install "gula"
    (share/"support/scripts").install "scripts"
    
    # Instalar xcodeproj y dependencias en el directorio de homebrew
    ENV["GEM_HOME"] = libexec
    system Formula["ruby"].opt_bin/"gem", "install", "xcodeproj", "--no-document", "--quiet"
    system Formula["ruby"].opt_bin/"gem", "install", "nkf", "--no-document", "--quiet"
    
    # Crear wrapper script que use las gemas instaladas
    original_gula = bin/"gula"
    original_gula.rename(libexec/"gula-original")
    
    (bin/"gula").write <<~EOS
      #!/bin/bash
      export GEM_HOME="#{libexec}"
      export GEM_PATH="#{libexec}"
      export PATH="#{Formula["ruby"].opt_bin}:$PATH"
      exec "#{libexec}/gula-original" "$@"
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
