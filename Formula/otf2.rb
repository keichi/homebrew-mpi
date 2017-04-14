class Otf2 < Formula
  desc "Open Trace Format Version 2"
  homepage "http://www.vi-hps.org/projects/score-p"
  url "http://www.vi-hps.org/upload/packages/otf2/otf2-2.0.tar.gz"
  sha256 "bafe0ac08e0a13e71568e5774dc83bd305d907159b4ceeb53d2e9f6e29462754"

  def install
    system "./configure", "--disable-debug",
                          "--disable-dependency-tracking",
                          "--disable-silent-rules",
                          "--prefix=#{prefix}",
                          "--enable-shared"
    system "make", "install"
  end

  test do
    system "#{bin}/otf2-config", "--help"
    system "#{bin}/otf2-estimator", "--help"
    system "#{bin}/otf2-marker", "--help"
    system "#{bin}/otf2-print", "--help"
    system "#{bin}/otf2-snapshots", "--help"
    system "#{bin}/otf2-template", "--help"
  end
end
