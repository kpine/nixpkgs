{
  lib,
  python3,
  fetchFromGitHub,
  wrapGAppsHook4,
  installShellFiles,
  help2man,
  pandoc,

  # libs
  gobject-introspection,
  unpaper,
  djvulibre,
  libtiff,
  qpdf,
  imagemagick,
  jbig2enc,
  poppler-utils,
  ghostscript_headless,
  xdg-utils,
  sane-backends,

  # tests
  appstream,
  dejavu_fonts,
  writableTmpDirAsHomeHook,
  xvfb,
  imagemagickBig,
  tesseract,
  makeFontsConf,
  glibcLocales,
}:

let
  runtimeExecDeps = [
    unpaper
    tesseract
    djvulibre
    libtiff
    qpdf
    ghostscript_headless
    imagemagick
    jbig2enc
    poppler-utils
    xdg-utils
  ];

  testLocales = glibcLocales.override {
    allLocales = false;
    locales = [ "de_DE.UTF-8/UTF-8" ];
  };

in
python3.pkgs.buildPythonApplication (finalAttrs: {
  pname = "scantpaper";
  version = "4.0.3";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "carygravel";
    repo = "scantpaper";
    tag = "v${finalAttrs.version}";
    hash = "sha256-sn8VvMSMyWaEWhEHQrIUlW9BXGG9dnIKwgpsUkPd74s=";
  };

  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
  '';

  postPatch = ''
    # `test_qbfox_fc_match_fallback` assumes `/usr/share/fonts/truetype/`
    # exists with a handful of fonts in it. This one font is enough to make
    # the test happy.
    substituteInPlace src/scantpaper/tests/test_conftest_helpers.py \
      --replace-fail "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf" "${dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf"

    # Help, --help and the man page point at a hardcoded FHS docs path
    substituteInPlace src/scantpaper/const.py \
      --replace-fail '/usr/share/doc/C/{PROG_NAME}/documentation.html' \
          '${placeholder "out"}/share/doc/scantpaper/documentation.html'

    # GTK translates the .ui strings (menus, toolbar) with glibc's gettext,
    # but scantpaper only configures Python's gettext, so tell glibc where
    # the catalogs are as well
    substituteInPlace src/scantpaper/app.py \
      --replace-fail 'gettext.bindtextdomain(f"{PROG_NAME}")' \
                     'gettext.bindtextdomain(f"{PROG_NAME}"); locale.bindtextdomain(PROG_NAME, str(pathlib.Path(__file__).parent / "locale"))'

    # scantpaper looks up SANE's option names in sane-backends' catalog, but
    # without a directory Python only searches its own prefix
    substituteInPlace src/scantpaper/i18n.py \
      --replace-fail 'gettext.translation("sane-backends")' \
                     'gettext.translation("sane-backends", localedir="${sane-backends}/share/locale")'
  '';

  build-system = with python3.pkgs; [
    setuptools
  ];

  dependencies = with python3.pkgs; [
    img2pdf
    ocrmypdf
    pikepdf
    pillow
    pycairo
    pygobject3
    python-iso639
    sane
    tesserocr
    typing-extensions
  ];

  nativeBuildInputs = [
    wrapGAppsHook4
    gobject-introspection
    writableTmpDirAsHomeHook
    help2man
    installShellFiles
    pandoc
    python3.pkgs.polib # compiles the translation catalogs in postInstall
  ];

  disabledTestPaths = [
    # In nixpkgs, we only want to test the functionality of a package,
    # not coverage, formatting, or type checking.
    "dev/tests/test_check_test_coverage.py"
  ];

  nativeCheckInputs =
    (with python3.pkgs; [
      polib
      pytestCheckHook
      pytest-cov-stub
      pytest-mock
      pytest-xvfb
      pytest-timeout
      tomli
    ])
    ++ [
      xvfb
      imagemagickBig # "big" version needed for text rendering in tests
      appstream # Provides `appstreamcli` used by `test_appstream_validate`.
    ]
    ++ runtimeExecDeps;

  preCheck = ''
    # Some tests exercise gtk code that expects to find the relevant gsettings schemas.
    # This is a simplified version of what wrapGAppsHook4 does. There's no good way to compose
    # that with pytestCheckHook, though.
    export XDG_DATA_DIRS=$GSETTINGS_SCHEMAS_PATH:$XDG_DATA_DIRS

    # Some tests exercise comma-decimal number handling in de_DE locale
    export LOCALE_ARCHIVE=${testLocales}/lib/locale/locale-archive

    # Adresses test message `Fontconfig error: Cannot load default config file: File not found`
    export FONTCONFIG_FILE=${makeFontsConf { fontDirectories = [ dejavu_fonts ]; }}
  '';

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath runtimeExecDeps)
  ];

  postInstall = ''
    install -Dm644 \
      src/scantpaper/icons/hicolor/scalable/apps/scantpaper.svg \
      $out/share/icons/hicolor/scalable/apps/scantpaper.svg

    install -Dm444 \
      org.scantpaper.desktop \
      $out/share/applications/org.scantpaper.desktop

    install -Dm644 org.scantpaper.desktop.metainfo.xml -t $out/share/metainfo

    # Compile and install the translations
    python3 dev/compile_mo.py --src po/scantpaper \
      --out $out/${python3.sitePackages}/scantpaper/locale
    # Local documentation opened by Help
    pandoc README.md -o documentation.html
    python3 dev/strip_remote_images.py documentation.html
    install -Dm644 documentation.html screenshot.png -t $out/share/doc/scantpaper

    # Generate man page
    # Set COLUMNS to stop argparse wrapping the long nix store path in the man page
    PYTHONPATH=$out/${python3.sitePackages}:$PYTHONPATH COLUMNS=1000 help2man \
      --no-info \
      --name="a GUI to produce PDFs or DjVus from scanned documents" \
      --output=scantpaper.1 \
      "python3 -m scantpaper.app"
    installManPage scantpaper.1
  '';

  meta = {
    changelog = "https://github.com/carygravel/scantpaper/blob/${finalAttrs.src.tag}/changelog.md";
    description = "GUI to produce PDFs or DjVus from scanned documents";
    homepage = "https://github.com/carygravel/scantpaper";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ euxane ];
    platforms = lib.platforms.linux;
    mainProgram = "scantpaper";
  };
})
