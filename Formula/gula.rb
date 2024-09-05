class Gula < Formula
  desc "Instalador de componentes de gula"
  homepage "https://github.com/rudoapps/gula"
  url "https://github.com/rudoapps/homebrew-gula/archive/refs/tags/0.0.22.tar.gz"
  sha256 "81a06cab7b6df7af45a6554313552b26231487387b6a8a7b0a9b8a984494f7be"
  license "MIT"

  # Dependencias
  depends_on "ruby" if MacOS.version <= :mojave
  depends_on "jq"

  # Recurso para xcodeproj
  resource "xcodeproj" do
    url "https://rubygems.org/gems/xcodeproj-1.25.0.gem"
    sha256 "aa0bc57eb3bd616357088a9b41794ef79bdcf7ba969000642aec1e768e7b06ce"
  end

  def install
    # Configura el entorno para usar la versión de Ruby de Homebrew
    ENV["GEM_HOME"] = libexec
    ENV["GEM_PATH"] = "#{libexec}:/usr/local/lib/ruby/gems/#{Formula["ruby"].version}"  # Cambia esta ruta a la versión correcta de Ruby
    ENV["PATH"] = "#{Formula["ruby"].opt_bin}:#{libexec}/bin:#{ENV["PATH"]}"

    # Instala la versión de Bundler compatible con Ruby 2.6.10 (si es necesario)
    system "gem", "install", "bundler", "-v", "2.4.22"

    # Instala la gema xcodeproj sin Bundler, directamente con gem install
    resource("xcodeproj").stage do
      system "gem", "install", "xcodeproj-1.25.0.gem"
    end

    bin.install "gula"
    (share/"support/scripts").install "scripts"
  end

  def post_install
    bin.install_symlink share/"support/scripts" => "gula-scripts"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
