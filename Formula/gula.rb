class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.90.tar.gz"
  sha256 "7e683a8fa56eb392c53f2f197107c2095bd311c24a2b8100566f9b04950fb586"
  license "MIT"

  # Dependencias
  depends_on "ruby"
  depends_on "jq" # Añade jq como una dependencia
  
  def install
    bin.install "gula"
    (share/"support/scripts").install "scripts"
    
    # Instalar xcodeproj y todas sus dependencias en el directorio de homebrew
    ENV["GEM_HOME"] = libexec
    # Instalar dependencias base primero
    system Formula["ruby"].opt_bin/"gem", "install", "rexml", "--no-document", "--quiet"
    system Formula["ruby"].opt_bin/"gem", "install", "nkf", "--no-document", "--quiet"
    system Formula["ruby"].opt_bin/"gem", "install", "atomos", "--no-document", "--quiet"
    system Formula["ruby"].opt_bin/"gem", "install", "claide", "--no-document", "--quiet"
    system Formula["ruby"].opt_bin/"gem", "install", "colored2", "--no-document", "--quiet"
    system Formula["ruby"].opt_bin/"gem", "install", "nanaimo", "--no-document", "--quiet"
    system Formula["ruby"].opt_bin/"gem", "install", "CFPropertyList", "--no-document", "--quiet"
    # Finalmente instalar xcodeproj
    system Formula["ruby"].opt_bin/"gem", "install", "xcodeproj", "--no-document", "--quiet"
    
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
