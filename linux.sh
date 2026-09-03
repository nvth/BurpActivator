#!/usr/bin/env bash
set -euo pipefail

BURP_URL="https://portswigger-cdn.net/burp/releases/download?product=pro&version=&type=jar"
JDK_URL="https://github.com/nvth/burpsuite/releases/download/v2024.7.4/jdk-21.0.9_linux-x64_bin.tar.gz"
LOADER_UBUNTU_URL="https://github.com/nvth/burpsuite/releases/download/v2026.3.3/core.jar"
ICON_URL="https://github.com/nvth/burpsuite/releases/download/v2024.7.4/burppro.ico"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/burpsuite_nvth"
DATA_DIR="$ROOT_DIR/data"
BIN_DIR="$ROOT_DIR/bin"

BURP_JAR="$DATA_DIR/burpsuite_pro.jar"
LOADER_UBUNTU="$DATA_DIR/core.jar"
ICON_PATH="$DATA_DIR/burppro.ico"
LAUNCHER="$BIN_DIR/burp"
JDK_TAR="$DATA_DIR/jdk-21.0.9_linux-x64_bin.tar.gz"
ENV_FILE="/etc/profile.d/burpsuite_nvth_java.sh"

echo "== Burp Suite Pro (Linux) Installer =="
echo "Root directory: $ROOT_DIR"
echo "Data directory: $DATA_DIR"
echo "Bin directory: $BIN_DIR"

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  echo "Example: sudo bash $0"
  exit 1
fi

mkdir -p "$DATA_DIR" "$BIN_DIR"


download_file() {
  local url="$1"
  local dest="$2"
  local label="$3"
  echo "Downloading $label..."
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$dest" "$url"
  else
    echo "curl or wget not found. Please install one of them."
    exit 1
  fi
  if [[ ! -s "$dest" ]]; then
    echo "Download failed or file is empty: $dest"
    exit 1
  fi
}

validate_tar_gz() {
  local file="$1"
  if ! command -v tar >/dev/null 2>&1; then
    echo "tar not found. Please install tar and re-run."
    exit 1
  fi
  tar -tzf "$file" >/dev/null 2>&1
}

validate_jar() {
  local file="$1"
  if command -v unzip >/dev/null 2>&1; then
    unzip -t -qq "$file" >/dev/null 2>&1
    return $?
  fi
  if command -v zipinfo >/dev/null 2>&1; then
    zipinfo -t "$file" >/dev/null 2>&1
    return $?
  fi
  local jar_cmd=""
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/jar" ]]; then
    jar_cmd="$JAVA_HOME/bin/jar"
  elif command -v jar >/dev/null 2>&1; then
    jar_cmd="$(command -v jar)"
  fi
  if [[ -n "$jar_cmd" ]]; then
    "$jar_cmd" tf "$file" >/dev/null 2>&1
    return $?
  fi
  echo "No tool to validate JAR (unzip/zipinfo/jar). Please install unzip or a full JDK."
  return 2
}

ensure_valid_jar() {
  local file="$1"
  local url="$2"
  local label="$3"
  if [[ -f "$file" ]]; then
    validate_jar "$file"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
      echo "$label already exists and is valid."
      return 0
    elif [[ $rc -eq 2 ]]; then
      exit 1
    fi
    echo "$label is invalid. Re-downloading..."
    rm -f "$file"
  fi
  download_file "$url" "$file" "$label"
  validate_jar "$file"
  local rc=$?
  if [[ $rc -eq 2 ]]; then
    exit 1
  fi
  if [[ $rc -ne 0 ]]; then
    echo "$label validation failed after download."
    exit 1
  fi
}

get_java_major() {
  local java_cmd="java"
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    java_cmd="$JAVA_HOME/bin/java"
  elif ! command -v java >/dev/null 2>&1; then
    return 1
  fi
  local line
  line="$("$java_cmd" -version 2>&1 | head -n 1)"
  if [[ $line =~ \"([0-9]+)\. ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ $line =~ \"1\.([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

install_java21() {
  local existing_dir
  existing_dir="$(ls -d "$DATA_DIR"/jdk-* 2>/dev/null | head -n 1 || true)"
  if [[ -n "$existing_dir" ]]; then
    echo "Found existing JDK at $existing_dir. Using it."
    export JAVA_HOME="$existing_dir"
    export PATH="$JAVA_HOME/bin:$PATH"
    cat > "$ENV_FILE" <<EOF
export JAVA_HOME="$JAVA_HOME"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
    chmod 644 "$ENV_FILE"
    echo "JAVA_HOME set to $JAVA_HOME"
    echo "Environment file created: $ENV_FILE"
    return 0
  fi

  if [[ -f "$JDK_TAR" ]]; then
    echo "JDK archive already exists. Verifying..."
    if ! validate_tar_gz "$JDK_TAR"; then
      echo "JDK archive is invalid or incomplete. Re-downloading..."
      rm -f "$JDK_TAR"
      download_file "$JDK_URL" "$JDK_TAR" "OpenJDK 21"
    else
      echo "JDK archive looks OK."
    fi
  else
    download_file "$JDK_URL" "$JDK_TAR" "OpenJDK 21"
  fi

  echo "Installing OpenJDK 21 (silent)..."
  local top_dir
  set +o pipefail
  top_dir="$(tar -tzf "$JDK_TAR" | head -n 1 | cut -d/ -f1)"
  local tar_status=$?
  set -o pipefail
  if [[ $tar_status -ne 0 ]]; then
    echo "Failed to read JDK archive. Please re-run the script to re-download."
    exit 1
  fi
  if [[ -z "$top_dir" ]]; then
    echo "Failed to read JDK archive."
    exit 1
  fi

  if [[ ! -d "$DATA_DIR/$top_dir" ]]; then
    tar -xzf "$JDK_TAR" -C "$DATA_DIR"
  else
    echo "JDK already extracted at $DATA_DIR/$top_dir."
  fi

  if [[ ! -x "$DATA_DIR/$top_dir/bin/java" ]]; then
    echo "Java binary not found after extraction: $DATA_DIR/$top_dir/bin/java"
    exit 1
  fi

  export JAVA_HOME="$DATA_DIR/$top_dir"
  export PATH="$JAVA_HOME/bin:$PATH"

  cat > "$ENV_FILE" <<EOF
export JAVA_HOME="$JAVA_HOME"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
  chmod 644 "$ENV_FILE"
  echo "JAVA_HOME set to $JAVA_HOME"
  echo "Environment file created: $ENV_FILE"
}

JAVA_MAJOR="$(get_java_major || true)"
if [[ -z "$JAVA_MAJOR" || ( "$JAVA_MAJOR" != "18" && "$JAVA_MAJOR" != "21" ) ]]; then
  echo "Java 18 or 21 is required."
  read -r -p "Do you want to download and install OpenJDK 21 now? (Y/N) " answer
  if [[ ! $answer =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "This app requires Java 18 or 21. Install it and re-run this script."
    exit 1
  fi
  install_java21
  JAVA_MAJOR="$(get_java_major || true)"
  if [[ "$JAVA_MAJOR" != "18" && "$JAVA_MAJOR" != "21" ]]; then
    echo "Java 21 install did not complete successfully. Please install Java 18 or 21 and re-run."
    exit 1
  fi
fi

ensure_valid_jar "$BURP_JAR" "$BURP_URL" "burpsuite_pro.jar"

if [[ -f "$SCRIPT_DIR/core.jar" && "$SCRIPT_DIR/core.jar" != "$LOADER_UBUNTU" ]]; then
  cp -f "$SCRIPT_DIR/core.jar" "$LOADER_UBUNTU"
fi
if [[ ! -f "$LOADER_UBUNTU" ]]; then
  echo "[INFO] Local core.jar not found. Downloading Core from GitHub release v2026.3.3."
fi
ensure_valid_jar "$LOADER_UBUNTU" "$LOADER_UBUNTU_URL" "core.jar"

if [[ ! -f "$ICON_PATH" ]]; then
  if [[ -f "$SCRIPT_DIR/burppro.ico" ]]; then
    cp -f "$SCRIPT_DIR/burppro.ico" "$ICON_PATH"
  else
    download_file "$ICON_URL" "$ICON_PATH" "burppro.ico"
  fi
fi

if [[ -f "$LOADER_UBUNTU" ]]; then
  echo "Using core.jar (data)"
  ACTIVE_LOADER="$LOADER_UBUNTU"
else
  echo "Core JAR not found. Please place core.jar in $SCRIPT_DIR."
  exit 1
fi

cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH")"
elif command -v realpath >/dev/null 2>&1; then
  SCRIPT_PATH="$(realpath "$SCRIPT_PATH")"
fi
ROOT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
BURP_JAR="$DATA_DIR/burpsuite_pro.jar"

if [[ -f "$DATA_DIR/core.jar" ]]; then
  LOADER_JAR="$DATA_DIR/core.jar"
else
  echo "Core JAR not found in $DATA_DIR." >&2
  exit 1
fi

if [[ ! -f "$BURP_JAR" ]]; then
  echo "burpsuite_pro.jar not found in $DATA_DIR." >&2
  exit 1
fi

JAVA_BIN=""
if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
  JAVA_BIN="$JAVA_HOME/bin/java"
else
  JAVA_DIR="$(ls -d "$DATA_DIR"/jdk-* 2>/dev/null | head -n 1 || true)"
  if [[ -n "$JAVA_DIR" && -x "$JAVA_DIR/bin/java" ]]; then
    JAVA_BIN="$JAVA_DIR/bin/java"
  else
    JAVA_BIN="$(command -v java || true)"
  fi
fi

if [[ -z "$JAVA_BIN" ]]; then
  echo "Java not found. Please install Java 18 or 21." >&2
  exit 1
fi

get_total_mem_gb() {
  local kb
  kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  if [[ -z "$kb" ]]; then
    echo "0"
    return 1
  fi
  echo $((kb / 1024 / 1024))
  return 0
}

get_java_opts() {
  local mem_gb
  mem_gb="$(get_total_mem_gb || true)"
  if [[ -z "$mem_gb" || "$mem_gb" -le 0 ]]; then
    echo ""
    return 0
  fi
  if [[ "$mem_gb" -lt 16 ]]; then
    echo ""
    return 0
  fi
  if [[ "$mem_gb" -lt 32 ]]; then
    echo "-Xmx8g"
    return 0
  fi
  echo ""
}

JAVA_OPTS="$(get_java_opts)"

"$JAVA_BIN" $JAVA_OPTS --add-opens=java.desktop/javax.swing=ALL-UNNAMED \
  --add-opens=java.base/java.lang=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED \
  --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED \
  -javaagent:"$LOADER_JAR" -noverify -jar "$BURP_JAR" >/dev/null 2>&1 &
EOF

chmod +x "$LAUNCHER"
echo "Launcher created: $LAUNCHER"

# Create symlink
SYMLINK_PATH="/usr/local/bin/burp"
if [[ $EUID -eq 0 ]]; then
  ln -sf "$LAUNCHER" "$SYMLINK_PATH"
  echo "Symlink created: $SYMLINK_PATH"
else
  if command -v sudo >/dev/null 2>&1; then
    if sudo ln -sf "$LAUNCHER" "$SYMLINK_PATH"; then
      echo "Symlink created: $SYMLINK_PATH"
    else
      echo "Could not write to /usr/local/bin. Falling back to ~/.local/bin"
      mkdir -p "$HOME/.local/bin"
      SYMLINK_PATH="$HOME/.local/bin/burp"
      ln -sf "$LAUNCHER" "$SYMLINK_PATH"
      echo "Symlink created: $SYMLINK_PATH"
    fi
  else
    echo "sudo not found. Falling back to ~/.local/bin"
    mkdir -p "$HOME/.local/bin"
    SYMLINK_PATH="$HOME/.local/bin/burp"
    ln -sf "$LAUNCHER" "$SYMLINK_PATH"
    echo "Symlink created: $SYMLINK_PATH"
  fi
fi

# Create desktop shortcut (no terminal)
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/BurpSuiteProfessional.desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Burp Suite Professional
Exec=$SYMLINK_PATH
Icon=$ICON_PATH
Terminal=false
Categories=Development;Security;
EOF

echo "Desktop shortcut created: $DESKTOP_FILE"
if [[ ! -f "$ICON_PATH" ]]; then
  echo "Warning: burppro.ico not found. You can add it later at $ICON_PATH."
fi

# Create uninstall script
UNINSTALL_SH="$ROOT_DIR/uninstall.sh"
printf '#!/usr/bin/env bash\nINSTALL_USER=%q\n' "${SUDO_USER:-$(id -un)}" > "$UNINSTALL_SH"
cat >> "$UNINSTALL_SH" <<'EOF'
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  echo "Example: sudo bash $0"
  exit 1
fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$ROOT_DIR/bin"
DATA_DIR="$ROOT_DIR/data"
USER_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"
if [[ -z "$USER_HOME" || "$USER_HOME" != /* || "$USER_HOME" == / || ! -d "$USER_HOME" ]]; then
  echo "[ERROR] Cannot resolve the installation account's home directory: $INSTALL_USER" >&2
  exit 1
fi
DESKTOP_FILE="$USER_HOME/.local/share/applications/BurpSuiteProfessional.desktop"
ENV_FILE="/etc/profile.d/burpsuite_nvth_java.sh"
SYMLINK_SYSTEM="/usr/local/bin/burp"
SYMLINK_USER="$USER_HOME/.local/bin/burp"

echo "[INFO] Close every Burp Suite instance before continuing so it cannot save the license again."
read -r -p "Remove Burp Suite NVTH files AND stored Burp license/preferences for $INSTALL_USER? Other Burp installations sharing these preferences are affected. (Y/N) " answer
if [[ ! $answer =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Canceled."
  exit 1
fi

# Remove only the verified Burp preference node for the installation account.
BURP_PREFS="$USER_HOME/.java/.userPrefs/burp"
if [[ -e "$BURP_PREFS" || -L "$BURP_PREFS" ]]; then
  USER_HOME_REAL="$(realpath -e -- "$USER_HOME")"
  BURP_PREFS_REAL="$(realpath -m -- "$BURP_PREFS")"
  if [[ "$BURP_PREFS_REAL" != "$USER_HOME_REAL/.java/.userPrefs/burp" ]]; then
    echo "[ERROR] Burp preferences resolve through a redirected path. Remove them manually: $BURP_PREFS" >&2
    exit 1
  fi
  rm -rf -- "$BURP_PREFS"
  echo "[INFO] Removed stored Burp license and preferences for $INSTALL_USER."
else
  echo "[INFO] No Burp Java preferences found for $INSTALL_USER."
fi

if [[ -L "$SYMLINK_SYSTEM" ]]; then
  if [[ $EUID -eq 0 ]]; then
    rm -f "$SYMLINK_SYSTEM"
  elif command -v sudo >/dev/null 2>&1; then
    sudo rm -f "$SYMLINK_SYSTEM"
  else
    echo "sudo not found. Skipping removal of $SYMLINK_SYSTEM."
  fi
fi

if [[ -L "$SYMLINK_USER" ]]; then
  rm -f "$SYMLINK_USER"
fi

if [[ -f "$DESKTOP_FILE" ]]; then
  rm -f "$DESKTOP_FILE"
fi

if [[ -d "$BIN_DIR" ]]; then
  rm -rf "$BIN_DIR"
fi

if [[ -d "$DATA_DIR" ]]; then
  rm -rf "$DATA_DIR"
fi

if [[ -f "$ENV_FILE" ]]; then
  rm -f "$ENV_FILE"
fi

UNINSTALL_TXT="$ROOT_DIR/UNINSTALL.txt"
if [[ -f "$UNINSTALL_TXT" ]]; then
  rm -f "$UNINSTALL_TXT"
fi

SELF="$0"
echo "Uninstall completed. Removing uninstall script."
sleep 1
rm -f "$SELF"
EOF
chmod +x "$UNINSTALL_SH"
echo "Uninstall script created: $UNINSTALL_SH"

# Create uninstall instructions
UNINSTALL_TXT="$ROOT_DIR/UNINSTALL.txt"
cat > "$UNINSTALL_TXT" <<EOF
UNINSTALL (Linux)

Step 1: Close all Burp Suite instances and open a terminal.
Step 2: Run as root:
  sudo bash $UNINSTALL_SH
Uninstall also removes the installation account's stored Burp license and Java preferences.
Other Burp installations sharing these preferences will need configuration/activation again.
EOF
echo "Uninstall instructions created: $UNINSTALL_TXT"

resolve_java_bin() {
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    echo "$JAVA_HOME/bin/java"
    return 0
  fi
  local java_dir
  java_dir="$(ls -d "$DATA_DIR"/jdk-* 2>/dev/null | head -n 1 || true)"
  if [[ -n "$java_dir" && -x "$java_dir/bin/java" ]]; then
    echo "$java_dir/bin/java"
    return 0
  fi
  if command -v java >/dev/null 2>&1; then
    command -v java
    return 0
  fi
  return 1
}

get_total_mem_gb() {
  local kb
  kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  if [[ -z "$kb" ]]; then
    echo "0"
    return 1
  fi
  # Round down to whole GB
  echo $((kb / 1024 / 1024))
  return 0
}

get_java_opts() {
  local mem_gb
  mem_gb="$(get_total_mem_gb || true)"
  if [[ -z "$mem_gb" || "$mem_gb" -le 0 ]]; then
    echo ""
    return 0
  fi
  if [[ "$mem_gb" -lt 16 ]]; then
    echo ""
    return 0
  fi
  if [[ "$mem_gb" -lt 32 ]]; then
    echo "-Xmx8g"
    return 0
  fi
  # >= 32GB: no Xmx override
  echo ""
}

run_as_user() {
  local cmd="$1"
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    local display="${DISPLAY:-:0}"
    local xauth="${XAUTHORITY:-}"
    if [[ -z "$xauth" ]]; then
      local guess="/home/$SUDO_USER/.Xauthority"
      if [[ -f "$guess" ]]; then
        xauth="$guess"
      fi
    fi
    if [[ -n "$xauth" ]]; then
      sudo -u "$SUDO_USER" env DISPLAY="$display" XAUTHORITY="$xauth" bash -lc "$cmd"
    else
      sudo -u "$SUDO_USER" env DISPLAY="$display" bash -lc "$cmd"
    fi
  else
    bash -lc "$cmd"
  fi
}

echo "Starting Core and Burp Suite..."
JAVA_BIN="$(resolve_java_bin || true)"
if [[ -z "$JAVA_BIN" ]]; then
  echo "Java not found. Please install Java 18 or 21."
else
  JAVA_OPTS="$(get_java_opts)"
  if [[ -f "$ACTIVE_LOADER" ]]; then
    run_as_user "\"$JAVA_BIN\" -jar \"$ACTIVE_LOADER\" >/dev/null 2>&1 &"
    sleep 2
  fi
  run_as_user "\"$JAVA_BIN\" ${JAVA_OPTS} --add-opens=java.desktop/javax.swing=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED --add-opens=java.base/jdk.internal.org.objectweb.asm.Opcodes=ALL-UNNAMED -javaagent:\"$ACTIVE_LOADER\" -noverify -jar \"$BURP_JAR\" >/dev/null 2>&1 &"
fi

echo ""
echo "Done. You can launch Burp Suite from your app menu or run: $SYMLINK_PATH"
