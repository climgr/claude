---
name: RPM packaging conventions
description: Spec file structure, build workflow, signing, and repo layout for CasjaysDev RPM packages
type: user
---

## Directory Layout

```
~/rpmbuild/                              # Spec files + sources (per-package subdirs)
  {name}/
    {name}.spec
    {source tarballs / patches}

~/.local/tmp/BUILD/                      # rpmbuild working dir (%_builddir)
~/.local/tmp/BUILDROOT/                  # rpmbuild install root (%_buildrootdir)

~/Documents/builds/rpmbuild/RHEL/el{VER}/
  SRPMS/                                 # Source RPMs
  {ARCH}/rpms/                           # Binary RPMs  ← final output
  {ARCH}/debug/                          # debuginfo/debugsource

~/Documents/builds/sourceforge/RHEL/el{VER}/{ARCH}/
  casjay/    os/    langs/    databases/
  infra/     extras/   kernel/   debug/   testing/   empty/
```

Spec and source files always live together under `~/rpmbuild/{name}/` — this
matches `%_specdir` and `%_sourcedir` in `.rpmmacros`.

---

## ~/.rpmmacros

Full config — install to `~/.rpmmacros` on any build host or inside any build container:

```
%global debug_package  %{nil}

%distroname           casjay
%packager             CasjaysDev
%_gpg_name            CasjaysDev RPM Dev <rpm-devel@casjaysdev.pro>
%vendor               %packager http://github.com/rpm-devel

%_minorver            .3.4
%_pdistro             %distroname
%_osver               el%{?rhel}

%dist                 %_minorver.%_pdistro.%_osver
%distribution         %_minorver.%_pdistro.%_osver
%_release_name        RHEL

%_topdir              %{getenv:HOME}/rpmbuild
%_sourcedir           %{getenv:HOME}/rpmbuild/%{name}
%_specdir             %{getenv:HOME}/rpmbuild/%{name}
%_builddir            %{getenv:HOME}/.local/tmp/BUILD
%_buildrootdir        %{getenv:HOME}/.local/tmp/BUILDROOT
%_buildroot           %{_buildrootdir}/%{name}-%{version}-%{release}.%{BuildArch}

%_srcrpmdir           %{getenv:HOME}/Documents/builds/rpmbuild/%_release_name/%_osver/SRPMS
%_rpmdir              %{getenv:HOME}/Documents/builds/rpmbuild/%_release_name/%_osver/%BuildArch/rpms
%_debugrpmdir         %{getenv:HOME}/Documents/builds/rpmbuild/%_release_name/%_osver/%BuildArch/debug

%_signature           gpg
%_gpg_path            %(echo $HOME)/.gnupg
%_gpgbin              /usr/bin/gpg
%_var                 /var
%_tmppath             /tmp
%_usr                 /usr
%_usrdir              /usr
%_usrsrc              /usr/src
%_docdir              /usr/share/doc
%_sysconfdir          /etc
%_prefix              /usr
%_bindir              /usr/bin
%_libdir              /usr/%_lib
%_libexecdir          /usr/libexec
%_sbindir             /usr/sbin
%_sharedstatedir      /var/lib
%_datarootdir         /usr/share
%_datadir             /usr/share
%_includedir          /usr/include
%_infodir             /usr/share/info
%_mandir              /usr/share/man
%_localstatedir       /var
%_initddir            /etc/rc.d/init.d
%ext_info             .gz
%ext_man              .gz
%_smp_mflags          -j2

# Non-interactive GPG signing — reads passphrase from file, never prompts
%__gpg_sign_cmd       %{__gpg} gpg \
  --no-verbose --no-armor --batch \
  --passphrase-file %{getenv:HOME}/.gnupg/rpm_sign_pass.txt \
  --pinentry-mode loopback \
  --no-secmem-warning \
  -u "%{_gpg_name}" \
  -sbo %{__signature_filename} \
  --digest-algo sha256 \
  %{__plaintext_filename}

%__arch_install_post [ "%{buildarch}" = "noarch" ] || QA_CHECK_RPATHS=1 ; \
    case "${QA_CHECK_RPATHS:-}" in [1yY]*) /usr/lib/rpm/check-rpaths ;; esac \
    /usr/lib/rpm/check-buildroot
```

### GPG passphrase file

`~/.gnupg/rpm_sign_pass.txt` must exist on the build host and inside any
build container (bind-mount it in). Permissions must be `600`:

```sh
chmod 600 ~/.gnupg/rpm_sign_pass.txt
```

The file contains only the raw passphrase, no newline required but one is harmless.

---

## Supported Versions

Build for every version in this matrix **where the software's dependencies
allow it**. If a version cannot be supported (missing dep, incompatible
runtime), skip it with a `%if` conditional and a comment explaining why.
Never silently drop a version.

All builds run inside `ghcr.io/rpm-devel/build:latest` using `mock`.
EOL targets use the `eol/` prefix — their repos have moved to archive
locations but builds are still fully required for security and bug fixes.

| Target | Versions | mock config |
|---|---|---|
| RHEL / CentOS 7 (EOL) | EL7 | `eol/centos-7-{arch}` |
| RHEL / AlmaLinux 8 | EL8 | `almalinux-8-{arch}` |
| RHEL / AlmaLinux 9 | EL9 | `almalinux-9-{arch}` |
| RHEL / AlmaLinux 10 | EL10 | `almalinux-10-{arch}` |
| Fedora 36–41 (EOL) | — | `eol/fedora-{36..41}-{arch}` |
| Fedora 42–current | — | `fedora-{N}-{arch}` |

Always build both `x86_64` and `aarch64` — never skip an arch.

### Version availability guards

When a feature or dependency is not available on older platforms, use a
conditional and document why:

```spec
# Recommends/Suggests are not available on EL7
%if 0%{?rhel} >= 8 || 0%{?fedora}
Recommends: {optional-dep}
%endif

# EL7 ships Python 3.6 — certbot requires 3.10+
%if 0%{?rhel} <= 7
%{error: EL7 does not provide Python >= 3.10 — this package cannot be built for EL7}
%endif
```

---

## Build — Docker Container

Builds always run inside `ghcr.io/rpm-devel/build:latest` using `mock`.
Never run `rpmbuild` directly on the host. All tools are pre-installed —
no container setup step is needed.

`mock` requires `--privileged` to create chroots.

### Pre-installed packages and repos

| Group | Packages |
|---|---|
| RPM toolchain | `mock`, `mock-core-configs`, `rpm-build`, `rpm-sign`, `rpmdevtools`, `rpmlint`, `dnf-utils`, `createrepo_c` |
| C/C++ build | `gcc`, `gcc-c++`, `binutils`, `make`, `cmake`, `autoconf`, `automake`, `libtool`, `pkgconf-pkg-config`, `patch`, `diffutils` |
| Common headers | `glibc-devel`, `openssl-devel`, `zlib-devel` |
| Archive formats | `bzip2`, `xz`, `zstd`, `unzip` |
| Scripting runtimes | `python3`, `python3-pip`, `perl` |
| VCS | `git`, `git-lfs` |
| Network / transfer | `curl`, `wget`, `rsync` |
| CI/CD | `copr-cli`, `jq` |
| Provider CLIs | `gh` (GitHub), `glab` (GitLab), `tea` (Gitea + Forgejo) |
| Utilities | `bc`, `file`, `which`, `hostname` |
| GPG / signing | `gnupg2`, `pinentry` |

**Enabled repos (Fedora host):**

| Repo | Purpose |
|---|---|
| Fedora main + updates | Default |
| RPM Fusion free | Packages not in main Fedora repos — codecs, drivers, extras |
| RPM Fusion nonfree | Non-free extras — firmware, proprietary drivers |
| GitHub CLI (gh-cli) | Official `gh` RPM repo |

**EPEL note:** EPEL applies to EL targets only, not the Fedora host. For
mock-based builds, EPEL is already configured in the EL mock chroot configs
shipped by `mock-core-configs` — no action needed. For direct `rpmbuild -ba`
against EL, run in a separate EL container.

`dnf builddep {spec}` is available via `dnf-utils` for direct `rpmbuild -ba`
builds. When using `mock --rebuild` it is not needed — mock installs
`BuildRequires` automatically inside the chroot, pulling from whatever repos
the target's mock config defines (including EPEL for EL targets).

### Build a SRPM then rebuild for each target

```sh
# 1. Start the build container (interactive)
docker run --rm \
  --privileged \
  --name rpmbuild-{name}-$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
  -v "$HOME/rpmbuild:/root/rpmbuild" \
  -v "$HOME/Documents/builds:/root/Documents/builds" \
  -v "$HOME/.rpmmacros:/root/.rpmmacros:ro" \
  -v "$HOME/.gnupg:/root/.gnupg:ro" \
  ghcr.io/rpm-devel/build:latest bash

# 2. Inside the container — download sources and build SRPM
spectool -g -R ~/rpmbuild/{name}/{name}.spec
rpmbuild -bs ~/rpmbuild/{name}/{name}.spec

# 3. Rebuild the SRPM for each target (repeat per version/arch)
mock -r almalinux-9-x86_64      --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r almalinux-9-aarch64     --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r almalinux-8-x86_64      --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r almalinux-8-aarch64     --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r almalinux-10-x86_64     --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r almalinux-10-aarch64    --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r eol/centos-7-x86_64     --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r eol/centos-7-aarch64    --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r fedora-42-x86_64        --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r fedora-42-aarch64       --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r eol/fedora-41-x86_64    --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
mock -r eol/fedora-41-aarch64   --rebuild ~/rpmbuild/SRPMS/{name}-{version}*.src.rpm
```

Results land in `/var/lib/mock/{target}/result/`. Skip targets where the
software's dependencies are unavailable — use `%if` guards in the spec and
note the reason.

### Non-interactive mode (CI / scripted)

Pass either a `.spec` or a `.src.rpm` as the CMD:

```sh
# From a spec file — entrypoint runs spectool + rpmbuild -bs, then mock --rebuild
docker run --rm \
  --privileged \
  --name rpmbuild-{name}-$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
  -v "$HOME/rpmbuild:/root/rpmbuild" \
  -v "$HOME/Documents/builds:/root/Documents/builds" \
  -v "$HOME/.rpmmacros:/root/.rpmmacros:ro" \
  -v "$HOME/.gnupg:/root/.gnupg:ro" \
  -e RPM_TARGET=almalinux-9-x86_64 \
  -e RPM_GPG_KEY_ID="CasjaysDev RPM Dev <rpm-devel@casjaysdev.pro>" \
  ghcr.io/rpm-devel/build:latest \
  /root/rpmbuild/SPECS/{name}.spec

# From a pre-built SRPM — passed directly to mock --rebuild
docker run --rm \
  --privileged \
  --name rpmbuild-{name}-$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-8) \
  -v "$HOME/rpmbuild:/root/rpmbuild" \
  -v "$HOME/Documents/builds:/root/Documents/builds" \
  -v "$HOME/.rpmmacros:/root/.rpmmacros:ro" \
  -v "$HOME/.gnupg:/root/.gnupg:ro" \
  -e RPM_TARGET=almalinux-9-x86_64 \
  ghcr.io/rpm-devel/build:latest \
  /root/rpmbuild/SRPMS/{name}-{version}*.src.rpm
```

When a `.spec` is given the entrypoint: downloads sources with `spectool -g -R`,
builds the SRPM with `rpmbuild -bs`, then passes the result to `mock --rebuild`.
mock handles all `BuildRequires` installation automatically inside the chroot.
Results are copied to `$RPM_OUTPUT_DIR/$RPM_TARGET/` (default `~/Documents/builds`).
All failures are hard errors (exit 1) — EOL targets are no exception.

### Verify macros

```sh
# Inside the container
# → .3.4.casjay.el9 (or .fcNN for Fedora)
rpm --eval '%dist'
# → CasjaysDev RPM Dev <rpm-devel@casjaysdev.pro>
rpm --eval '%_gpg_name'
```

---

## GPG Signing

Non-interactive signing uses `~/.gnupg/rpm_sign_pass.txt` via the
`%__gpg_sign_cmd` override in `.rpmmacros` (defined above). No pinentry,
no interactive prompt.

```sh
# Sign a single RPM
rpmsign --addsign {package}.rpm

# Sign all RPMs in a directory
find ~/Documents/builds/rpmbuild/RHEL/el9/x86_64/rpms -name '*.rpm' \
  -print0 | xargs -0 -r rpmsign --addsign

# Verify a signed RPM
rpm --checksig {package}.rpm
```

The passphrase file must be readable before `rpmsign` is called.
If the file does not exist or is unreadable, signing will fail — never
fall back to interactive mode.

Import the public key for local verification:

```sh
rpm --import ~/.gnupg/RPM-GPG-KEY-casjay
```

---

## Published Repo Layout

Packages are published on SourceForge at `rpm-devel.sourceforge.io/repo/`:

```
RHEL/{VER}/{ARCH}/
  rpms/     CasjaysDev custom-built packages
  addons/   Upstream third-party mirrors (OS, langs, databases, infra)
  extras/   Community extras (EPEL, RPM Fusion, Ghettoforge, ELRepo)
  debug/    All debuginfo / debugsource RPMs

RHEL/{VER}/
  srpms/    Source RPMs (shared across arches — stored once per version)

Fedora/{VER}/{ARCH}/  (same structure)
Fedora/{VER}/srpms/
```

### DNF repo sections and mirrorlist URLs

Clients use a mirrorlist hosted in the `casjay-release` GitHub repo.
The mirrorlist resolves to SourceForge and its mirrors.

| Section | mirrorlist | Contents |
|---|---|---|
| `casjay-rpms` | `ZREPO/RHEL/$releasever/$basearch/mirrors/rpms` | CasjaysDev-built packages |
| `casjay-addons` | `ZREPO/RHEL/$releasever/$basearch/mirrors/addons` | Upstream third-party |
| `casjay-extras` | `ZREPO/RHEL/$releasever/$basearch/mirrors/extras` | EPEL, RPM Fusion, Ghettoforge, ELRepo |
| `casjay-debug` | `ZREPO/RHEL/$releasever/$basearch/mirrors/debug` | debuginfo / debugsource |
| `casjay-sources` | `ZREPO/RHEL/$releasever/mirrors/srpms` | Source RPMs |

Full mirrorlist base URL: `https://github.com/rpm-devel/casjay-release/raw/main/`

GPG key: `https://github.com/rpm-devel/casjay-release/raw/main/ZREPO/RHEL/keys/RPM-GPG-KEY-casjay`

Example repo entry:

```ini
[casjay-rpms]
name=Casjay RPMs - $releasever $basearch
mirrorlist=https://github.com/rpm-devel/casjay-release/raw/main/ZREPO/RHEL/$releasever/$basearch/mirrors/rpms
gpgkey=https://github.com/rpm-devel/casjay-release/raw/main/ZREPO/RHEL/keys/RPM-GPG-KEY-casjay
enabled=1
module_hotfixes=1
```

### Actual SourceForge base URLs (inside mirrorlist files)

```
https://rpm-devel.sourceforge.io/repo/RHEL/{VER}/{ARCH}/rpms
https://rpm-devel.sourceforge.io/repo/RHEL/{VER}/{ARCH}/addons
https://rpm-devel.sourceforge.io/repo/RHEL/{VER}/{ARCH}/extras
https://rpm-devel.sourceforge.io/repo/RHEL/{VER}/{ARCH}/debug
https://rpm-devel.sourceforge.io/repo/RHEL/{VER}/srpms
```

Never use `sourceforge.net/projects/casjaysdev/files/` — that is incorrect.
Never use `sourceforge.net/projects/rpm-devel/` — that is also incorrect.
The correct host is `rpm-devel.sourceforge.io/repo/`.

## Repo Creation

After building and signing, create the repodata with `createrepo_c`:

```sh
# Create / update repo metadata
createrepo_c ~/Documents/builds/RHEL/9/x86_64/rpms/

# Sign the repomd.xml (clients with repo_gpgcheck=1 require this)
gpg --batch \
    --passphrase-file ~/.gnupg/rpm_sign_pass.txt \
    --pinentry-mode loopback \
    --detach-sign --armor \
    ~/Documents/builds/RHEL/9/x86_64/rpms/repodata/repomd.xml
```

Run `createrepo_c --update` on subsequent runs to only process new/changed packages.

---

## Package Repo Layout

Every individual package repo (`certbot`, `cmus`, `nginx`, etc.) uses a
**flat layout** — all files at the repository root:

```
{name}/
  {name}.spec          ← spec file at root
  {name}-{ver}.tar.gz  ← committed source(s) when not fetchable upstream
  *.patch              ← patches, if any
  sources              ← lookaside hash file, if used
```

**Never add** `SPEC/`, `SOURCES/`, `Makefile`, `IDEA.md`, `CLAUDE.md`,
`AI.md`, `PLAN.md`, `TODO.AI.md`, `.github/`, or any other wrapper
infrastructure to a package repo. The spec file is the source of truth.
`spectool -g -R` fetches all `SourceN:` URLs at build time.

---

## Spec File Structure

### Required header fields (in order)

```spec
# use %global for constants, not %define
%global some_ver  1.2.3

Name:       {name}
Version:    {version}
Release:    1%{?dist}
Summary:    One-line description (imperative, no trailing period)
License:    {SPDX-identifier}
URL:        https://...

Source0:    https://.../{name}-{version}.tar.gz
# Source1, Source2, ... for additional sources

BuildRequires: make
Requires:      bash

%description
Multi-line description of what the package does.
```

Rules:
- **`Release: 1%{?dist}`** — always; `%{?dist}` expands via `.rpmmacros`
- **`License:`** — SPDX identifiers (`Apache-2.0`, `MIT`, `GPLv2`, `GPLv2+`) — never informal names
- **No `Group:` tag** — deprecated since RHEL 7; omit entirely
- **No `%clean` section** — deprecated; omit entirely
- **No `%defattr`** — deprecated; use `%attr` per-file in `%files` if needed
- **Never `BuildArch: noarch`** — all packages are built per-arch (x86_64 and aarch64)
- **`%global` over `%define`** — `%global` expands everywhere; use it for spec-level constants

### Dependency Tags

Use every relevant tag — never leave out `Provides:` or `Obsoletes:` when a
package renames, replaces, or bundles something.

#### Requires / BuildRequires

```spec
BuildRequires: make
BuildRequires: gcc
Requires:      bash >= 4.0
# sub-package pin
Requires:      %{name}-data = %{version}-%{release}
```

- `BuildRequires` — only what is actually needed at build time
- `Requires` — runtime deps; version-pin when stability matters
- `%{version}-%{release}` — use for inter-subpackage deps so upgrades stay in sync

#### Provides

Always declare virtual names so other packages can depend on a stable name
regardless of the real package name:

```spec
Provides:  %{name}           = %{version}-%{release}
Provides:  virtual-cap-name  = %{version}-%{release}
# paired with Obsoletes
Provides:  old-package-name  = %{version}-%{release}
```

#### Obsoletes

When a package replaces or renames another, declare both `Provides:` **and**
`Obsoletes:`. `Obsoletes:` without a matching `Provides:` is a removal, not
a replacement — `dnf` will not offer the new package as the upgrade path.

```spec
# Renames old-name → new-name, upgrades cleanly
Provides:   old-name = %{version}-%{release}
Obsoletes:  old-name < %{version}-%{release}

# Replaces a split package with a bundled one (no version bound = all versions)
Provides:   split-subpackage  = %{version}-%{release}
Obsoletes:  split-subpackage
```

- **Version-bound `Obsoletes:`** (`< version`) when you only replace specific old
  versions and a future upstream package might reclaim the name
- **Unversioned `Obsoletes:`** only when you own the name permanently and no
  future package should exist under it

#### Conflicts

```spec
# cannot coexist with this version range
Conflicts:  other-provider >= 2.0
```

Use `Conflicts:` when two packages provide the same service/file and cannot
both be installed. Rare — prefer `Obsoletes:` for true replacements.

#### Soft dependencies (EL8+ and Fedora only — not available on EL7)

```spec
%if 0%{?rhel} >= 8 || 0%{?fedora}
# installed automatically if available, not a hard dep
Recommends: {nice-to-have}
# shown to the user but not auto-installed
Suggests:   {optional}
# pulled in when {other-pkg} is installed alongside this one
Supplements: {other-pkg}
# same direction as Supplements, complementary
Enhances:    {other-pkg}
%endif
```

#### Epoch

Avoid `Epoch:` unless fixing a version ordering mistake that cannot be solved
any other way. If used, document the reason in `%changelog`.

### Section separators

```spec
# -----------------------------------------------------------------------
# Python interpreter selection
# -----------------------------------------------------------------------
```

### Conditionals

```spec
%if 0%{?rhel} >= 10
  ...
%endif
%if 0%{?rhel} == 9
  ...
%endif
%if 0%{?fedora}
  ...
%endif
```

Use `0%{?rhel}` (leading zero) — expands to `0` when undefined, preventing syntax errors.

### %prep

```spec
%prep
%setup -q -n %{name}-%{version}
```

### %build

```spec
%build
%make_build
```

Or for custom builds:
```spec
%build
%{__make} %{?_smp_mflags} BINDIR=%{_bindir} PREFIX=%{_prefix}
```

- Always use `%{?_smp_mflags}` for parallel builds (set to `-j2` in `.rpmmacros`)
- Never hardcode paths — use macros
- Go binaries: `CGO_ENABLED=0 go build -ldflags "-s -w" -o %{name} ./...`

### %install

```spec
%install
%{__rm} -rf %{buildroot}
%{__install} -Dpm 0755 %{name}           %{buildroot}%{_bindir}/%{name}
%{__install} -Dpm 0644 %{name}.1         %{buildroot}%{_mandir}/man1/%{name}.1
%{__install} -Dpm 0644 completions/bash  %{buildroot}%{_datadir}/bash-completion/completions/%{name}
%{__install} -Dpm 0644 %{name}.conf      %{buildroot}%{_sysconfdir}/%{name}/%{name}.conf
```

- Always start with `%{__rm} -rf %{buildroot}`
- Use RPM macro wrappers: `%{__install}`, `%{__rm}`, `%{__mkdir}`, `%{__cp}`, `%{__tar}`, `%{__ln_s}`
- `%{__install} -Dpm {mode} src dst` creates parent directories automatically
- Modes: `0755` executables · `0644` data/config · `0600` secrets

### %files

```spec
%files
%license LICENSE
%doc README.md
%{_bindir}/%{name}
%{_mandir}/man1/%{name}.1*
%{_datadir}/bash-completion/completions/%{name}
%config(noreplace) %{_sysconfdir}/%{name}/%{name}.conf
```

- `%license` — license file
- `%doc` — documentation
- `%config(noreplace)` — config not overwritten on upgrade (preferred)
- `%config` — config overwritten on upgrade (rare)
- `%dir` — own a directory without owning its contents
- `%attr({mode},{user},{group})` — explicit permissions when needed
- Always use macros, never hardcoded paths

### %changelog

```spec
%changelog
* Thu May 22 2026 CasjaysDev <rpm-devel@casjaysdev.pro> - 1.0-1
- Initial package
```

- Format: `* Weekday Mon DD YYYY Name <email> - version-release`
- Date must be a real calendar date (`rpmbuild` warns on invalid day-of-week)
- Most recent entry at top
- Bullets use `-` not `*`
- No markdown

---

## Scriptlets

`$1` argument values:

| `$1` | Meaning |
|---|---|
| `1` | Fresh install |
| `2` | Upgrade |
| `0` | Final removal |

### systemd services — use RPM macros

```spec
%post
%systemd_post %{name}.service

%preun
%systemd_preun %{name}.service

%postun
%systemd_postun_with_restart %{name}.service
```

`%systemd_*` macros (from `systemd-rpm-macros`) handle `$1` correctly and are
the RHEL/Fedora standard. Never write raw `systemctl` calls in scriptlets.
For timer units include both the `.service` and `.timer` in each macro.

### Non-systemd scriptlets

```spec
%post
if [ $1 -eq 1 ]; then
  # fresh install only
fi

%preun
if [ $1 -eq 0 ]; then
  # final removal only
fi
```

- Scriptlets must be minimal — no network calls, no package manager invocations
- Guard non-fatal operations with `|| true`
- Never `exit 1` in a scriptlet — it aborts the entire transaction

---

## Multi-Arch

Always build for both `x86_64` and `aarch64` — two separate containers, one per arch.
Never use `BuildArch: noarch`. Every package is arch-specific.

---

## Rules

- **Never hardcode paths** — always use `%{_bindir}`, `%{_sysconfdir}`, `%{_datadir}`, `%{_mandir}`, etc.
- **Use RPM macro wrappers** for all filesystem commands in `%install` and scriptlets
- **`%{buildroot}` not `$RPM_BUILD_ROOT`**
- **No `Group:`, no `%clean`, no `%defattr`** — deprecated; omit
- **`Release: 1%{?dist}`** always
- **All packages signed** with `rpmsign --addsign` before publishing — unsigned packages will not install when `gpgcheck=1`
- **Non-interactive signing** via `~/.gnupg/rpm_sign_pass.txt` and `%__gpg_sign_cmd` override in `.rpmmacros` — never rely on interactive pinentry
- **Spec + sources under `~/rpmbuild/{name}/`** — matches `%_specdir` / `%_sourcedir`
- **Builds always inside `ghcr.io/rpm-devel/build:latest`** — never `rpmbuild` on the host; use `mock` inside the container for all targets
- **`mock` requires `--privileged`** — always include it; mock creates chroots that need elevated permissions
- **No debug subpackages** — `%global debug_package %{nil}` is set globally in `.rpmmacros`
- **Supported versions**: RHEL/CentOS 7 through current EL, Fedora EOL (36–41) through current — build for every version the software's deps allow; skip with `%if` + comment if not
- **EOL targets use the `eol/` prefix** — `eol/centos-7-{arch}`, `eol/fedora-{36..41}-{arch}`; all failures are hard errors regardless of EOL status
- **Always both arches**: x86_64 and aarch64 — never noarch, never skip an arch
- **Provides + Obsoletes always paired** — `Obsoletes:` without a matching `Provides:` is a removal not an upgrade path; never use one without the other when replacing a package
- **Soft deps require a version guard** — `Recommends:`/`Suggests:` not available on EL7; wrap in `%if 0%{?rhel} >= 8 || 0%{?fedora}`
- **Version-bound Obsoletes preferred** — use `Obsoletes: old-name < version` unless you own the name permanently
- **No project meta files in package repos** — individual package repos (`certbot`, `cmus`, `nginx`, etc.) must not contain `IDEA.md`, `CLAUDE.md`, `PLAN.md`, `TODO.AI.md`, `AI.md`, `Makefile`, `SPEC/`, `SOURCES/`, or any wrapper infrastructure. The spec file IS the source of truth. Flat layout only: `{name}.spec`, committed source tarballs, patches, and an optional `sources` lookaside file.
- **Fix bogus `%changelog` dates** — whenever a spec is edited, verify every `%changelog` date has the correct weekday for that calendar date. A date with the wrong weekday is a hard error — correct it. Use `date -d "{YYYY-MM-DD}" +%a` to verify. Most common mistake: copy-pasted entries where only the date was changed but not the weekday.
