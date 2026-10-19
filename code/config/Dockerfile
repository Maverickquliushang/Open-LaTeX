FROM ubuntu:22.04
RUN sed -i 's@http://archive.ubuntu.com/ubuntu@http://mirrors.ustc.edu.cn/ubuntu@g; s@http://security.ubuntu.com/ubuntu@http://mirrors.ustc.edu.cn/ubuntu@g' /etc/apt/sources.list \
    && apt-get -o Acquire::Retries=3 update \
    && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y --no-install-recommends ca-certificates \
    && sed -i 's@http://mirrors.ustc.edu.cn@https://mirrors.ustc.edu.cn@g' /etc/apt/sources.list \
    && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
       texlive-latex-extra texlive-xetex texlive-lang-chinese \
       texlive-fonts-recommended texlive-fonts-extra texlive-science \
       texlive-bibtex-extra texlive-publishers texlive-luatex texlive-plain-generic texlive-font-utils latexmk biber git curl perl fontconfig poppler-utils xindy ghostscript python3 python3-pygments tex-gyre cm-super fonts-lohit-deva fonts-noto-core fonts-linuxlibertine latex-cjk-all texlive-lang-french texlive-lang-german texlive-lang-spanish
COPY src/tools/install-modern-texlive.sh /opt/latex-build/install-modern-texlive.sh
RUN bash /opt/latex-build/install-modern-texlive.sh
WORKDIR /work
CMD ["bash"]
