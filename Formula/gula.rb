class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.84.tar.gz"
  sha256 "f940a2a775476f2a09cbac72c70dd9b28841d852c7fced09245d295ba6fc54a3"
  license "MIT"

  # Dependencias
  depends_on "ruby"
  depends_on "jq" # Añade jq como una dependencia
  
  resource "xcodeproj" do
    url "https://rubygems.org/downloads/xcodeproj-1.23.0.gem"
    sha256 "6b8663e2ad7b7ff31e4b8a4b998e8c1a8d4a20a7e72c8cebcf62f5f4e2b4e6a5"
  end

  def install
    bin.install "gula"
    (share/"support/scripts").install "scripts"
    
    # Instalar gemas Ruby necesarias
    resources.each do |r|
      r.stage do
        system "gem", "install", Dir["*.gem"].first, "--install-dir", libexec
      end
    end
  end

  def post_install
    bin.install_symlink share/"support/scripts" => "gula-scripts"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
