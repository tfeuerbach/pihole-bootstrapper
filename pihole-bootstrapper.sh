#!/bin/bash
set -e

# --- Debug Mode ---
if [[ "$1" == "-d" ]]; then
    echo "--- DEBUG MODE ENABLED ---"
    set -x # Print each command before it's executed
    shift # Consume the flag so it doesn't interfere with the menu
fi

# Quiet Homebrew noise
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1


# --- Pi-hole Bootstrapper for macOS ---
#
# One script to spin up Pi-hole in Docker on macOS and wire up DNS.
# Keeps it simple and cleans up after itself.
#

# --- Configuration ---
CONTAINER_NAME="local-pihole"
CONFIG_DIR="$(pwd)/pihole-config"
DNS_BACKUP_FILE="${CONFIG_DIR}/dns_backup.txt"
WEBPASSWORD="pihole"  # You can change the default admin portal password here if you like.
PIHOLE_HOSTNAME="pihole.local"
HOST_DNS_PORT=5053
DNS_READY_RETRIES=10

# --- UI & Colors ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'

function print_step() { echo -e "\n${C_BLUE}⚙️  $1${C_RESET}"; }
function print_info() { echo -e "${C_YELLOW}   ℹ️  $1${C_RESET}"; }
function print_success() { echo -e "${C_GREEN}   ✅ $1${C_RESET}"; }
function print_error() { echo -e "${C_RED}   ❌ $1${C_RESET}"; }
function print_warning() { echo -e "${C_YELLOW}   ⚠️  $1${C_RESET}"; }


# --- Helpers ---
wait_for() {
    local seconds=${1:-10}
    local i
    for ((i=0; i<seconds; i++)); do
        echo -n "."; sleep 1
    done
    echo
}

ensure_homebrew() {
    if command -v brew &> /dev/null; then
        return
    fi
    print_info "Homebrew not found."
    read -p "Install Homebrew now? (y/n) " hb
    [[ "$hb" == "y" || "$hb" == "Y" ]] || { print_info "Skipping install."; return 1; }
    print_step "Installing Homebrew..."
    (
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ) &
    tell_jokes $!
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
}

ensure_brew_pkg() {
    local formula=$1
    local bin_hint=${2:-}
    if [[ -n "$bin_hint" ]] && command -v "$bin_hint" &> /dev/null; then
        return
    fi
    if brew list --formula "$formula" &> /dev/null; then
        return
    fi
    print_step "Installing $formula..."
    brew install "$formula"
}

dnsmasq_stop() {
    sudo brew services stop dnsmasq > /dev/null 2>&1 || true
}

dnsmasq_start() {
    ensure_homebrew || return 1
    ensure_brew_pkg dnsmasq dnsmasq
    local conf
    conf="$(brew --prefix)/etc/dnsmasq.conf"
    echo "listen-address=127.0.0.1" > "$conf"
    echo "server=127.0.0.1#${HOST_DNS_PORT}" >> "$conf"
    sudo brew services start dnsmasq > /dev/null
    # readiness
    local tries=$DNS_READY_RETRIES
    while (( tries > 0 )); do
        if nslookup -timeout=1 example.com 127.0.0.1 &> /dev/null; then
            return 0
        fi
        sleep 1; tries=$((tries-1))
    done
    return 1
}

function install_dependencies() {
    ensure_homebrew || { print_error "Homebrew required."; exit 1; }

    # Sanity: brew architecture
    ARCH=$(uname -m)
    BREW_PATH=$(which brew)
    if [[ "$ARCH" == "arm64" && "$BREW_PATH" == "/usr/local/bin/brew" ]]; then
        print_error "Intel Homebrew detected on Apple Silicon. Reinstall native Homebrew."
        exit 1
    fi

    # dnsmasq (proxy)
    ensure_brew_pkg dnsmasq dnsmasq

    # Docker Desktop
    if [ ! -d "/Applications/Docker.app" ]; then
        print_step "Installing Docker Desktop..."
        print_info "Docker Desktop is not installed."
        echo ""
        echo "What would you like to do?"
        echo "  1) Install Docker via Homebrew (Recommended)"
        echo "  2) Open Docker website for manual installation"
        read -p "Enter your choice [1-2]: " choice
        if [[ "$choice" == "1" ]]; then
            print_info "Installing Docker via Homebrew..."
            if brew install --cask docker; then
                print_success "Docker Desktop installed."
                print_info "Open Docker once to finish setup, then re-run the wizard."
                read -p "Open Docker now? (y/n) " open_choice
                [[ "$open_choice" == "y" || "$open_choice" == "Y" ]] && open -a "Docker"
                exit 0
            else
                print_error "Docker install failed."
                open "https://www.docker.com/products/docker-desktop/" || true
                exit 1
            fi
        else
            open "https://www.docker.com/products/docker-desktop/" || true
            exit 1
        fi
    fi
}

function check_dependencies() {
    # Basic deps: Docker + dnsmasq
    if [ ! -d "/Applications/Docker.app" ] || ! command -v dnsmasq &> /dev/null; then
        install_dependencies
    fi

    # Docker daemon up?
    if ! docker info &> /dev/null; then
        print_info "Docker daemon is not running. Attempting to start Docker Desktop..."
        if ! open -a "Docker"; then
            print_error "Failed to open Docker.app."
            print_info "Please ensure Docker is in /Applications and try again."
            exit 1
        fi
        echo -n "Waiting for Docker to initialize..."
        local timeout=60
        local elapsed=0
        while ! docker info &> /dev/null; do
            if [ $elapsed -ge $timeout ]; then
                echo ""
                print_error "Timed out waiting for Docker."
                exit 1
            fi
            echo -n "."
            sleep 8
            elapsed=$((elapsed + 8))
        done
        print_success "\nDocker started."
    fi
}

function tell_jokes() {
    local pid_to_watch=${1:-} # Optional PID for monitoring a process

    local jokes=(
        "Why don't scientists trust atoms? Because they make up everything!"
        "I told my computer I needed a break... now it won't stop sending me Kit-Kat ads."
        "Why was the JavaScript developer sad? Because he didn't Node how to express himself."
        "There are 10 types of people in the world: those who understand binary, and those who don't."
        "Why did the programmer quit his job? He didn't get arrays."
    )

    # If no PID is provided, run in standalone joke mode.
    if [ -z "$pid_to_watch" ]; then
        clear
        echo "Entering Joke Mode..."
        echo "A new joke will appear every 8 seconds."
        echo "Press [CTRL+C] to exit."
        echo ""
        while true; do
            echo -e "${jokes[$RANDOM % ${#jokes[@]}]}\n"
            sleep 8
        done
    # If a PID is provided, monitor the process and tell jokes.
    else
        while ps -p "$pid_to_watch" > /dev/null; do
            sleep 8
            if ps -p "$pid_to_watch" > /dev/null; then
                echo -e "\n\n(Still working... here's a joke)\n${jokes[$RANDOM % ${#jokes[@]}]}"
            fi
        done
    fi
}


function find_active_network_service() {
    # Default route interface -> service name
    local interface
    interface=$(route -n get default | grep 'interface:' | awk '{print $2}')
    if [ -z "$interface" ]; then
        print_error "Couldn't find primary interface."
        exit 1
    fi
    networksetup -listallhardwareports | awk -v iface="$interface" '
        $1 == "Hardware" && $2 == "Port:" { port=$3 }
        $1 == "Device:" && $2 == iface { print port }'
}


function add_host_entry() {
    # Add a hosts file entry to map the custom hostname to localhost.
    # Requires sudo.
    if ! grep -q "127.0.0.1 $PIHOLE_HOSTNAME" /etc/hosts; then
        print_info "Sudo password required to map '$PIHOLE_HOSTNAME' to 127.0.0.1 in /etc/hosts"
        echo "127.0.0.1 $PIHOLE_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
        print_success "Host entry added."
    fi
}

function remove_host_entry() {
    # Remove the hosts file entry.
    # Requires sudo.
    if grep -q "127.0.0.1 $PIHOLE_HOSTNAME" /etc/hosts; then
        print_info "Sudo password required to remove '$PIHOLE_HOSTNAME' from /etc/hosts"
        sudo sed -i.bak "/127.0.0.1 $PIHOLE_HOSTNAME/d" /etc/hosts
        # Clean up the backup file created by sed.
        sudo rm -f /etc/hosts.bak
        print_success "Host entry removed."
    fi
}


# --- UI / Menu ---
function main_menu() {
    clear
    echo "
 ▗▄▄▖   █  ▗▖        ▗▄▖            ▗▖                  ▗▄▖  
 ▐▛▀▜▖  ▀  ▐▌        ▝▜▌            ▐▌                  ▝▜▌  
 ▐▌ ▐▌ ██  ▐▙██▖ ▟█▙  ▐▌   ▟█▙      ▐▌    ▟█▙  ▟██▖ ▟██▖ ▐▌  
 ▐██▛   █  ▐▛ ▐▌▐▛ ▜▌ ▐▌  ▐▙▄▟▌     ▐▌   ▐▛ ▜▌▐▛  ▘ ▘▄▟▌ ▐▌  
 ▐▌     █  ▐▌ ▐▌▐▌ ▐▌ ▐▌  ▐▛▀▀▘     ▐▌   ▐▌ ▐▌▐▌   ▗█▀▜▌ ▐▌
 ▐▌   ▗▄█▄▖▐▌ ▐▌▝█▄█▘ ▐▙▄ ▝█▄▄▌  █  ▐▙▄▄▖▝█▄█▘▝█▄▄▌▐▙▄█▌ ▐▙▄ 
 ▝▘   ▝▀▀▀▘▝▘ ▝▘ ▝▀▘   ▀▀  ▝▀▀   ▀  ▝▀▀▀▘ ▝▀▘  ▝▀▀  ▀▀▝▘  ▀▀ 
     "
    echo "Install Pi-hole for your machine and your machine ONLY!"
    echo "========================================================"
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  1) Install/Start Pi-hole"
    echo "  2) Stop Pi-hole"
    echo "  3) Uninstall Pi-hole"
    echo "  4) Watch a movie"
    echo "  5) Exit"
    echo ""
    read -p "Enter your choice [1-5]: " choice

    case $choice in
        1)
            install_or_start_pihole
            ;;
        2)
            stop_pihole
            ;;
        3)
            uninstall_pihole
            ;;
        4)
            watch_movie
            ;;
        5)
            echo "Exiting."
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please try again."
            sleep 2
            main_menu
            ;;
    esac
}


# --- Command Functions ---

function install_or_start_pihole() {
    # Kill any dnsmasq first
    dnsmasq_stop

    print_step "Checking dependencies..."
    check_dependencies

    # Check if a container already exists.
    if [ "$(docker ps -a -q -f name=$CONTAINER_NAME)" ]; then
        # If running, offer to test or exit.
        if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
            print_success "Pi-hole is already running."
            echo ""
            echo "What would you like to do?"
            echo "  1) Run verification test"
            echo "  2) Exit"
            read -p "Enter your choice [1-2]: " choice
            if [[ "$choice" == "1" ]]; then
                verify_pihole
            fi
            return
        fi

        # Remove stopped containers to ensure a clean start with correct port mappings.
        # User data is preserved in the mounted volume.
        print_warning "Found a stopped Pi-hole container. This might be from a previous or failed run."
        print_info "Removing it to create a fresh one with the correct settings..."
        docker rm "$CONTAINER_NAME" > /dev/null
        print_success "Old container removed. Proceeding with fresh installation..."
    fi

    # If we've reached this point, no container existed or a stale one was removed.
    print_step "Starting New Pi-hole Installation..."

    # Prompt for Upstream DNS
    echo ""
    echo "Please choose your upstream DNS provider:"
    echo "  1) Google (8.8.8.8, 8.8.4.4)"
    echo "  2) Cloudflare (1.1.1.1, 1.0.0.1)"
    echo "  3) OpenDNS (208.67.222.222, 208.67.220.220)"
    read -p "Enter your choice [1-3]: " dns_choice
    case $dns_choice in
        1) DNS1="8.8.8.8"; DNS2="8.8.4.4" ;;
        2) DNS1="1.1.1.1"; DNS2="1.0.0.1" ;;
        3) DNS1="208.67.222.220"; DNS2="208.67.220.220" ;;
        *) print_warning "Invalid choice. Defaulting to Google."; DNS1="8.8.8.8"; DNS2="8.8.4.4" ;;
    esac

    # Configure network settings
    print_step "Configuring Network Settings..."
    ACTIVE_SERVICE=$(find_active_network_service)
    print_info "Found active service: $ACTIVE_SERVICE"
    print_info "Backing up current DNS settings..."
    mkdir -p "$CONFIG_DIR"
    CURRENT_DNS=$(networksetup -getdnsservers "$ACTIVE_SERVICE")
    echo "$CURRENT_DNS" > "$DNS_BACKUP_FILE"
    print_success "DNS settings backed up to $DNS_BACKUP_FILE"

    # Get macOS Timezone for container logs
    TIMEZONE=$(readlink /etc/localtime | sed 's#/var/db/timezone/zoneinfo/##')

    # Deploy the Pi-hole Docker container.
    # docker run with DNS published to localhost:5053
    print_step "Deploying Pi-hole container..."
    dnsmasq_stop
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p 127.0.0.1:${HOST_DNS_PORT}:53/tcp \
        -p 127.0.0.1:${HOST_DNS_PORT}:53/udp \
        -p 127.0.0.1:80:80 \
        -e FTLCONF_webserver_api_password="$WEBPASSWORD" \
        -e FTLCONF_dns_listeningMode=all \
        -e TZ="$TIMEZONE" \
        -e DNS1="$DNS1" \
        -e DNS2="$DNS2" \
        -v "${CONFIG_DIR}/etc-pihole/:/etc/pihole/" \
        -v "${CONFIG_DIR}/etc-dnsmasq.d/:/etc/dnsmasq.d/" \
        --restart=unless-stopped \
        pihole/pihole:latest > /dev/null

    echo -n "Waiting for Pi-hole to be ready"; wait_for 24

    # dns proxy -> Pi-hole on ${HOST_DNS_PORT}
    print_step "Starting local DNS proxy..."
    if dnsmasq_start; then
        print_success "DNS proxy started."
    else
        print_error "dnsmasq did not become ready."
        docker stop "$CONTAINER_NAME" > /dev/null
        docker rm "$CONTAINER_NAME" > /dev/null
        exit 1
    fi

    # Apply system network changes
    add_host_entry
    networksetup -setdnsservers "$ACTIVE_SERVICE" "127.0.0.1"
    print_success "Local DNS set to use Pi-hole at 127.0.0.1"

    echo ""
    print_success "-----------------------------------------------------"
    print_success "Pi-hole is now running and blocking ads!"
    print_info "Admin URL:  http://$PIHOLE_HOSTNAME/admin/"
    print_info "Password:   $WEBPASSWORD"
    print_success "-----------------------------------------------------"

    echo ""
    read -p "Would you like to run a quick test to verify ad-blocking? (y/n) " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        verify_pihole
    fi
}

# Reverts network settings without verbose output. Called by stop and uninstall.
function _revert_network_settings() {
    # Stop proxy
    dnsmasq_stop
    # Restore DNS
    if [ -f "$DNS_BACKUP_FILE" ]; then
        local active_service
        active_service=$(find_active_network_service)
        local original_dns
        original_dns=$(cat "$DNS_BACKUP_FILE")
        if [ -z "$original_dns" ] || [[ "$original_dns" == *"There aren't any DNS Servers"* ]]; then
            networksetup -setdnsservers "$active_service" "Empty"
        else
            local dns_servers_to_set
            dns_servers_to_set=$(echo "$original_dns" | tr '\n' ' ')
            networksetup -setdnsservers "$active_service" $dns_servers_to_set
        fi
    fi
    # Hosts cleanup
    if grep -q "127.0.0.1 $PIHOLE_HOSTNAME" /etc/hosts; then
        print_info "Sudo password required to remove '$PIHOLE_HOSTNAME' from /etc/hosts"
        sudo sed -i.bak "/127.0.0.1 $PIHOLE_HOSTNAME/d" /etc/hosts
        sudo rm -f /etc/hosts.bak
    fi
}

function stop_pihole() {
    print_step "Stopping Pi-hole..."
    echo ""

    if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
        echo "   - Stopping Docker container..."
        docker stop "$CONTAINER_NAME" > /dev/null
    fi

    echo "   - Reverting network settings..."
    _revert_network_settings

    echo ""
    print_success "Pi-hole has been stopped. Your container and configs are preserved."
}

function uninstall_pihole() {
    print_step "Uninstalling Pi-hole completely..."
    echo ""

    # Stop container if running
    if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
        echo "   - Stopping container..."
        docker stop "$CONTAINER_NAME" > /dev/null
    fi

    # Revert network settings
    echo "   - Reverting network settings..."
    _revert_network_settings

    echo ""

    # Remove all assets
    print_info "Removing all Pi-hole assets..."
    if [ "$(docker ps -a -q -f name=$CONTAINER_NAME)" ]; then
        echo "   - Removing Docker container..."
        docker rm "$CONTAINER_NAME" > /dev/null
    fi
    if [ -d "$CONFIG_DIR" ]; then
        echo "   - Removing configuration directory..."
        rm -rf "$CONFIG_DIR"
    fi

    echo ""
    print_success "Pi-hole has been completely uninstalled."
}

function preflight_check() {
    local ip_to_check=$1
    print_step "Running Pre-Flight Network Check..."
    print_info "Pinging Google's DNS to ensure general internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "Cannot reach the internet. Please check your network connection."
        exit 1
    fi
    print_success "Internet connection is active."

    print_info "Attempting to communicate with Pi-hole container at $ip_to_check..."
    # Use nslookup with an explicit server and a short timeout.
    if ! nslookup -timeout=5 google.com "$ip_to_check" &> /dev/null; then
        print_error "Pre-flight check failed: Your Mac cannot communicate with the Pi-hole container."
        print_info "This is a Docker networking issue. The script will now stop and clean up to avoid breaking your internet."
        # Clean up the container we just created.
        docker stop "$CONTAINER_NAME" > /dev/null
        docker rm "$CONTAINER_NAME" > /dev/null
        exit 1
    fi
    print_success "Successfully communicated with the Pi-hole container."
}


function verify_pihole() {
    print_step "Running verification test..."
    
    # 1) General network connectivity
    print_info "Checking internet connectivity (ping 8.8.8.8)..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_error "Internet connectivity check failed."
        print_info "Try 'Stop Pi-hole' to revert DNS and confirm your network is working, then install again."
        return
    fi
    print_success "Internet is reachable."

    # 2) Basic DNS via local proxy
    print_info "Testing DNS proxy responsiveness (example.com via 127.0.0.1)..."
    local dns_ok=false
    if nslookup -timeout=2 example.com 127.0.0.1 &> /dev/null; then
        dns_ok=true
    else
        print_warning "DNS proxy didn't respond. Restarting..."
        sudo brew services restart dnsmasq > /dev/null 2>&1 || true
        # readiness
        local tries=$DNS_READY_RETRIES
        while (( tries > 0 )); do
            if nslookup -timeout=1 example.com 127.0.0.1 &> /dev/null; then
                dns_ok=true; break
            fi
            sleep 1; tries=$((tries-1))
        done
    fi
    if [ "$dns_ok" != true ]; then
        print_error "DNS proxy on 127.0.0.1:53 is not responding."
        print_info "Check for port conflicts on 53 and try again."
        return
    fi
    print_success "DNS proxy is responding."

    # 3) Ad domain block verification
    print_info "Looking up doubleclick.net via 127.0.0.1..."
    local result
    result=$(nslookup -timeout=2 doubleclick.net 127.0.0.1 2>&1 || true)

    if [[ "$result" == *";; connection timed out;"* ]]; then
        print_error "Verification failed: DNS queries timed out."
        return
    fi

    if echo "$result" | grep -q "Address: 0.0.0.0" || echo "$result" | grep -qi "address: 127.0.0.1"; then
        print_success "Success! Blocking works."
    else
        print_warning "Pi-hole responded but the ad domain wasn't blocked."
        print_info "Open http://$PIHOLE_HOSTNAME/admin to review blocklists."
        print_info "Full lookup output:"; echo "$result"
    fi
}

function watch_movie() {
    print_step "Launching Star Wars (SSH)…"
    print_info "Press Ctrl+C to exit."

    if ! command -v ssh &> /dev/null; then
        print_warning "OpenSSH not found."
        read -p "Install OpenSSH now? (y/n) " choice
        if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
            print_info "Skipping movie."
            return
        fi
        ensure_homebrew || { print_error "Homebrew required."; return; }
        ensure_brew_pkg openssh ssh || { print_error "OpenSSH install failed."; return; }
    fi

    ssh -o ConnectTimeout=15 starwarstel.net || print_error "SSH failed. Try again later or run: ssh starwarstel.net"
}


# --- Main Execution ---
main_menu

exit 0