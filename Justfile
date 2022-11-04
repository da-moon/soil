# !/usr/bin/env -S just --justfile
# vi: ft=just tabstop=2 shiftwidth=2 softtabstop=2 expandtab:

set positional-arguments := true
set dotenv-load := true
set shell := ["/bin/bash", "-o", "pipefail", "-c"]

project_name := `basename $PWD`

default: format-just
    @just --choose

# ────────────────────────────────────────────────────────────────────────────────
clean: teardown-lxc clean-go

#
# ──────────────────────────────────────────────────────────────── I ──────────
#   :::::: D E P E N D E N C I E S : :  :   :    :     :        :          :
# ──────────────────────────────────────────────────────────────────────────
#
# ─── BOOTSTRAP ALL REPOSITORY REQUIREMENTS ──────────────────────────────────────
#:::::: :::::: YOU MUST RUN THIS TARGET ONCE AFTER CLONING THE REPO ::::::  ::::::

alias b := bootstrap

bootstrap: dependencies kary-comments format pre-commit go-bootstrap
    @echo bootstrap completed

# ─── ENSURE PARU INSTALL ON ARCH LINUX ──────────────────────────────────────────
install-paru:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -- pacman --version > /dev/null 2>&1 ; then
    if ! command -- paru --version > /dev/null 2>&1 ; then
    rm -rf /tmp/paru
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    pushd /tmp/paru
    for i in {1..5}; do
    makepkg -sicr --noconfirm && break || sleep 15
    done ;
    popd
    sudo rm -rf /tmp/paru
    else
    echo >&2 "*** paru installation detected. skipping build ..."
    fi
    else
    true
    fi

# ─── UPDATE AND UPGRADE PACKAGES INSTALLED THROUGH OS PACKAGE MANAGER ───────────
update-os-pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    if  command -- apt -h > /dev/null 2>&1 ; then
      echo >&2 "*** Debian based distribution detected."
      export DEBIAN_FRONTEND=noninteractive
      sudo apt-get update -qq
      sudo apt-get -f install -y
      sudo apt-get upgrade -yq
      sudo apt-get autoremove --purge -y
    elif command -- pacman --version > /dev/null 2>&1 ; then
      echo >&2 "*** Arch Linux based distribution detected."
      echo >&2 "*** updating official Arch packages with pacman."
      sudo pacman -Syyu --noconfirm || true ;
      if command -- paru --version > /dev/null 2>&1 ; then
        just install-paru
        echo >&2 "*** updating Packages installed from AUR with 'paru'."
        paru -Syyu --cleanafter --removemake --noconfirm || true ;
      else
        true
      fi
    else
      echo >&2 "*** Your Operating system is not supported."
    fi

# ─── INSTALL USING OS PACKAGE MANAGER ───────────────────────────────────────────

install-os-package pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    if  command -- apt -h > /dev/null 2>&1 ; then
      PKG_OK=$((dpkg-query -W --showformat='${Status}\n' {{ pkg }} || true )|(grep "install ok installed" || true))
      if [ "" = "$PKG_OK" ]; then
        sudo apt-get -yq install {{ pkg }}
      else
        echo >&2 "*** '{{ pkg }}' has already been installed.skipping "
      fi
    elif command -- pacman --version > /dev/null 2>&1 ; then
      if ! pacman -Qi "{{ pkg }}" > /dev/null 2>&1 ; then
        sudo pacman -Sy --needed --noconfirm {{ pkg }} || true ;
      else
        echo >&2 "*** '{{ pkg }}' has already been installed.skipping "
      fi
    else
      echo >&2 "*** Your Operating system is not supported."
      exit 1
    fi

# ─── VALIADATE AND BOOTSTRAP CORE TOOLS ─────────────────────────────────────────

alias bc := bootstrap-core

bootstrap-core: update-os-pkgs
    #!/usr/bin/env bash
    set -euo pipefail
    core_dependencies=()
    core_dependencies+=("jq")
    core_dependencies+=("parallel")
    core_dependencies+=("cmake")
    core_dependencies+=("make")
    core_dependencies+=("git")
    core_dependencies+=("fzf")
    core_dependencies+=("sshpass")
    core_dependencies+=("bash-completion")
    core_dependencies+=("pandoc")
    core_dependencies+=("pdftk")
    core_dependencies+=("texmaker")
    core_dependencies+=("ripgrep")
    core_dependencies+=("exa")
    core_dependencies+=("graphviz")
    if command -- apt -h > /dev/null 2>&1 ; then
      core_dependencies+=("python3-distutils")
      core_dependencies+=("libgconf-2-4")
      core_dependencies+=("libssl-dev")
      core_dependencies+=("golang")
      core_dependencies+=("build-essential")
      core_dependencies+=("software-properties-common")
      core_dependencies+=("poppler-utils")
      core_dependencies+=("librsvg2-bin")
      core_dependencies+=("lmodern")
      core_dependencies+=("fonts-symbola")
      core_dependencies+=("xfonts-utils ")
      core_dependencies+=("texlive-xetex")
      core_dependencies+=("texlive-fonts-recommended")
      core_dependencies+=("texlive-fonts-extra")
      core_dependencies+=("texlive-latex-extra")
    else
      true
    fi
    if command -- pacman --version > /dev/null 2>&1 ; then
      core_dependencies+=("molecule")
      core_dependencies+=("yarn")
      core_dependencies+=("npm")
      core_dependencies+=("nodejs")
      core_dependencies+=("pacman-contrib")
      core_dependencies+=("expac")
      core_dependencies+=("base-devel")
      core_dependencies+=("go")
      core_dependencies+=("poppler")
      core_dependencies+=("librsvg")
      core_dependencies+=("xorg-xfontsel")
      core_dependencies+=("texlive-most")
    else
      true
    fi
    if [ ${#core_dependencies[@]} -ne 0  ]; then
      for dep in "${core_dependencies[@]}"; do
        just install-os-package "${dep}"
      done
    else
      true
    fi

# ─── ENSURE SNAPD INSTALLATION ──────────────────────────────────────────────────

_ensure-snapd-installation:
    #!/usr/bin/env bash
    set -euo pipefail
    IFS=':' read -a paths <<< "$(printenv PATH)" ;
    [[ ! " ${paths[@]} " =~ " /snap/bin " ]] && export PATH="${PATH}:/snap/bin" || true
    [[ ! " ${paths[@]} " =~ " //usr/sbin " ]] && export PATH="${PATH}://usr/sbin" || true
    if ! command -- snap --version > /dev/null 2>&1 ; then
        if command -- apt -h > /dev/null 2>&1 ; then
            export DEBIAN_FRONTEND=noninteractive
            sudo apt-get update -qq > /dev/null 2>&1
            sudo apt-get upgrade -yqq
            sudo apt-get install -yq snapd
            sudo sysctl kernel.unprivileged_userns_clone=1 > /dev/null 2>&1
        else
            true
        fi
        if command -- pacman --version > /dev/null 2>&1 ; then
            rm -rf /tmp/snapd
            git clone https://aur.archlinux.org/snapd.git /tmp/snapd
            pushd /tmp/snapd
            for i in {1..5}; do
            makepkg -sicr --noconfirm && break || sleep 15
            done ;
            popd
            sudo rm -rf /tmp/snapd
            [ -d /var/lib/snapd/snap ] && sudo ln -sf /var/lib/snapd/snap /snap || true
        else
            true
        fi
    else
        true
    fi
    sudo systemctl enable --now snapd.socket
    sudo systemctl enable --now snapd.service
    echo "PATH=$PATH:/snap/bin" | sudo tee -a /etc/environment > /dev/null
    if ! command -- snap --version  > /dev/null 2>&1 ; then
        echo >&2 "*** snapd could not be found."
        exit 1
    else
      echo >&2 "*** ensuring successful installation of snapd ..."
      sudo snap install hello-world
      exit 0
    fi

# ─── ENSURE LXD INSTALLATION ────────────────────────────────────────────────────
bootstrap-lxd:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! sudo /snap/bin/lxd --version  > /dev/null 2>&1 ; then
        just _ensure-snapd-installation ;
        sudo snap install lxd ;
        if command -- pacman --version > /dev/null 2>&1 ; then
            just install-os-package apparmor
            sudo systemctl enable --now apparmor
            sudo systemctl restart apparmor
            sudo apparmor_parser -r /etc/apparmor.d/*snap-confine*
            sudo apparmor_parser -r /var/lib/snapd/apparmor/profiles/snap-confine*
            sudo apparmor_parser -r /var/lib/snapd/apparmor/profiles/*
            sudo systemctl restart snapd.service
            sudo snap restart lxd
        else
            true
        fi


    else
      echo >&2 "*** lxd has already been installed."
      true
    fi
    getent group lxd > /dev/null || sudo groupadd lxd
    sudo usermod --append --groups lxd "$(whoami)"
    if [[ -z $(sudo /snap/bin/lxc profile device list default 2> /dev/null) ]]; then
        echo >&2 "*** initializing lxd default profile."
        sudo /snap/bin/lxd init \
        --auto \
        --network-address="0.0.0.0" \
        --network-port="8443" \
        --trust-password="$(whoami)" \
        --storage-backend="dir" 2>/dev/null
    else
        echo >&2 "*** lxd default profile has already been initialized."
    fi
    sudo sed -i \
        -e '/^\s*#/d' \
        -e '/^\lxd*#/d' \
        -e '/^\lxc*#/d' \
        -e '/^\s*$/d' \
        /etc/bash.bashrc \
        && ( \
        echo '[ $( lxc --version  > /dev/null 2>&1) ] && eval $(lxc completion bash 2>/dev/null);' ; \
        echo '[ $( lxd --version  > /dev/null 2>&1) ] && eval $(lxd completion bash 2>/dev/null);' ;
        ) | sudo tee -a /etc/bash.bashrc > /dev/null
    sudo iptables -P FORWARD ACCEPT > /dev/null 2>&1 || true

# ─── VALIDATE AND BOOTSTRAP PYTHON INSTALLATION ─────────────────────────────────
# TODO keep track of removed packages and reinstall them after get-pip.py is done

alias bp := bootstrap-python

_remove-pip:
    #!/usr/bin/env bash
    set -euo pipefail
    if  command -- apt -h > /dev/null 2>&1 ; then
      PKG_OK=$((dpkg-query -W --showformat='${Status}\n' "python3-pip" || true )|(grep "install ok installed" || true))
      if [ "" != "$PKG_OK" ]; then
        python3 -m pip freeze --user  | xargs -r python3 -m pip uninstall --quiet --yes
        sudo apt -yqq remove --purge python3-pip
      else
        true
      fi
    elif command -- pacman --version > /dev/null 2>&1 ; then
      if  pacman -Qi "python-pip" > /dev/null 2>&1 ; then
        python3 -m pip freeze --user  | xargs -r python3 -m pip uninstall --quiet --yes
        sudo pacman -Rcns --noconfirm python-pip ;
      else
        true
      fi
    else
      true
    fi

bootstrap-python: _remove-pip
    #!/usr/bin/env bash
    set -euo pipefail
    echo >&2 "*** ensuring python3 and pip3 are installed"
    to_install=()
    to_install+=("python")
    if  command -- apt -h > /dev/null 2>&1 ; then
        to_install+=("python3")
    else
        true
    fi
    for pkg in "${to_install[@]}"; do
        echo >&2 "*** ensuring '${pkg}' is installed"
        just install-os-package "${pkg}"
    done

    if ! command -- $(which pip3) --version > /dev/null 2>&1 ; then
        echo >&2 "*** installing pip with 'get-pip.py' script"
        export PIP_USER=false
        curl -fsSl https://bootstrap.pypa.io/get-pip.py | sudo python3 -
    else
      echo >&2 "*** Python3 and Pip3 installations have been validated."
      true
    fi
    IFS=':' read -a paths <<< "$(printenv PATH)" ;
    if [[ ! " ${paths[@]} " =~ " ${HOME}/.local/bin " ]]; then
        echo "*** adding $HOME/.local/bin to user's PATH"
        [ ! -d "$HOME/.local/bin" ] && mkdir -p "$HOME/.local/bin" || true ;
        grep -qF 'local/bin' ~/.bashrc || echo 'export PATH="${PATH}:${HOME}/.local/bin"' >> ~/.bashrc
    fi

# ─── ENSURE PYTHON DEPENDENCIES ARE UPDATED ─────────────────────────────────────

alias up := update-python-pkgs

update-python-pkgs: bootstrap-python
    #!/usr/bin/env bash
    set -euo pipefail
    IFS=':' read -a paths <<< "$(printenv PATH)" ;
    [[ ! " ${paths[@]} " =~ " ${HOME}/.local/bin " ]] && export PATH="${PATH}:${HOME}/.local/bin" || true
    echo >&2 "*** ensuring all user installed python packages have been updated to latest versions"
    upgradeable=($($(which python3) -m pip list --user --format=freeze 2>/dev/null | awk 'BEGIN{FS=OFS="="}/^\-e/ {print $1}'))
    if [ ${#upgradeable[@]} -ne 0  ];then
      echo >&2 "*** upgrading outdated python dependencies : ${upgradeable[@]}"
      $(which python3) -m pip install \
        --user \
        --upgrade \
        --no-cache-dir \
        --progress-bar ascii \
        ${upgradeable[@]} 2>/dev/null ;
    else
      echo >&2 "*** all python packages are at the latest version"
    fi

# ─── INSTALL PYTHON PACKAGE ─────────────────────────────────────────────────────

# --install-scripts=/usr/local/bin \
install-python-package pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -- $(which pip3) --version > /dev/null 2>&1 ; then
      just bootstrap-python
    else
      true
    fi
    $(which python3) -m pip install \
      --user \
      --quiet \
      --no-cache-dir \
      --progress-bar ascii {{ pkg }} 2>/dev/null || true

# ─── INSTALL PYTHON VENDOR DEPENDENCIES ─────────────────────────────────────────

alias ipd := install-python-dependencies
alias python-dependencies := install-python-dependencies

install-python-dependencies: update-python-pkgs
    #!/usr/bin/env bash
    set -euo pipefail
    IFS=':' read -a paths <<< "$(printenv PATH)" ;
    [[ ! " ${paths[@]} " =~ " ${HOME}/.local/bin " ]] && export PATH="${PATH}:${HOME}/.local/bin" || true
    echo >&2 "*** ensuring all required python packages are installed"
    PYTHON_PACKAGES="\
    diagrams \
    yq \
    pre-commit \
    pylint \
    yapf \
    autoflake \
    isort \
    coverage \
    "
    installed=($($(which python3) -m pip list --user --format=freeze 2>/dev/null | awk 'BEGIN{FS=OFS="="}/^\-e/ {print $1}'))
    IFS=' ' read -a PYTHON_PACKAGES <<< "$PYTHON_PACKAGES" ;
    to_install=()
    if [ ${#PYTHON_PACKAGES[@]} -ne 0  ];then
      intersection=($(comm -12 <(for X in "${PYTHON_PACKAGES[@]}"; do echo "${X}"; done|sort)  <(for X in "${installed[@]}"; do echo "${X}"; done|sort)))
      to_install=($(echo ${intersection[*]} ${PYTHON_PACKAGES[*]} | sed 's/ /\n/g' | sort -n | uniq -u | paste -sd " " - ))
    else
      true
    fi
    if [ ${#to_install[@]} -ne 0  ];then
      for dep in "${to_install[@]}"; do
        echo >&2 "*** ensuring python dependencies ${dep} has been installed"
        just install-python-package "${dep}"
      done
    else
      echo >&2 "*** all required python dependencies have been satisfied"
    fi

# ─── VALIDATE AND BOOTSTRAP NODEJS INSTALLATION ─────────────────────────────────

alias bn := bootstrap-nodejs

bootstrap-nodejs:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -- $(which node) --version > /dev/null 2>&1 ; then
      if  command -- pacman -h > /dev/null 2>&1 ; then
        sudo pacman -Sy --needed --noconfirm "nodejs"
      else
        true ;
      fi
    else
      true
    fi
    if ! command -- $(which yarn) --version > /dev/null 2>&1 ; then
      if  command -- pacman -h > /dev/null 2>&1 ; then
        sudo pacman -Sy --needed --noconfirm "yarn"
      else
        true
      fi
    else
      true
    fi
    if ! command -- $(which node) --version > /dev/null 2>&1 ; then
      echo >&2 "*** nodejs is required."
      exit 1
    else
      echo >&2 "*** Node.JS installation has been validated."
    fi
    if ! command -- $(which npm) --version > /dev/null 2>&1 ; then
      echo >&2 "*** npm is required."
      exit 1
    else
      echo >&2 "*** npm installation has been validated."
    fi

    if ! command -- $(which yarn) --version > /dev/null 2>&1 ; then
      echo >&2 "*** yarn not found. installing"
      sudo npm install -g yarn
      exit 1
    else
      echo >&2 "*** yarn installation has been validated."
    fi

# ─── INSTALL A NODEJS PACKAGE WITH YARN ─────────────────────────────────────────

install-nodejs-package pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -- $(which yarn) --version > /dev/null 2>&1 ; then
      just bootstrap-nodejs
    else
      true
    fi
    sudo $(which yarn) global add --latest --prefix /usr/local {{ pkg }}

# ─── ENSURE NODEJS PACKAGES ARE UPDATED ─────────────────────────────────────────

alias un := update-nodejs

update-nodejs: bootstrap-nodejs
    #!/usr/bin/env bash
    set -euo pipefail
    echo >&2 "*** ensuring all globally installed yarn packages have been updated to latest versions"
    if [ -r $(sudo $(which yarn) global dir 2>/dev/null )/package.json ] ; then
      pushd $(sudo $(which yarn) global dir 2>/dev/null  ) > /dev/null 2>&1
      upgradeable=($(($(which yarn) outdated --json 2>/dev/null || true) \
      | (jq -r '. | select (.type == "table").data.body[]|.[]' || true ) \
      | (/bin/grep -Pv '^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+)?$' || true) \
      | (/bin/grep -Pv '^http(s)*:\/\/|^dependencies$' || true) \
      )) ;
      popd > /dev/null 2>&1
      if [ ${#upgradeable[@]} -ne 0  ];then
        for pkg in "${upgradeable[@]}"; do
        echo >&2 "*** upgrading outdated nodejs package ${pkg}"
        just install-nodejs-package "${pkg}"
        done
      else
        echo >&2 "*** all nodejs packages are at the latest version"
      fi
    else
      true
    fi

# ─── INSTALL ALL NODEJS VENDOR DEPENDENCIES ─────────────────────────────────────

alias ind := install-nodejs-dependencies
alias nodejs-dependencies := install-nodejs-dependencies

install-nodejs-dependencies: update-nodejs
    #!/usr/bin/env bash
    set -euo pipefail
    echo >&2 "*** ensuring all required nodejs packages are installed"
    NODE_PACKAGES="\
    markdown-magic \
    remark \
    remark-cli \
    remark-stringify \
    remark-frontmatter \
    wcwidth \
    prettier \
    bash-language-server \
    dockerfile-language-server-nodejs \
    standard-readme-spec \
    "
    IFS=' ' read -a NODE_PACKAGES <<< "$NODE_PACKAGES" ;
    installed=()
    if command -- jq -h > /dev/null 2>&1 && [ -r $(sudo $(which yarn) global dir 2>/dev/null )/package.json ] ; then
      while IFS='' read -r line; do
        installed+=("$line");
      done < <( (cat $(sudo $(which yarn) global dir 2>/dev/null )/package.json || true ) | (jq -r '.dependencies|keys[]' ||true ))
    fi
    intersection=($(comm -12 <(for X in "${NODE_PACKAGES[@]}"; do echo "${X}"; done|sort)  <(for X in "${installed[@]}"; do echo "${X}"; done|sort)))
    to_install=($(echo ${intersection[*]} ${NODE_PACKAGES[*]} | sed 's/ /\n/g' | sort -n | uniq -u | paste -sd " " - ))
    if [ ${#to_install[@]} -ne 0  ];then
      for dep in "${to_install[@]}"; do
        echo >&2 "*** installing unmet NodeJS dependencies ${dep}"
        just install-nodejs-package "${dep}"
      done
    else
      echo >&2 "*** all required NodeJS dependencies have been satisfied"
    fi

# ─── VALIDATE RUST INSTALLATION ─────────────────────────────────────────────────

alias br := bootstrap-rust

bootstrap-rust:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -- rustup -h > /dev/null 2>&1 ; then
      echo >&2 "*** rustup is required."
      exit 1
    else
      true
    fi
    if ! command -- cargo -h > /dev/null 2>&1 ; then
      echo >&2 "*** cargo is required."
      exit 1
    else
      true
    fi

# ─── UPDATE RUST TOOLCHAINS AND INSTALLED PACKAGES ──────────────────────────────

alias ur := update-rust

update-rust: bootstrap-rust
    #!/usr/bin/env bash
    set -xeuo pipefail
    echo >&2 "*** ensuring rustup has been updated."
    rustup update >/dev/null 2>&1
    echo >&2 "*** ensuring rust nightly and stable toolchains are installed."
    rustup toolchain install nightly stable >/dev/null 2>&1
    rustup default stable
    if ! command -- cargo-install-update -h >/dev/null 2>&1; then
      just install-rust-package cargo-update
    else
      true
    fi
    echo >&2 "*** ensuring all installed rust-based command line utilities, compiled with stable toolchain, have been updated to latest versions"
    cargo-install-update install-update --all || true
    rustup default nightly
    echo >&2 "*** ensuring all installed rust-based command line utilities, compiled with nightly toolchain, have been updated to latest versions"
    cargo-install-update install-update --all || true
    rustup default stable

# ─── BUILDS AND INSTALLS RUST PACKAGE FROM SOURCE ───────────────────────────────
install-rust-package name:
    #!/usr/bin/env bash
    set -xeuo pipefail
    if  ! command -- cargo --version > /dev/null 2>&1 ; then
        echo >&2 "*** cannot install '{{ name }}' as rust toolchain has not been installed"
        exit 1
    else
        true
    fi

    installed_packages=($(cargo install --list | awk '/:/{print $1}'))
    mkdir -p {{ justfile_directory() }}/tmp
    rm -rf {{ justfile_directory() }}/tmp/rust-fail.txt
    if [[ ! " ${installed_packages[@]} " =~ " {{ name }} " ]]; then
        echo >&2 "***  building and installing '{{ name }}' from source ..."
        cargo install --all-features '{{ name }}' || (echo '{{ name }}' >> {{ justfile_directory() }}/tmp/rust-fail.txt ; true)
    else
        echo >&2 "***  '{{ name }}' installation detected. Skipping build ..."
    fi

# ─── INSTALL RUST VENDOR DEPENDENCIES ───────────────────────────────────────────

alias ird := install-rust-dependencies
alias rust-dependencies := install-rust-dependencies

install-rust-dependencies: update-rust
    #!/usr/bin/env bash
    set -euo pipefail
    echo >&2 "*** ensuring all required rust packages are installed"
    RUST_PACKAGES="\
      jsonfmt \
      prose \
      bat \
      convco \
      skim \
    "
    IFS=' ' read -a RUST_PACKAGES <<< "$RUST_PACKAGES" ;
    if [ ${#RUST_PACKAGES[@]} -ne 0  ];then
      for pkg in "${RUST_PACKAGES[@]}"; do
        just install-rust-package "${pkg}"
      done
    fi

# ─── INSTALLING HASHICORP TOOLS ─────────────────────────────────────────────────

alias ihd := install-hashicorp-dependencies
alias hashicorp-dependencies := install-hashicorp-dependencies

install-hashicorp-dependencies:
    #!/usr/bin/env bash
    set -euo pipefail
    just install-rust-package hcdl
    IFS=':' read -a paths <<< "$(printenv PATH)" ;
    [[ ! " ${paths[@]} " =~ " ${HOME}/.local/bin " ]] && export PATH="${PATH}:${HOME}/.local/bin" || true
    [[ ! " ${paths[@]} " =~ " ${HOME}/.cargo/bin " ]] && export PATH="${PATH}:${HOME}/.cargo/bin" || true
    HASHICORP_TOOLS="\
    consul \
    "
    IFS=' ' read -a HASHICORP_TOOLS <<< "$HASHICORP_TOOLS" ;
    if [ ${#HASHICORP_TOOLS[@]} -ne 0  ];then
        for pkg in "${HASHICORP_TOOLS[@]}"; do
            if  ! command -- "${pkg}" "--version"  > /dev/null 2>&1  ; then
                curl -sL "https://api.github.com/repos/hashicorp/${pkg}/releases/latest" \
                | jq -r '.name' \
                | sed 's/v//g' \
                | xargs -r \
                hcdl "${pkg}" --build
            else
                echo >&2 "***  ${pkg} installation detected. skipping ..."
            fi
        done
    else
        true
    fi

# ─── INSTALLING DELTA ───────────────────────────────────────────────────────────

alias igd := install-git-delta

install-git-delta:
    #!/usr/bin/env bash
    set -euo pipefail
    just install-rust-package git-delta
    git config --global pager.diff delta
    git config --global pager.log delta
    git config --global pager.reflog delta
    git config --global pager.show delta
    git config --global interactive.difffilter "delta --color-only --features=interactive"
    git config --global delta.features "decorations"
    git config --global delta.interactive.keep-plus-minus-markers "false"
    git config --global delta.decorations.commit-decoration-style "blue ol"
    git config --global delta.decorations.commit-style "raw"
    git config --global delta.decorations.file-style "omit"
    git config --global delta.decorations.hunk-header-decoration-style "blue box"
    git config --global delta.decorations.hunk-header-file-style "red"
    git config --global delta.decorations.hunk-header-line-number-style "#067a00"
    git config --global delta.decorations.hunk-header-style "file line-number syntax"

# ─── BUILD LATEST NEOVIM FROM SOURCE ────────────────────────────────────────────

_remove-neovim:
    #!/usr/bin/env bash
    set -euo pipefail
    echo >&2 "*** ensuring all existing neovim installations are removed."
    if command -- nvim --version > /dev/null 2>&1 ; then
      command -- apt -h > /dev/null 2>&1 && ( sudo apt -yqq remove --purge neovim python3-neovim > /dev/null 2>&1 || true ) || true
      command -- apt -h > /dev/null 2>&1 && ( sudo apt -yqq remove --purge python-neovim > /dev/null 2>&1 || true ) || true
      command -- pacman --version > /dev/null 2>&1 && ( sudo pacman -Rcns --noconfirm neovim python-pynvim > /dev/null 2>&1 || true ) || true
      command -- snap --version > /dev/null 2>&1 && ( sudo snap remove nvim > /dev/null 2>&1 || true ) || true
      echo >&2 "*** all existing neovim installations have been removed."
    fi

build-neovim: _remove-neovim
    #!/usr/bin/env bash
    set -euo pipefail
    if command -- nvim --version > /dev/null 2>&1 ; then
      echo >&2 "*** neovim installation found, skipping build from source."
      exit 0
    else
      echo >&2 "*** downloading dependencies to build Neovim from source."
      build_dependencies=(
        "cmake"
        "curl"
        "unzip"
      )
      if command -- apt -h > /dev/null 2>&1 ; then
        build_dependencies+=("ninja-build")
        build_dependencies+=("gettext")
        build_dependencies+=("libtool")
        build_dependencies+=("libtool-bin")
        build_dependencies+=("autoconf")
        build_dependencies+=("automake")
        build_dependencies+=("g++")
        build_dependencies+=("pkg-config")
      else
        true
      fi
      if command -- pacman --version > /dev/null 2>&1 ; then
        build_dependencies+=("base-devel")
        build_dependencies+=("ninja")
        build_dependencies+=("tree-sitter")
      else
        true
      fi
      if [ ${#build_dependencies[@]} -ne 0  ];then
        for pkg in "${build_dependencies[@]}"; do
          just install-os-package "${pkg}"
        done
      else
        echo >&2 "*** no build dependencies found, skipping build."
        exit 0
      fi
      echo >&2 "*** building neovim from source."
      build_dir="/tmp/neovim"
      sudo rm -rf "${build_dir}"
      mkdir -p "${build_dir}"
      git clone https://github.com/neovim/neovim.git "${build_dir}" ;
      pushd "${build_dir}" > /dev/null 2>&1
      make -j`nproc` CMAKE_BUILD_TYPE=RelWithDebInfo ;
      CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=/usr/local" sudo make -j`nproc` install ;
      popd > /dev/null 2>&1
      sudo rm -rf "${build_dir}"
    fi

# ─── INSTALL SPACEVIM ───────────────────────────────────────────────────────────

alias is := install-spacevim

install-spacevim:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -- $(which pip3) --version > /dev/null 2>&1 ; then
      echo >&2 "*** ensuring all existing neovim related python packages are removed."
      $(which python3) -m pip uninstall -yq neovim pynvim msgpack greenlet >/dev/null 2>&1  || true
    else
      echo >&2 "*** skipping Python package clean-ups as Python3 and Pip3 were not installed."
      true
    fi
    if command -- $(which yarn) --version > /dev/null 2>&1 ; then
      sudo $(which yarn) global remove neovim  >/dev/null 2>&1  || true
    else
      echo >&2 "*** skipping NodeJs package clean-ups as Yarn was not installed."
    fi
    echo >&2 "*** cleaning up neovim leftover directories."
    just install-python-package neovim
    sudo npm -g install neovim
    rm -rf \
        ~/.SpaceVim \
        ~/.vim* \
        ~/.config/*vim* \
        ~/.cache/*vim* \
        ~/.cache/neosnippet \
        ~/.local/share/*vim*
    curl -sLf https://spacevim.org/install.sh | bash
    sed -i.bak 's/call dein#add/"call dein#add/g' "$HOME/.SpaceVim/autoload/SpaceVim/plugins.vim"
    mkdir -p "$HOME/.local/share/nvim/shada"
    sudo npm -g install neovim
    python3 -m pip install --user notedown
    nvim --headless \
    -c "call dein#direct_install('deoplete-plugins/deoplete-go', { 'build': 'make' })" \
    -c "call dein#direct_install('iamcco/markdown-preview.nvim', {'on_ft': ['markdown', 'pandoc.markdown', 'rmd'],'build': 'yarn --cwd app --frozen-lockfile install' })" \
    -c "call dein#direct_install('lymslive/vimloo', { 'merged': '0' })" \
    -c "call dein#direct_install('lymslive/vnote', { 'depends': 'vimloo' })" \
    -c "qall"
    if [ -r "$HOME/.cache/vimfiles/repos/github.com/zchee/deoplete-go/rplugin/python3/deoplete/sources/deoplete_go.py" ]; then
    sed -i \
        -e '/def gather_candidates/a\        return []' \
        -e '/def get_complete_result/a\        return []' \
        -e '/def find_gocode_binary/a\        return "/bin/true"' \
    "$HOME/.cache/vimfiles/repos/github.com/zchee/deoplete-go/rplugin/python3/deoplete/sources/deoplete_go.py"
    echo 'finish' >  "$HOME/.cache/vimfiles/repos/github.com/zchee/deoplete-go/plugin/deoplete-go.vim"
    fi
    mv "$HOME/.SpaceVim/autoload/SpaceVim/plugins.vim.bak" "$HOME/.SpaceVim/autoload/SpaceVim/plugins.vim"
    nvim --headless \
      -c "call dein#install()" \
      -c "call dein#update()" \
      -c "call dein#remote_plugins()" \
      -c "call dein#recache_runtimepath()" \
      -c "UpdateRemotePlugins" \
      -c "qall" ; \
    [ -d "${HOME}/.SpaceVim/bundle/vimproc.vim" ] && make -C ~/.SpaceVim/bundle/vimproc.vim ;
    if command -- go version > /dev/null 2>&1 ; then
        nvim --headless \
        -c "GoInstallBinaries" \
        -c "GoUpdateBinaries" \
        -c "qall" || true
    fi

# ─── RUN ALL AVAILABLE DEPENDENCY RELATED TARGETS ───────────────────────────────

alias d := dependencies

dependencies: bootstrap-core install-nodejs-dependencies install-python-dependencies install-rust-dependencies
    #!/usr/bin/env bash
    set -euo pipefail
    just install-git-delta
    just install-hashicorp-dependencies
    just build-neovim
    just install-spacevim

# ────────────────────────────────────────────────────────────────────────────────

alias gb := go-bootstrap

go-bootstrap:
    go env -w "GO111MODULE=on"
    go env -w "CGO_ENABLED=0"
    go env -w "CGO_LDFLAGS=-s -w -extldflags '-static'"
    go clean -modcache
    go mod tidy
    go generate -tags tools tools.go

# ────────────────────────────────────────────────────────────────────────────────

alias kc := kary-comments

kary-comments:
    #!/usr/bin/env bash
    set -euo pipefail
    sed -i.bak \
    -e "/case 'yaml':.*/a case 'terraform':" \
    -e "/case 'yaml':.*/a case 'dockerfile':" \
    -e "/case 'yaml':.*/a case 'just':" \
    -e "/case 'yaml':.*/a case 'hcl':" \
    ~/.vscode*/extensions/karyfoundation.comment*/dictionary.js > /dev/null 2>&1 || true

# ────────────────────────────────────────────────────────────────────────────────

alias vt := vscode-tasks

vscode-tasks:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -- jq -h > /dev/null 2>&1 ; then
      IFS=' ' read -a TASKS <<< "$(just --summary --color never -f "{{ justfile() }}" 2>/dev/null)"
      if [ ${#TASKS[@]} -ne 0  ];then
        mkdir -p "{{ justfile_directory() }}/.vscode"
        json=$(jq -n --arg version "2.0.0" '{"version":$version,"tasks":[]}')
        for task in "${TASKS[@]}";do
          taskjson=$(jq -n --arg task "${task}" --arg command "just ${task}" '[{"type": "shell","label": $task,  "command": $command }]')
          json=$(echo "${json}" | jq ".tasks += ${taskjson}")
        done
        echo "${json}" | jq -r '.' > "{{ justfile_directory() }}/.vscode/tasks.json"
      fi
    fi
    just format-just

# ─── FORMAT ─────────────────────────────────────────────────────────────────────

alias f := format
alias fmt := format

format: format-json format-just format-go
    @echo format completed

# ────────────────────────────────────────────────────────────────────────────────

alias fj := format-json
alias json-fmt := format-json

format-json:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -- jsonfmt -h > /dev/null 2>&1 ; then
      while read file;do
        echo "*** formatting $file"
        jsonfmt "$file" || true
        echo '' >> "$file"
      done < <(find -type f -not -path '*/\.git/*' -name '*.json')
    fi

# ────────────────────────────────────────────────────────────────────────────────

alias go-fmt := format-go
alias gofmt := format-go
alias fg := format-go

format-go:
    #!/usr/bin/env bash
    set -euo pipefail
    gofmt -l -w {{ justfile_directory() }}

# ────────────────────────────────────────────────────────────────────────────────
format-just:
    #!/usr/bin/env bash
    set -euo pipefail
    just --unstable --fmt 2>/dev/null

# ─── GO ─────────────────────────────────────────────────────────────────────────
build:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{ justfile_directory() }}/bin"
    mage build

clean-go:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo pkill -SIGTERM soil || true 
    sudo rm -rf "{{ justfile_directory() }}/tmp"
    mkdir -p "{{ justfile_directory() }}/tmp"

# ────────────────────────────────────────────────────────────────────────────────

# run: build clean-go
run:
    #!/usr/bin/env bash
    set -euo pipefail
    COMMAND="sudo"
    COMMAND+=" {{ justfile_directory() }}/bin/soil"
    COMMAND+=" agent"
    configs=($(find "{{ justfile_directory() }}/fixture/soil" -type f -name '*.hcl'))
    for config in "${configs[@]}"; do
      COMMAND+=" --config=${config}"
    done
    $COMMAND > {{ justfile_directory() }}/tmp/soil.log 2>&1 &

# ────────────────────────────────────────────────────────────────────────────────

lint: golangci-lint

golangci-lint: format-go
    #!/usr/bin/env bash
    set -euox pipefail
    golangci-lint run \
    --print-issued-lines=false \
    --exclude-use-default=false \
    --config "{{ justfile_directory() }}/.golangci.yml"

# ─── GIT ────────────────────────────────────────────────────────────────────────
# Variables

MASTER_BRANCH_NAME := 'master'
MAJOR_VERSION := `[[ ! -z $(git tag -l | head -n 1 ) ]] && convco version --major 2>/dev/null || echo '0.0.1'`
MINOR_VERSION := `[[ ! -z $(git tag -l | head -n 1 ) ]] && convco version --minor 2>/dev/null || echo '0.0.1'`
PATCH_VERSION := `[[ ! -z $(git tag -l | head -n 1 ) ]] && convco version --patch 2>/dev/null || echo '0.0.1'`

# ────────────────────────────────────────────────────────────────────────────────

alias pc := pre-commit

pre-commit:
    #!/usr/bin/env bash
    set -xeuo pipefail
    IFS=':' read -a paths <<< "$(printenv PATH)" ;
    [[ ! " ${paths[@]} " =~ " ${HOME}/.local/bin " ]] && export PATH="${PATH}:${HOME}/.local/bin" || true
    pushd "{{ justfile_directory() }}" > /dev/null 2>&1
    if [ -r .pre-commit-config.yaml ]; then
      git add ".pre-commit-config.yaml"
      pre-commit install > /dev/null 2>&1
      pre-commit install-hooks
      pre-commit
    fi
    popd > /dev/null 2>&1

# ────────────────────────────────────────────────────────────────────────────────

alias gf := git-fetch

git-fetch:
    #!/usr/bin/env bash
    set -euo pipefail
    pushd "{{ justfile_directory() }}" > /dev/null 2>&1
    git fetch -p ;
    to_remove=($(git branch -vv | awk '/: gone]/ {print $1}'))
    if [ ${#to_remove[@]} -ne 0  ]; then
      for branch in "${to_remove[@]}"; do
        git branch -D "$branch";
      done
    fi
    popd > /dev/null 2>&1

# ────────────────────────────────────────────────────────────────────────────────

alias c := commit

commit: format-just pre-commit git-fetch
    #!/usr/bin/env bash
    set -euo pipefail
    pushd "{{ justfile_directory() }}" > /dev/null 2>&1
    if command -- convco -h > /dev/null 2>&1 ; then
      convco commit
    else
      git commit
    fi
    popd > /dev/null 2>&1

# ────────────────────────────────────────────────────────────────────────────────

alias mar := major-release

major-release: format-just git-fetch
    #!/usr/bin/env bash
    set -euo pipefail
    pushd "{{ justfile_directory() }}" > /dev/null 2>&1
    git checkout "{{ MASTER_BRANCH_NAME }}"
    git pull
    git tag -a "v{{ MAJOR_VERSION }}" -m 'major release {{ MAJOR_VERSION }}'
    git push origin --tags
    if command -- convco -h > /dev/null 2>&1 ; then
      convco changelog > CHANGELOG.md
      git add CHANGELOG.md
      if command -- pre-commit -h > /dev/null 2>&1 ; then
        pre-commit || true
        git add CHANGELOG.md
      fi
      git commit -m 'docs(changelog): updated changelog for v{{ MAJOR_VERSION }}'
      git push
    fi
    just git-fetch
    popd > /dev/null 2>&1

# ────────────────────────────────────────────────────────────────────────────────

alias mir := minor-release

minor-release: format-just git-fetch
    #!/usr/bin/env bash
    set -euo pipefail
    pushd "{{ justfile_directory() }}" > /dev/null 2>&1
    git checkout "{{ MASTER_BRANCH_NAME }}"
    git pull
    git tag -a "v{{ MINOR_VERSION }}" -m 'minor release {{ MINOR_VERSION }}'
    git push origin --tags
    if command -- convco -h > /dev/null 2>&1 ; then
      convco changelog > CHANGELOG.md
      git add CHANGELOG.md
      if command -- pre-commit -h > /dev/null 2>&1 ; then
        pre-commit || true
        git add CHANGELOG.md
      fi
      git commit -m 'docs(changelog): updated changelog for v{{ MINOR_VERSION }}'
      git push
      just git-fetch
    fi
    popd > /dev/null 2>&1

# ────────────────────────────────────────────────────────────────────────────────

alias pr := patch-release

patch-release: format-just git-fetch
    #!/usr/bin/env bash
    set -euo pipefail
    pushd "{{ justfile_directory() }}" > /dev/null 2>&1
    git checkout "{{ MASTER_BRANCH_NAME }}"
    git pull
    git tag -a "v{{ PATCH_VERSION }}" -m 'patch release {{ PATCH_VERSION }}'
    git push origin --tags
    if command -- convco -h > /dev/null 2>&1 ; then
      convco changelog > CHANGELOG.md
      git add CHANGELOG.md
      if command -- pre-commit -h > /dev/null 2>&1 ; then
        pre-commit || true
        git add CHANGELOG.md
      fi
      git commit -m 'docs(changelog): updated changelog for v{{ MINOR_VERSION }}'
      git push
    fi
    just git-fetch
    popd > /dev/null 2>&1

alias gc := generate-changelog

generate-changelog: format-just
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf "{{ justfile_directory() }}/tmp"
    mkdir -p "{{ justfile_directory() }}/tmp"
    convco changelog > "{{ justfile_directory() }}/tmp/$(basename {{ justfile_directory() }})-changelog-$(date -u +%Y-%m-%d).md"
    if command -- pandoc -h >/dev/null 2>&1; then
    pandoc \
      --from markdown \
      --pdf-engine=xelatex \
      -o  "{{ justfile_directory() }}/tmp/$(basename {{ justfile_directory() }})-changelog-$(date -u +%Y-%m-%d).pdf" \
      "{{ justfile_directory() }}/tmp/$(basename {{ justfile_directory() }})-changelog-$(date -u +%Y-%m-%d).md"
    fi
    if [ -d /workspace ]; then
      cp -f "{{ justfile_directory() }}/tmp/$(basename {{ justfile_directory() }})-changelog-$(date -u +%Y-%m-%d).pdf" /workspace/
      cp -f "{{ justfile_directory() }}/tmp/$(basename {{ justfile_directory() }})-changelog-$(date -u +%Y-%m-%d).md" /workspace/
    fi

snapshot: format-just git-fetch
    #!/usr/bin/env bash
    set -euo pipefail
    sync
    snapshot_dir="{{ justfile_directory() }}/tmp/snapshots"
    mkdir -p "${snapshot_dir}"
    time="$(date +'%Y-%m-%d-%H-%M')"
    path="${snapshot_dir}/${time}.tar.gz"
    tmp="$(mktemp -d)"
    tar -C {{ justfile_directory() }} -cpzf "$tmp/${time}.tar.gz" .
    mv "$tmp/${time}.tar.gz" "$path"
    rm -r "$tmp"
    echo >&2 "*** snapshot created at ${path}"

# ─── PRODUCTION DOCKER IMAGE BUILD ──────────────────────────────────────────────

alias bdi := build-docker-image

build-docker-image:
    #!/usr/bin/env bash
    set -euo pipefail
    bash contrib/docker/alpine/build.sh

#
# ────────────────────────────────────────────────────────────── I ──────────
#   :::::: L X C   H E L P E R S : :  :   :    :     :        :          :
# ────────────────────────────────────────────────────────────────────────
#
# ─── ENSURE PROJECT SPECIFIC SSH KEYS ARE PRESENT ───────────────────────────────

alias sk := ssh-key

ssh-key:
    #!/usr/bin/env bash
    set -euo pipefail
    echo >&2 "*** ensuring a set of ssh keys for '{{ project_name }}' project has been generated on host" ;
    [ ! -r ~/.ssh/id_rsa ] \
    && (
        echo >&2 "*** generating default ssh key-pair'" ;
        ssh-keygen \
        -b 4096 \
        -t rsa \
        -f ~/.ssh/id_rsa -q -N "" ;
        ) \
    || true ;

# ─── PULL TEMPLATE RENDERER TOOL ────────────────────────────────────────────────

_docker-pull-renderer:
    #!/usr/bin/env bash
    set -euo pipefail
    docker pull hairyhenderson/gomplate > /dev/null 2>&1

# ─── RENDER TEMPLATED LXD PROFILE ───────────────────────────────────────────────

alias lrp := lxc-render-profile

lxc-render-profile: _docker-pull-renderer
    #!/usr/bin/env bash
    set -euo pipefail
    docker run \
        --env "USER=$USER" \
        --env "PWD={{ justfile_directory() }}" \
        --env "SHIFT_FS=$(modinfo shiftfs > /dev/null 2>&1 && echo true || echo false)" \
        --env "PASSWD=$(openssl passwd -1 -salt SaltSalt '$USER' )" \
        --env "profile={{ project_name }}" \
        -w "/workspace" \
        -v "$PWD:/workspace" \
        -v "${HOME}/.ssh/id_rsa.pub:/id_rsa.pub:ro" \
        --rm -it hairyhenderson/gomplate \
        --file /workspace/contrib/lxd/debian.yml.tmpl

# ─── UPDATE LOCAL MACHINE SSH CONFIG ────────────────────────────────────────────

alias sc := ssh-config

ssh-config:
    #!/usr/bin/env bash
    set -euo pipefail
    readarray -t containers < <(lxc list --format json 2>/dev/null | jq -c '
    [
        .[]
        | select(
            (
                (.status=="Running")
                and (.profiles | contains(["{{ project_name }}"]))
            )
        ) | {
        name:.name,
        addr:.state.network.eth0.addresses[]|select(.family=="inet").address
        }
    ]
    ' | jq -r '.[] | @base64')
    for container in "${containers[@]}"; do
        _jq() {
            echo "${container}" | base64 --decode | jq -r "${1}"
        }
        name="$(_jq '.name')"
        addr="$(_jq '.addr')"
        echo >&2 "*** removing existing '${name}' config from ~/.ssh/config"
        [ -r $HOME/.ssh/config ] \
            && sed -n -i \
                -e "/Host ${name}/,/UserKnownHostsFile/!{//!p}" \
            ~/.ssh/config \
        || true
        echo >&2 "*** storing ssh config for '${name}' in ~/.ssh/config"
        echo '' >> ~/.ssh/config
        cat << CONFIG | tee -a ~/.ssh/config > /dev/null
    Host ${name}
      user $(whoami)
      HostName ${addr}
      RequestTTY yes
      IdentityFile ~/.ssh/id_rsa
      IdentitiesOnly yes
      StrictHostKeyChecking no
      CheckHostIP no
      MACs hmac-sha2-256
      UserKnownHostsFile=/dev/null
    CONFIG
        sed -i -e "/^\s*$/d" ~/.ssh/config
        echo '' >> ~/.ssh/config
    done

# ─── UPDATE LOCAL MACHINE HOSTS ─────────────────────────────────────────────────

alias hc := hosts-config

hosts-config:
    #!/usr/bin/env bash
    set -euo pipefail
    echo >&2 "*** removing existing .local domains from /etc/hosts"
    [ -r /etc/hosts ] && sudo sed -i "/\.local/d" /etc/hosts || true
    readarray -t containers < <(lxc list --format json 2>/dev/null | jq -c '
    [
        .[]
        | select(
            (
                (.status=="Running")
                and (.profiles | contains(["{{ project_name }}"]))
            )
        ) | {
        name:.name,
        addr:.state.network.eth0.addresses[]|select(.family=="inet").address
        }
    ]
    ' | jq -r '.[] | @base64')
    for container in "${containers[@]}"; do
        _jq() {
            echo "${container}" | base64 --decode | jq -r "${1}"
        }
        name="$(_jq '.name')"
        addr="$(_jq '.addr')"
        echo >&2 "*** updating /etc/hosts for '${name}'"
        echo "$addr  ${name}.local" | sudo tee -a /etc/hosts
        if command -- hostname -h >/dev/null 2>&1; then
          echo "$addr  ${name}.$(hostname).local" | sudo tee -a /etc/hosts
        else
          true ;
        fi
    done

# ─── UPDATE LXC PROFILE ─────────────────────────────────────────────────────────

alias lp := lxc-profile

lxc-profile *path: _docker-pull-renderer ssh-key
    #!/usr/bin/env bash
    set -euo pipefail
    [ -z '{{ path }}' ] && path='contrib/lxd/debian.yml.tmpl' || path='{{ path }}'

    echo >&2 "*** ensuring '{{ project_name }}-debian' LXD profile exists" ;
    ! lxc profile show "{{ project_name }}-debian" > /dev/null 2>&1 \
    && lxc profile create "{{ project_name }}-debian" 2>/dev/null
    echo >&2 "*** ensuring '{{ project_name }}-debian' LXD profile matches our requirements" ;
    docker run \
        --env "USER=$USER" \
        --env "PWD={{ justfile_directory() }}" \
        --env "SHIFT_FS=$(modinfo shiftfs > /dev/null 2>&1 && echo true || echo false)" \
        --env "PASSWD=$(openssl passwd -1 -salt SaltSalt '$USER' )" \
        --env "profile={{ project_name }}" \
        -w "/workspace" \
        -v "$PWD:/workspace" \
        -v "${HOME}/.ssh/id_rsa.pub:/id_rsa.pub:ro" \
        --rm -i hairyhenderson/gomplate \
        --file "/workspace/${path}" \
    | lxc profile edit "{{ project_name }}-debian" 2>/dev/null

# ─── START A CONTAINER ──────────────────────────────────────────────────────────

lxc-launch name:
    #!/usr/bin/env bash
    set -xeuo pipefail
    echo >&2 "*** ensuring '{{ name }}' LXD container has started" ;
    lxc launch \
    --profile="default" \
    --profile="{{ project_name }}-debian" \
    images:debian/bullseye/cloud \
    "{{ name }}" 2>/dev/null \
    || lxc start "{{ name }}" 2>/dev/null || true
    just lxc-wait "{{ name }}"
    just ssh-config
    just hosts-config
    echo >&2 "*** testing SSH access to '{{ name }}'.  ... "
    export LC_ALL=C ;
    ssh "{{ name }}" -- echo '*** $(whoami)@$(hostname) can be accessed through ssh...'

# ─── WAIT UNTIL PROVISIONING HAS BEEN COMPLETED ─────────────────────────────────
lxc-wait name:
    #!/usr/bin/env bash
    set -euo pipefail
    echo >&2 "*** waiting for cloud-init to finish initial provisioning of '{{ name }}' LXD container" ;
    lxc exec "{{ name }}" -- cloud-init status --wait

# ─── TAIL CLOUD INIT LOGS ───────────────────────────────────────────────────────

alias tail := lxc-tail-logs
alias logs := lxc-tail-logs

lxc-tail-logs *name:
    #!/usr/bin/env bash
    set -euo pipefail
    name='{{ project_name }}'
    [ ! -z '{{ name }}' ] && name='{{ name }}' || true
    lxc exec "${name}" -- tail -f /var/log/cloud-init-output.log

# ─── QUICK CREATION OF A SINGLE SANDBOX NODE ────────────────────────────────────

alias sandbox := lxc-sandbox

lxc-sandbox *name: lxc-profile
    #!/usr/bin/env bash
    set -euo pipefail
    name='{{ project_name }}'
    [ ! -z '{{ name }}' ] && name='{{ name }}' || true
    just lxc-launch "${name}"

devcontainer *name:
    #!/usr/bin/env bash
    set -euo pipefail
    name='{{ project_name }}'
    [ ! -z '{{ name }}' ] && name='{{ name }}' || true
    just lxc-sandbox "${name}"
    ssh "${name}" 2>/dev/null -- '[[ -d /workspace ]] && ( echo true && cd /workspace && source /etc/profile && just bootstrap ) || echo "workspace/ not found "'

# ─── TEARDOWN LXC NODES ─────────────────────────────────────────────────────────

alias tl := teardown-lxc
alias lxc-clean := teardown-lxc
alias lc := teardown-lxc

teardown-lxc *name:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z '{{ name }}' ]; then
        set -euo pipefail
        readarray -t containers < <(lxc list --format json 2>/dev/null | jq -c '
        [
            .[]
            | select(.profiles | contains(["{{ project_name }}"]))
            |{
                name:.name,
            }
        ]
        ' | jq -r '.[] | @base64')
    else
        readarray -t containers < <(lxc list --format json 2>/dev/null | jq -c '
        [
            .[]
            | select(.name | contains("{{ name }}"))
            |{
                name:.name,
            }
        ]
        ' | jq -r '.[] | @base64')
    fi
    for container in "${containers[@]}"; do
        _jq() {
            echo "${container}" | base64 --decode | jq -r "${1}"
        }
        name="$(_jq '.name')"
        echo >&2 "*** removing '${name}' container";
        lxc delete -f "${name}" 2>/dev/null
        echo >&2 "*** removing '${name}' entry from /etc/hosts"
        [ -r /etc/hosts ] && sudo sed -i "/${name}/d" /etc/hosts 2>/dev/null || true
        echo >&2 "*** removing '${name}' SSH config"
        [ -r $HOME/.ssh/config ] &&  sed -n -i "/${name}/,/UserKnownHostsFile/!{//!p}" ~/.ssh/config || true
    done
    lxc profile delete "{{ project_name }}-debian" > /dev/null 2>&1 || true

# ─── GITPOD ─────────────────────────────────────────────────────────────────────

gitpod-docker-socket-chown:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo chown "$(id -u gitpod):$(cut -d: -f3 < <(getent group docker))" /var/run/docker.sock

alias gp-fo := gitpod-fix-ownership

gitpod-fix-ownership: gitpod-docker-socket-chown
    #!/usr/bin/env bash
    set -euo pipefail
    sudo find "${HOME}/" "/workspace" -not -group `id -g` -not -user `id -u` -print0 | xargs -P 0 -0 --no-run-if-empty sudo chown --no-dereference "`id -u`:`id -g`" || true ;
    # sudo find "/workspace" -not -group `id -g` -not -user `id -u` -print | xargs -I {}  -P `nproc` --no-run-if-empty sudo chown --no-dereference "`id -u`:`id -g`" {} || true ;

gitpod-docker-login-env:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "*** ensuring current user belongs to docker group" ;
    sudo usermod -aG docker "$(whoami)"
    echo "*** ensuring required environment variables are present" ;
    while [ -z "$DOCKER_USERNAME" ] ; do \
    printf "\n❗ The DOCKER_USERNAME environment variable is required. Please enter its value.\n" ;
    read -s -p "DOCKER_USERNAME: " DOCKER_USERNAME ; \
    done ; gp env DOCKER_USERNAME=$DOCKER_USERNAME && printf "\nThanks\n" || true ;
    while [ -z "$DOCKER_PASSWORD" ] ; do \
    printf "\n❗ The DOCKER_PASSWORD environment variable is required. Please enter its value.\n" ;
    read -s -p "DOCKER_PASSWORD: " DOCKER_PASSWORD ; \
    done ; gp env DOCKER_PASSWORD=$DOCKER_PASSWORD && printf "\nThanks\n" || true ;

alias gp-dl := gitpod-docker-login

gitpod-docker-login: gitpod-fix-ownership gitpod-docker-login-env
    #!/usr/bin/env bash
    set -euo pipefail
    echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin ;
    just gitpod-fix-ownership

gitpod-ssh-pub-key-env:
    #!/usr/bin/env bash
    set -euo pipefail
    while [ -z "$SSH_PUB_KEY" ] ; do \
    printf "\n❗ The SSH_PUB_KEY environment variable is required. Please enter its value.\n" ;
    read -s -p "SSH_PUB_KEY: " SSH_PUB_KEY ; \
    done ; gp env SSH_PUB_KEY=$SSH_PUB_KEY && printf "\nThanks\n" || true ;

gitpod-ssh-pub-key: gitpod-fix-ownership gitpod-ssh-pub-key-env
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ${HOME}/.ssh ;
    echo "${SSH_PUB_KEY}" | tee ${HOME}/.ssh/authorized_keys > /dev/null ;
    chmod 700 ${HOME}/.ssh ;
    chmod 600 ${HOME}/.ssh/authorized_keys ;
    just gitpod-fix-ownership
    exit 0

gitpod-chisel: gitpod-fix-ownership
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f ${HOME}/chisel.pid ] && echo "*** killing chisel server" && kill -9 "$(cat ${HOME}/chisel.pid)" && rm -rf ${HOME}/chisel.pid ;
    pushd ${HOME}/ ;
    echo "*** starting chisel server" ;
    bash -c "chisel server --socks5 --pid > ${HOME}/chisel.log 2>&1 &" ;
    echo "*** chisel was started successfully" ;
    popd ;
    just gitpod-fix-ownership
    exit 0

gitpod-dropbear: gitpod-fix-ownership
    #!/usr/bin/env bash
    set -euo pipefail
    [ ! -f ${HOME}/dropbear.hostkey ] && echo "*** generating dropbear host key" && dropbearkey -t rsa -f ${HOME}/dropbear.hostkey ;
    [ -f ${HOME}/dropbear.pid ] && echo "*** killing dropbear server" && kill -9 "$(cat ${HOME}/dropbear.pid)" && rm -rf ${HOME}/dropbear.pid ;
    echo "*** starting dropbear server" ;
    bash -c "dropbear -r ${HOME}/dropbear.hostkey -F -E -s -p 2222 -P ${HOME}/dropbear.pid > ${HOME}/dropbear.log 2>&1 &" ;
    echo "*** dropbear server was started successfully" ;
    just gitpod-fix-ownership
    exit 0

alias gp-ssh := gitpod-ssh-config

gitpod-ssh-config: gitpod-ssh-pub-key
    #!/usr/bin/env bash
    set -euo pipefail
    cat << EOF
    Host $(gp url | sed -e 's/https:\/\///g' -e 's/[.].*$//g')
      HostName localhost
      User gitpod
      Port 2222
      ProxyCommand chisel client $(gp url 8080) stdio:%h:%p
      RemoteCommand cd /workspace && exec bash --login
      RequestTTY yes
      IdentityFile ~/.ssh/id_rsa
      IdentitiesOnly yes
      StrictHostKeyChecking no
      CheckHostIP no
      MACs hmac-sha2-256
      UserKnownHostsFile /dev/null
    EOF

# ─── VAGRANT RELATED TARGETS ────────────────────────────────────────────────────

alias vug := vagrant-up-gcloud

vagrant-up-gcloud:
    #!/usr/bin/env bash
    set -euo pipefail
    export NAME="$(basename "{{ justfile_directory() }}")" ;
    plugins=(
      "vagrant-share"
      "vagrant-google"
      "vagrant-rsync-back"
    );
    available_plugins=($(vagrant plugin list | awk '{print $1}'))
    intersection=($(comm -12 <(for X in "${plugins[@]}"; do echo "${X}"; done|sort)  <(for X in "${available_plugins[@]}"; do echo "${X}"; done|sort)))
    to_install=($(echo ${intersection[*]} ${plugins[*]} | sed 's/ /\n/g' | sort -n | uniq -u | paste -sd " " - ))
    if [ ${#to_install[@]} -ne 0  ];then
      vagrant plugin install ${to_install[@]}
    fi
    if [ -z ${GOOGLE_PROJECT_ID+x} ] || [ -z ${GOOGLE_PROJECT_ID} ]; then
      export GOOGLE_PROJECT_ID="$(gcloud config get-value core/project)" ;
    fi
    GCLOUD_IAM_ACCOUNT="${NAME}@${GOOGLE_PROJECT_ID}.iam.gserviceaccount.com"
    if ! gcloud iam service-accounts describe "${GCLOUD_IAM_ACCOUNT}" > /dev/null 2>&1; then
      gcloud iam service-accounts create "${NAME}" ;
      gcloud projects add-iam-policy-binding "${GOOGLE_PROJECT_ID}" \
        --member="serviceAccount:${GCLOUD_IAM_ACCOUNT}" \
        --role="roles/owner" ;
    fi
      if [ -z ${GOOGLE_APPLICATION_CREDENTIALS+x} ] || [ -z ${GOOGLE_APPLICATION_CREDENTIALS} ]; then
      export GOOGLE_APPLICATION_CREDENTIALS="${HOME}/${NAME}_gcloud.json" ;
    fi
    if [ -r "${GOOGLE_APPLICATION_CREDENTIALS}" ];then
      rm ${GOOGLE_APPLICATION_CREDENTIALS}
    fi
    gcloud iam service-accounts keys list \
      --iam-account="${GCLOUD_IAM_ACCOUNT}" \
      --format="value(KEY_ID)" | xargs -I {} \
      gcloud iam service-accounts keys delete \
      --iam-account="${GCLOUD_IAM_ACCOUNT}" {} >/dev/null 2>&1 || true ;
    gcloud iam service-accounts keys \
      create ${GOOGLE_APPLICATION_CREDENTIALS} \
      --iam-account="${GCLOUD_IAM_ACCOUNT}" ;
    rm -f "$HOME/.ssh/${NAME}"* ;
    ssh-keygen -q -N "" -t rsa -b 2048 -f "$HOME/.ssh/${NAME}" || true ;
    vagrant up --provider=google

# ────────────────────────────────────────────────────────────────────────────────

alias vdg := vagrant-down-gcloud

vagrant-down-gcloud:
    #!/usr/bin/env bash
    set -euo pipefail ;
    vagrant destroy -f || true ;
    export NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" ;
    if [ -z ${GOOGLE_PROJECT_ID+x} ] || [ -z ${GOOGLE_PROJECT_ID} ]; then
    export GOOGLE_PROJECT_ID="$(gcloud config get-value core/project)" ;
    fi
    if [ -z ${GOOGLE_APPLICATION_CREDENTIALS+x} ] || [ -z ${GOOGLE_APPLICATION_CREDENTIALS} ]; then
    export GOOGLE_APPLICATION_CREDENTIALS="${HOME}/${NAME}_gcloud.json" ;
    fi
    GCLOUD_IAM_ACCOUNT="${NAME}@${GOOGLE_PROJECT_ID}.iam.gserviceaccount.com"
    gcloud iam service-accounts delete --quiet "${GCLOUD_IAM_ACCOUNT}" > /dev/null 2>&1  || true ;
    rm -f "${GOOGLE_APPLICATION_CREDENTIALS}" ;
    rm -f "$HOME/.ssh/${NAME}" ;
    rm -f "$HOME/.ssh/${NAME}.pub" ;
    gcloud compute instances delete --quiet "${NAME}" > /dev/null 2>&1 || true ;
    sudo rm -rf .vagrant ;
