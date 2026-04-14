{ pkgs }:

pkgs.stdenv.mkDerivation rec {
  pname = "claude-code";
  version = "2.1.101";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    sha256 = "sha256-wWXXLCpU0vHrm71uKrE2nV4Uo8Rqe8OweRIn7KoMFFk=";
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  unpackPhase = ''
    mkdir -p $TMPDIR/source
    tar xzf $src -C $TMPDIR/source --strip-components=1
  '';

  installPhase = ''
    mkdir -p $out/lib/claude-code $out/bin
    cp -r $TMPDIR/source/* $out/lib/claude-code/
    chmod +x $out/lib/claude-code/cli.js
    makeWrapper ${pkgs.nodejs}/bin/node $out/bin/claude \
      --add-flags "$out/lib/claude-code/cli.js"
  '';

  meta = with pkgs.lib; {
    description = "Claude Code - Anthropic's CLI for Claude";
    homepage = "https://claude.ai/code";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
