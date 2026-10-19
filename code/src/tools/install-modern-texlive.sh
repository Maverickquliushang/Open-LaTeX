#!/usr/bin/env bash
set -euo pipefail
# Optional isolated toolchain for modern tagged-PDF documents. Run in the container.
tex_root=/opt/texlive-modern
staging=/opt/latex-build/.tmp/modern-installer
mkdir -p "$staging"
if [[ ! -x "$tex_root/bin/x86_64-linux/tlmgr" ]]; then
  curl -fsSL --retry 3 --max-time 120 https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz -o "$staging/install-tl.tar.gz"
  tar -xzf "$staging/install-tl.tar.gz" -C "$staging"
  installers=("$staging"/install-tl-*/install-tl)
  perl "${installers[-1]}" --no-interaction --scheme=basic --no-doc-install --no-src-install \
    --texdir="$tex_root" --texuserdir="$tex_root/.cache/user" \
    --repository=https://mirror.ctan.org/systems/texlive/tlnet
fi
"$tex_root/bin/x86_64-linux/tlmgr" install acmart latex-lab tagpdf pdfmanagement latexmk \
  collection-latexrecommended libertine libertinus-fonts newtx inconsolata microtype hyperxmp \
  xstring environ trimspaces totpages ncctools comment makecell framed zref draftwatermark fancyhdr pbalance
