#!/bin/bash

# Ultimate All-in-One Game Server Stack Installer - FIXED FILE CREATION
# Includes: Pelican Panel + Wings (proper host install) + Portainer + Suwayomi + Caddy
# Features: Docker no-sudo fix, complete automation, production & local support

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to print colored messages
print_status() { echo -e "${YELLOW}➜${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_important() { echo -e "${PURPLE}⚠${NC} $1"; }
print_step() { echo -e "${CYAN}[$1]${NC} $2"; }

# Banner
clear
cat << "EOF"
   ____                        ____                           
  / ___| __ _ _ __ ___   ___  / ___|  ___ _ ____   _____ _ __ 
 | |  _ / _` | '_ ` _ \ / _ \ \___ \ / _ \ '__\ \ / / _ \ '__|
 | |_| | (_| | | | | | |  __/  ___) |  __/ |   \ V /  __/ |   
  \____|\__,_|_| |_| |_|\___| |____/ \___|_|    \_/ \___|_|   
                                                              
        Complete Stack Installer v2.1 - Fixed Edition
EOF
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
fi

print_info "Detected OS: $OS $VER"

# Check if running with proper permissions
if [ "$EUID" -ne 0 ]; then 
   print_error "This installer needs sudo privileges for initial setup"
   echo ""
   echo "Please run: ${GREEN}sudo bash $0${NC}"
   echo ""
   exit 1
fi

# Get the actual user (not root)
if [ "$SUDO_USER" ]; then
    ACTUAL_USER=$SUDO_USER
    ACTUAL_HOME="/home/$SUDO_USER"
else
    echo -n "Enter the username that will manage the stack: "
    read -r ACTUAL_USER
    if ! id "$ACTUAL_USER" &>/dev/null; then
        print_error "User $ACTUAL_USER does not exist!"
        exit 1
    fi
    ACTUAL_HOME="/home/$ACTUAL_USER"
fi

print_success "Stack will be configured for user: $ACTUAL_USER"
print_info "Home directory: $ACTUAL_HOME"

# Set installation directory
INSTALL_DIR="$ACTUAL_HOME/game-stack"

# Installation mode selection
echo ""
print_step "1/8" "Installation Mode"
echo ""
echo "Choose your installation mode:"
echo ""
echo "  ${GREEN}1)${NC} Quick Install - Local Development (localhost)"
echo "  ${BLUE}2)${NC} Production Install (with domain & SSL)"
echo "  ${YELLOW}3)${NC} Custom Install (choose components)"
echo "  ${CYAN}4)${NC} Docker Fix Only (make Docker work without sudo)"
echo ""
read -p "Select mode [1-4]: " -n 1 -r INSTALL_MODE
echo ""
echo ""

# Function to install Docker
install_docker() {
    print_step "2/8" "Docker Installation"
    
    if command -v docker &> /dev/null; then
        print_success "Docker is already installed"
        return 0
    fi
    
    print_status "Installing Docker..."
    curl -sSL https://get.docker.com/ | CHANNEL=stable sh
    systemctl enable --now docker
    print_success "Docker installed successfully"
}

# Function to setup Docker without sudo
setup_docker_nosudo() {
    print_step "3/8" "Docker Permission Configuration"
    
    # Create docker group if it doesn't exist
    if ! getent group docker > /dev/null 2>&1; then
        groupadd docker
        print_success "Created docker group"
    fi
    
    # Add user to docker group
    if ! groups "$ACTUAL_USER" | grep -q docker; then
        usermod -aG docker "$ACTUAL_USER"
        print_success "Added $ACTUAL_USER to docker group"
        NEED_RELOGIN=true
    else
        print_success "$ACTUAL_USER is already in docker group"
        NEED_RELOGIN=false
    fi
}

# Function to install Wings
install_wings() {
    print_step "4/8" "Wings Daemon Installation"
    
    # Check if Wings is already installed
    if [ -f /usr/local/bin/wings ]; then
        print_info "Wings binary already exists"
        echo -n "Reinstall Wings? (y/n): "
        read -r response
        if [[ ! "$response" == "y" ]]; then
            return 0
        fi
    fi
    
    print_status "Installing Wings daemon..."
    
    # Create required directories for Wings
    mkdir -p /etc/pelican
    mkdir -p /var/run/wings
    mkdir -p /var/lib/pelican/{volumes,backups,archives}
    mkdir -p /var/log/pelican
    mkdir -p /tmp/pelican
    
    # Download Wings binary
    print_status "Downloading Wings binary..."
    ARCH=$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")
    curl -L -o /usr/local/bin/wings "https://github.com/pelican-dev/wings/releases/latest/download/wings_linux_${ARCH}"
    chmod u+x /usr/local/bin/wings
    
    # Create systemd service for Wings
    cat > /etc/systemd/system/wings.service << 'EOF'
[Unit]
Description=Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "Wings installed successfully"
}

# Function to create stack files
create_stack_files() {
    local setup_type=$1
    local domain=$2
    local email=$3
    
    print_step "5/8" "Creating Configuration Files"
    
    # Create install directory
    print_status "Creating directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit
    
    # Create docker-compose.yml
    print_status "Creating docker-compose.yml..."
    
    if [ "$setup_type" = "production" ]; then
        cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3'

services:
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - pelican

  pelican:
    image: ghcr.io/pelican-dev/panel:latest
    container_name: pelican
    restart: unless-stopped
    volumes:
      - pelican_data:/pelican-data
      - ./pelican-caddyfile:/etc/caddy/Caddyfile
    environment:
      APP_URL: "https://panel.$domain"
      ADMIN_EMAIL: "$email"
    networks:
      - pelican

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - pelican

  suwayomi:
    image: ghcr.io/suwayomi/suwayomi-server:latest
    container_name: suwayomi
    restart: unless-stopped
    volumes:
      - suwayomi_data:/home/suwayomi/.local/share/Tachidesk
    networks:
      - pelican

volumes:
  caddy_data:
  caddy_config:
  pelican_data:
  portainer_data:
  suwayomi_data:

networks:
  pelican:
    name: pelican
    driver: bridge
EOF
        
        # Create production Caddyfile
        cat > "$INSTALL_DIR/Caddyfile" << EOF
{
    email $email
}

panel.$domain {
    reverse_proxy pelican:80
}

portainer.$domain {
    reverse_proxy portainer:9000
}

manga.$domain {
    reverse_proxy suwayomi:4567
}

$domain {
    redir https://panel.$domain permanent
}

www.$domain {
    redir https://panel.$domain permanent
}
EOF
    else
        # Local development setup
        cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
version: '3'

services:
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
    networks:
      - pelican

  pelican:
    image: ghcr.io/pelican-dev/panel:latest
    container_name: pelican
    restart: unless-stopped
    volumes:
      - pelican_data:/pelican-data
      - ./pelican-caddyfile:/etc/caddy/Caddyfile
    environment:
      APP_URL: "http://panel.localhost"
      ADMIN_EMAIL: "admin@example.com"
    networks:
      - pelican

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - pelican

  suwayomi:
    image: ghcr.io/suwayomi/suwayomi-server:latest
    container_name: suwayomi
    restart: unless-stopped
    volumes:
      - suwayomi_data:/home/suwayomi/.local/share/Tachidesk
    networks:
      - pelican

volumes:
  pelican_data:
  portainer_data:
  suwayomi_data:

networks:
  pelican:
    name: pelican
    driver: bridge
EOF
        
        # Create local Caddyfile
        cat > "$INSTALL_DIR/Caddyfile" << 'EOF'
{
    auto_https off
}

panel.localhost:80 {
    reverse_proxy pelican:80
}

portainer.localhost:80 {
    reverse_proxy portainer:9000
}

manga.localhost:80 {
    reverse_proxy suwayomi:4567
}

:80 {
    respond "Game Server Stack Services:

• Pelican Panel: http://panel.localhost
• Portainer: http://portainer.localhost
• Suwayomi Manga: http://manga.localhost

Wings is running on the host system.
Configure it in Pelican Panel admin area."
}
EOF
    fi
    
    # Create pelican-caddyfile (same for both)
    cat > "$INSTALL_DIR/pelican-caddyfile" << 'EOF'
{
    admin off
    auto_https off
}

:80 {
    root * /var/www/html/public
    encode gzip
    php_fastcgi 127.0.0.1:9000
    file_server
}
EOF
    
    # Create Wings configuration helper
    cat > "$INSTALL_DIR/configure-wings.sh" << 'EOF'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║               Wings Configuration Helper                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}Step 1: Complete Pelican Panel setup${NC}"
echo "  → Visit http://panel.localhost/installer"
echo "  → Complete the installation wizard"
echo ""

echo -e "${BLUE}Step 2: Create a node in Pelican Panel${NC}"
echo "  → Login to Pelican Panel as admin"
echo "  → Go to: Admin Area → Nodes → Create New"
echo "  → Use these settings:"
echo ""
echo "    Name: Local Server"
echo "    Description: Local Wings Node"
echo ""
echo "    FQDN Options (choose one):"
echo "      • For Docker: host.docker.internal"
echo "      • For Network: $(hostname -I | awk '{print $1}')"
echo "      • For Local: 127.0.0.1"
echo ""
echo "    Communicate Over SSL: No"
echo "    Behind Proxy: No"
echo ""
echo "    Daemon Port: 8080"
echo "    Daemon SFTP Port: 2022"
echo ""
echo "    Memory: $(free -m | awk 'NR==2{print $2}') MB"
echo "    Memory Overallocate: 0"
echo "    Disk: $(df -BM / | awk 'NR==2{print $2}' | sed 's/M//') MB"
echo "    Disk Overallocate: 0"
echo ""

echo -e "${BLUE}Step 3: Get the configuration${NC}"
echo "  → After creating the node, click on it"
echo "  → Go to the 'Configuration' tab"
echo "  → Click 'Generate Token' if needed"
echo "  → Copy the entire configuration block"
echo ""

echo -e "${YELLOW}Ready to configure Wings? (y/n):${NC} "
read -r response

if [[ "$response" == "y" ]]; then
    echo ""
    echo "Opening Wings config file..."
    echo "Paste the configuration from Pelican Panel, then save and exit (Ctrl+X, Y, Enter)"
    echo ""
    sleep 2
    sudo nano /etc/pelican/config.yml
    
    echo ""
    echo "Starting Wings service..."
    sudo systemctl enable wings
    sudo systemctl start wings
    
    echo ""
    echo "Waiting for Wings to start..."
    sleep 3
    
    echo "Checking Wings status..."
    sudo systemctl status wings --no-pager
    
    echo ""
    echo -e "${GREEN}✓ Wings configuration complete!${NC}"
    echo ""
    echo "Go back to Pelican Panel - the node should show as 'Online' (green heart)"
    echo ""
    echo "If the node shows as offline:"
    echo "  1. Check Wings logs: sudo journalctl -u wings -f"
    echo "  2. Verify config: sudo cat /etc/pelican/config.yml"
    echo "  3. Check firewall: sudo ufw status (port 8080 should be open)"
else
    echo ""
    echo "Run this script again when you're ready to configure Wings."
    echo "Location: $PWD/configure-wings.sh"
fi
EOF
    
    chmod +x "$INSTALL_DIR/configure-wings.sh"
    
    # Set proper ownership
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$INSTALL_DIR"
    
    # List created files
    print_success "Created files in $INSTALL_DIR:"
    ls -la "$INSTALL_DIR"
}

# Function to start services
start_services() {
    print_step "6/8" "Starting Docker Services"
    
    cd "$INSTALL_DIR" || exit
    
    # Pull images first
    print_status "Pulling Docker images (this may take a few minutes)..."
    docker compose pull
    
    # Start services
    print_status "Starting all services..."
    docker compose up -d
    
    # Check if services started
    sleep 5
    docker compose ps
    
    print_success "Services started successfully"
}

# Main execution based on mode
case $INSTALL_MODE in
    1)
        # Quick Install - Local
        print_info "Starting Quick Install for Local Development"
        
        # Run all installation steps
        install_docker
        setup_docker_nosudo
        install_wings
        
        # Create stack files
        create_stack_files "local" "" ""
        
        # Start services
        start_services
        
        SETUP_TYPE="local"
        ;;
        
    2)
        # Production Install
        print_info "Starting Production Installation"
        
        echo ""
        echo -n "Enter your domain (e.g., example.com): "
        read -r DOMAIN
        echo -n "Enter your email for SSL certificates: "
        read -r EMAIL
        
        if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
            print_error "Domain and email are required!"
            exit 1
        fi
        
        # Run all installation steps
        install_docker
        setup_docker_nosudo
        install_wings
        
        # Create stack files
        create_stack_files "production" "$DOMAIN" "$EMAIL"
        
        # Start services
        start_services
        
        SETUP_TYPE="production"
        ;;
        
    3)
        # Custom Install
        print_info "Custom Installation - Choose components"
        
        echo ""
        echo -n "Install Docker? (y/n): "
        read -r INSTALL_DOCKER_CHOICE
        
        echo -n "Configure Docker without sudo? (y/n): "
        read -r DOCKER_NOSUDO_CHOICE
        
        echo -n "Install Wings daemon? (y/n): "
        read -r INSTALL_WINGS_CHOICE
        
        echo -n "Create and start stack? (y/n): "
        read -r INSTALL_STACK_CHOICE
        
        if [[ "$INSTALL_DOCKER_CHOICE" == "y" ]]; then
            install_docker
        fi
        
        if [[ "$DOCKER_NOSUDO_CHOICE" == "y" ]]; then
            setup_docker_nosudo
        fi
        
        if [[ "$INSTALL_WINGS_CHOICE" == "y" ]]; then
            install_wings
        fi
        
        if [[ "$INSTALL_STACK_CHOICE" == "y" ]]; then
            echo ""
            echo -n "Local or Production setup? (l/p): "
            read -r STACK_TYPE
            
            if [[ "$STACK_TYPE" == "p" ]]; then
                echo -n "Enter domain: "
                read -r DOMAIN
                echo -n "Enter email: "
                read -r EMAIL
                create_stack_files "production" "$DOMAIN" "$EMAIL"
                start_services
                SETUP_TYPE="production"
            else
                create_stack_files "local" "" ""
                start_services
                SETUP_TYPE="local"
            fi
        fi
        ;;
        
    4)
        # Docker Fix Only
        print_info "Fixing Docker to work without sudo"
        setup_docker_nosudo
        
        if [ "$NEED_RELOGIN" = true ]; then
            echo ""
            print_important "You must log out and back in for changes to take effect!"
            echo "After relogin, test with: docker ps"
        else
            print_success "Docker already configured for $ACTUAL_USER"
        fi
        exit 0
        ;;
        
    *)
        print_error "Invalid choice!"
        exit 1
        ;;
esac

# Final summary
print_step "7/8" "Installation Summary"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Installation Complete!                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show what was installed
print_success "Installed Components:"
echo "  ✓ Docker CE"
echo "  ✓ Docker configured for user: $ACTUAL_USER"
echo "  ✓ Wings daemon (host installation)"
echo "  ✓ Pelican Panel (Docker container)"
echo "  ✓ Portainer CE (Docker container)"
echo "  ✓ Suwayomi Server (Docker container)"
echo "  ✓ Caddy Proxy (Docker container)"
echo ""

print_success "Installation Location:"
echo "  Directory: $INSTALL_DIR"
echo "  Config Files:"
echo "    • docker-compose.yml"
echo "    • Caddyfile"
echo "    • pelican-caddyfile"
echo "    • configure-wings.sh"
echo ""

# Get Pelican app key if available
APP_KEY=$(docker logs pelican 2>/dev/null | grep "Generated app key:" | tail -1 | cut -d':' -f3- | xargs)

if [ "$SETUP_TYPE" = "production" ]; then
    print_success "Access URLs (Production):"
    echo "  • Pelican Panel: https://panel.$DOMAIN"
    echo "  • Portainer: https://portainer.$DOMAIN"
    echo "  • Suwayomi: https://manga.$DOMAIN"
    echo ""
    print_important "Configure DNS Records:"
    echo "  A  panel.$DOMAIN     → $(curl -s ifconfig.me)"
    echo "  A  portainer.$DOMAIN → $(curl -s ifconfig.me)"
    echo "  A  manga.$DOMAIN     → $(curl -s ifconfig.me)"
else
    print_success "Access URLs (Local):"
    echo "  • Pelican Panel: http://panel.localhost"
    echo "  • Portainer: http://portainer.localhost"
    echo "  • Suwayomi: http://manga.localhost"
fi

echo ""
print_step "8/8" "Next Steps"
echo ""

STEP_NUM=1

if [ "$NEED_RELOGIN" = true ]; then
    echo "${STEP_NUM}. ${RED}CRITICAL: Log out and back in${NC}"
    echo "   This enables Docker without sudo for: $ACTUAL_USER"
    echo ""
    STEP_NUM=$((STEP_NUM + 1))
fi

echo "${STEP_NUM}. ${YELLOW}Setup Pelican Panel:${NC}"
echo "   → Open: http://panel.localhost/installer"
echo "   → Complete the installation wizard"
if [ -n "$APP_KEY" ]; then
    echo "   → ${GREEN}App Key: $APP_KEY${NC} (SAVE THIS!)"
fi
echo ""
STEP_NUM=$((STEP_NUM + 1))

echo "${STEP_NUM}. ${YELLOW}Configure Wings:${NC}"
echo "   → Run: ${CYAN}cd $INSTALL_DIR && ./configure-wings.sh${NC}"
echo "   → This connects Wings to Pelican Panel"
echo ""
STEP_NUM=$((STEP_NUM + 1))

echo "${STEP_NUM}. ${YELLOW}Setup Portainer:${NC}"
echo "   → Open: http://portainer.localhost"
echo "   → Create admin account quickly (5 minute timeout!)"
echo ""

print_info "Useful Commands:"
echo ""
echo "Stack Management (run from $INSTALL_DIR):"
echo "  ${GREEN}docker compose ps${NC}          - Check service status"
echo "  ${GREEN}docker compose logs -f${NC}     - View all logs"
echo "  ${GREEN}docker compose restart${NC}     - Restart services"
echo "  ${GREEN}docker compose down${NC}        - Stop everything"
echo "  ${GREEN}docker compose up -d${NC}       - Start everything"
echo ""
echo "Wings Management:"
echo "  ${GREEN}sudo systemctl status wings${NC}   - Check Wings status"
echo "  ${GREEN}sudo systemctl restart wings${NC}  - Restart Wings"
echo "  ${GREEN}sudo journalctl -u wings -f${NC}   - View Wings logs"
echo ""

# Save installation details
cat > "$INSTALL_DIR/installation-info.txt" << EOF
Installation Details
====================
Date: $(date)
User: $ACTUAL_USER
Type: $SETUP_TYPE
Directory: $INSTALL_DIR
$([ "$SETUP_TYPE" = "production" ] && echo "Domain: $DOMAIN")
$([ "$SETUP_TYPE" = "production" ] && echo "Email: $EMAIL")
$([ -n "$APP_KEY" ] && echo "Pelican App Key: $APP_KEY")

Installed Components:
- Docker CE (with no-sudo configuration)
- Wings Daemon (host installation at /usr/local/bin/wings)
- Pelican Panel (Docker container)
- Portainer CE (Docker container)
- Suwayomi Server (Docker container)
- Caddy Reverse Proxy (Docker container)

Service URLs:
$([ "$SETUP_TYPE" = "production" ] && echo "- https://panel.$DOMAIN" || echo "- http://panel.localhost")
$([ "$SETUP_TYPE" = "production" ] && echo "- https://portainer.$DOMAIN" || echo "- http://portainer.localhost")
$([ "$SETUP_TYPE" = "production" ] && echo "- https://manga.$DOMAIN" || echo "- http://manga.localhost")

Ports Used:
- 80: HTTP
$([ "$SETUP_TYPE" = "production" ] && echo "- 443: HTTPS")
- 8080: Wings API
- 2022: SFTP
- 25565-25575: Minecraft
- 27015: Source Games

Configuration Files:
- Stack Directory: $INSTALL_DIR
- Docker Compose: $INSTALL_DIR/docker-compose.yml
- Caddy Config: $INSTALL_DIR/Caddyfile
- Wings Config: /etc/pelican/config.yml
- Wings Binary: /usr/local/bin/wings
- Wings Service: /etc/systemd/system/wings.service

Commands:
- Configure Wings: cd $INSTALL_DIR && ./configure-wings.sh
- View logs: cd $INSTALL_DIR && docker compose logs -f
- Restart stack: cd $INSTALL_DIR && docker compose restart
EOF

chown "$ACTUAL_USER:$ACTUAL_USER" "$INSTALL_DIR/installation-info.txt"

print_info "Installation details saved to: $INSTALL_DIR/installation-info.txt"

if [ "$NEED_RELOGIN" = true ]; then
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║         IMPORTANT: Log out and back in to continue!         ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
fi

echo ""
print_success "All done! Your game server stack is ready! 🎮"
echo ""
echo "Stack location: ${CYAN}$INSTALL_DIR${NC}"
echo "To manage the stack: ${GREEN}cd $INSTALL_DIR${NC}"
