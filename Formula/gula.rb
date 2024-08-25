class Gula < Formula
  desc "Una descripción breve de lo que hace tu script"
  homepage "https://github.com/tu_usuario/gula"  # Reemplaza con tu URL
  url "https://github.com/tu_usuario/gula/archive/refs/tags/v1.0.tar.gz"  # URL del tarball de tu versión
  sha256 "tu_sha256_sum"  # El checksum SHA256 de tu archivo tar.gz
  license "MIT"  # O la licencia que corresponda

  def install
    bin.install "gula"
  end

  test do
    system "#{bin}/gula", "install", "prueba"
  end
end
