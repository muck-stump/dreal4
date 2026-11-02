# Copyright (c) 2018, Massachusetts Institute of Technology.
# Copyright (c) 2018, Toyota Research Institute.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Copyright (c) 2009-2018, Homebrew contributors.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Local copy of robotlocomotion/director's ibex@2.7.4 formula (license above)
# with two extra patches so that it also builds on Apple Silicon:
#
#   1. ibex's `waf` script still has a `python2.7` shebang, and Homebrew no
#      longer ships Python 2. waf 2.0.12 runs fine under Python 3, but it
#      uses the `imp` module and the `rU` open mode that were removed in
#      Python 3.11/3.12, so we pin it to Homebrew's Python 3.10.
#   2. ibex's CLP plugin looks for pkg-config at /usr/local/bin/pkg-config,
#      which only exists on Intel Macs; on Apple Silicon Homebrew lives in
#      /opt/homebrew. (It also passes waf a stripped-down environment, so
#      Homebrew's pkg-config shims cannot be used here.)
#   3. ibex.pc advertises -msse3 and -ffloat-store in its Cflags. arm64 clang
#      rejects -msse3 outright (Apple Silicon has no SSE), and it rejects
#      -ffloat-store too, which matters because dReal builds with -Werror.
#
# dReal needs exactly ibex 2.7.4 (the upstream ibex formula is 2.9.x), so
# we build this pinned version from source.

class IbexAT274 < Formula
  desc "C++ library for constraint processing over real numbers"
  homepage "https://github.com/ibex-team/ibex-lib"
  url "https://github.com/dreal-deps/ibex-lib/archive/ibex-2.7.4_13.tar.gz"
  version "2.7.4"
  sha256 "d5524eb7e8f1edf6fe7867bea617bf450ad05e2c2eb5e8048a8532619e0ec0e1"
  revision 13

  bottle do
    root_url "https://drake-homebrew.csail.mit.edu/bottles"
    sha256 cellar: :any, big_sur: "4b874fed3174c68a99ca4b822b1802c48094dc1d47f95e3eeba9206d35993e82"
    sha256 cellar: :any, catalina: "4a1c80f394a5a8078f34d0bca0ba137f8bd2935a9954b875a8c3fb8007b197b0"
  end

  keg_only :versioned_formula

  depends_on "pkg-config" => [:build, :test]
  depends_on "python@3.10" => :build
  depends_on "clp"

  def install
    ENV.cxx11

    # Patch 1: run waf with Python 3.10 instead of the missing python2.7.
    inreplace "waf", "#!/usr/bin/env python2.7", "#!#{Formula["python@3.10"].opt_bin}/python3.10"

    # Patch 2: ibex hardcodes Intel-Mac Homebrew's pkg-config location on
    # macOS; point it at this system's Homebrew prefix instead.
    inreplace "plugins/lp_lib_clp/wscript",
              "/usr/local/bin/pkg-config",
              "#{HOMEBREW_PREFIX}/bin/pkg-config"

    # Reported 9 Oct 2017 https://github.com/ibex-team/ibex-lib/issues/286
    ENV.deparallelize
    args = %W[
      --prefix=#{prefix}
      --enable-shared
      --with-optim
      --with-solver
      --with-affine-extended
      --interval-lib=filib
      --lp-lib=clp
      --clp-path=#{Formula["clp"].opt_prefix}
    ]
    system "./waf", "configure", *args
    system "./waf", "install"

    pkgshare.install %w[examples plugins/solver/benchs]
    (pkgshare/"examples/symb01.txt").write <<~EOS
      function f(x)
        return ((2*x,-x);(-x,3*x));
      end
    EOS
    inreplace "#{share}/pkgconfig/ibex.pc", prefix, opt_prefix

    # Patch 3: drop x86-only flags from ibex.pc on arm64.
    if Hardware::CPU.arm?
      inreplace "#{share}/pkgconfig/ibex.pc", " -msse3", ""
      inreplace "#{share}/pkgconfig/ibex.pc", " -ffloat-store", ""
    end
  end

  test do
    ENV.cxx11
    cp_r (pkgshare/"examples").children, testpath

    # so that pkg-config can remain a build-time only dependency
    inreplace %w[makefile slam/makefile] do |s|
      s.gsub!(/CXXFLAGS.*pkg-config --cflags ibex./,
              "CXXFLAGS := -I#{include} -I#{include}/ibex "\
                          "-I#{include}/ibex/3rd "\
                          "`PKG_CONFIG_PATH=#{Formula["clp"].opt_lib}/pkgconfig pkg-config --cflags clp`")
      s.gsub!(/LIBS.*pkg-config --libs  ibex./,
              "LIBS := -L#{lib} -libex "\
              "`PKG_CONFIG_PATH=#{Formula["clp"].opt_lib}/pkgconfig pkg-config --libs clp`")
    end

    (1..8).each do |n|
      system "make", "lab#{n}"
      system "./lab#{n}"
    end

    (1..3).each do |n|
      system "make", "-C", "slam", "slam#{n}"
      system "./slam/slam#{n}"
    end
  end
end
