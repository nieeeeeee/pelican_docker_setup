#!/bin/bash

# Ultimate Docker Stack Setup Script
# Includes: Pelican Panel + Wings + Portainer + Suwayomi + Caddy
# Works for both localhost and production domains

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored messages
print_status() { echo -e "${YELLOW}➜${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

# Banner
clear
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Complete Game Server Stack Installer            ║${NC}"
echo -e "${GREEN}║  Pelican + Wings + Portainer + Suwayomi + Caddy        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed!"
    echo "Install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if running as root (warn but don't stop)
if [ "$EUID" -eq 0 ]; then 
   print_info "Running as root - be careful!"
fi

# Setup type selection
echo "Choose your installation type:"
echo ""
echo "  1) ${GREEN}Local Development${NC} (localhost)"
echo "  2) ${BLUE}Production Server${NC} (with domain)"
echo "  3) ${YELLOW}Quick Local${NC} (no questions asked)"
echo ""
read -p "Enter choice [1-3]: " -n 1 -r
echo ""
echo ""

INSTALL_DIR="game-stack"
SETUP_TYPE=""
DOMAIN=""
EMAIL=""

case $REPLY in
    1)
        SETUP_TYPE="local"
        print_status "Setting up for local development..."
        ;;
    2)
        SETUP_TYPE="production"
        print_status "Setting up for production..."
        echo ""
        read -p "Enter your domain (e.g., example.com): " DOMAIN
        read -p "Enter your email for SSL certificates: " EMAIL
        
        if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
            print_error "Domain and email are required for production!"
            exit 1
        fi
        ;;
    3)
        SETUP_TYPE="quick"
        print_status "Quick local setup - here we go!"
        ;;
    *)
        print_error "Invalid choice!"
        exit 1
        ;;
esac

# Create and enter directory
print_status "Creating directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit

# Clean up any existing setup
if [ -f docker-compose.yml ]; then
    print_info "Found existing setup, backing up..."
    mv docker-compose.yml docker-compose.backup.$(date +%s).yml
fi

# Stop any existing containers
docker compose down 2>/dev/null || true

# Create docker-compose.yml
print_status "Creating docker-compose.yml..."

if [ "$SETUP_TYPE" = "production" ]; then
    cat > docker-compose.yml << EOF
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
      - web
    depends_on:
      - pelican
      - wings
      - portainer
      - suwayomi

  pelican:
    image: ghcr.io/pelican-dev/panel:latest
    container_name: pelican
    restart: unless-stopped
    volumes:
      - pelican-data:/pelican-data
      - ./pelican-caddyfile:/etc/caddy/Caddyfile
    environment:
      APP_URL: "https://panel.$DOMAIN"
      ADMIN_EMAIL: "$EMAIL"
    networks:
      - web

  wings:
    image: ghcr.io/pelican-dev/wings:latest
    container_name: wings
    restart: unless-stopped
    privileged: true
    ports:
      - "8080:8080"
      - "2022:2022"
      - "25565:25565"
      - "25566-25575:25566-25575"
      - "27015:27015"
      - "27015:27015/udp"
      - "7777-7780:7777-7780/udp"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - wings-config:/etc/pelican
      - wings-data:/var/lib/pelican
      - wings-logs:/var/log/pelican
      - /tmp/pelican:/tmp/pelican
    environment:
      WINGS_DEBUG: "false"
    networks:
      - web

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer-data:/data
    networks:
      - web

  suwayomi:
    image: ghcr.io/suwayomi/suwayomi-server:latest
    container_name: suwayomi
    restart: unless-stopped
    volumes:
      - suwayomi-data:/home/suwayomi/.local/share/Tachidesk
    networks:
      - web

volumes:
  caddy_data:
  caddy_config:
  pelican-data:
  wings-config:
  wings-data:
  wings-logs:
  portainer-data:
  suwayomi-data:

networks:
  web:
EOF

else
    # Local setup (both quick and interactive)
    cat > docker-compose.yml << 'EOF'
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
      - web
    depends_on:
      - pelican
      - wings
      - portainer
      - suwayomi

  pelican:
    image: ghcr.io/pelican-dev/panel:latest
    container_name: pelican
    restart: unless-stopped
    volumes:
      - pelican-data:/pelican-data
      - ./pelican-caddyfile:/etc/caddy/Caddyfile
    environment:
      APP_URL: "http://panel.localhost"
      ADMIN_EMAIL: "admin@example.com"
    networks:
      - web

  wings:
    image: ghcr.io/pelican-dev/wings:latest
    container_name: wings
    restart: unless-stopped
    privileged: true
    ports:
      - "8080:8080"
      - "2022:2022"
      - "25565:25565"
      - "25566-25575:25566-25575"
      - "27015:27015"
      - "27015:27015/udp"
      - "7777-7780:7777-7780/udp"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - wings-config:/etc/pelican
      - wings-data:/var/lib/pelican
      - wings-logs:/var/log/pelican
      - /tmp/pelican:/tmp/pelican
    environment:
      WINGS_DEBUG: "false"
    networks:
      - web

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer-data:/data
    networks:
      - web

  suwayomi:
    image: ghcr.io/suwayomi/suwayomi-server:latest
    container_name: suwayomi
    restart: unless-stopped
    volumes:
      - suwayomi-data:/home/suwayomi/.local/share/Tachidesk
    networks:
      - web

volumes:
  pelican-data:
  wings-config:
  wings-data:
  wings-logs:
  portainer-data:
  suwayomi-data:

networks:
  web:
EOF
fi

print_success "docker-compose.yml created"

# Create Caddyfile
print_status "Creating Caddyfile..."

if [ "$SETUP_TYPE" = "production" ]; then
    cat > Caddyfile << EOF
{
    email $EMAIL
}

panel.$DOMAIN {
    reverse_proxy pelican:80
}

wings.$DOMAIN {
    reverse_proxy wings:8080
}

portainer.$DOMAIN {
    reverse_proxy portainer:9000
}

manga.$DOMAIN {
    reverse_proxy suwayomi:4567
}

$DOMAIN {
    redir https://panel.$DOMAIN permanent
}

www.$DOMAIN {
    redir https://panel.$DOMAIN permanent
}
EOF
else
    cat > Caddyfile << 'EOF'
{
    auto_https off
}

panel.localhost:80 {
    reverse_proxy pelican:80
}

wings.localhost:80 {
    reverse_proxy wings:8080
}

portainer.localhost:80 {
    reverse_proxy portainer:9000
}

manga.localhost:80 {
    reverse_proxy suwayomi:4567
}

:80 {
    respond "Game Server Stack Running!
    
Services:
• Pelican Panel: http://panel.localhost
• Wings Node: http://wings.localhost
• Portainer: http://portainer.localhost
• Suwayomi Manga: http://manga.localhost

Game Server Ports:
• Minecraft: 25565-25575
• Source Games: 27015
• Other Games: 7777-7780
• SFTP: 2022"
}
EOF
fi

print_success "Caddyfile created"

# Create pelican-caddyfile
print_status "Creating Pelican Caddyfile override..."
cat > pelican-caddyfile << 'EOF'
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

print_success "Pelican Caddyfile created"

# Create Wings setup helper script
print_status "Creating Wings configuration helper..."
cat > configure-wings.sh << 'WINGS_SCRIPT'
#!/bin/bash

echo "Wings Configuration Helper"
echo "=========================="
echo ""
echo "After Pelican Panel is installed:"
echo "1. Go to Admin → Nodes → Create New"
echo "2. Use these settings:"
echo "   - Name: Local Node"
echo "   - FQDN: wings (or wings.localhost for external)"
echo "   - Daemon Port: 8080"
echo "   - SFTP Port: 2022"
echo ""
echo "3. Go to the node's Configuration tab"
echo "4. Copy the configuration"
echo "5. Run: docker exec -it wings sh"
echo "6. Run: vi /etc/pelican/config.yml"
echo "7. Paste the configuration and save"
echo "8. Exit and run: docker restart wings"
echo ""
echo "Press Enter when ready to configure Wings..."
read

echo "Opening Wings shell. Paste your config when ready..."
docker exec -it wings sh
WINGS_SCRIPT
chmod +x configure-wings.sh

print_success "Helper scripts created"

# Pull Docker images
print_status "Pulling Docker images (this may take a few minutes)..."
docker compose pull

# Start services
print_status "Starting all services..."
docker compose up -d

# Wait for services to initialize
print_status "Waiting for services to initialize..."
for i in {1..10}; do
    echo -n "."
    sleep 1
done
echo ""

# Check services status
print_status "Checking service status..."
docker compose ps

# Get Pelican app key if it exists
APP_KEY=$(docker compose logs pelican 2>/dev/null | grep "Generated app key:" | tail -1 | cut -d':' -f3 | xargs)

# Final output
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 Installation Complete!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$SETUP_TYPE" = "production" ]; then
    echo -e "${GREEN}Your services are available at:${NC}"
    echo "  • Pelican Panel: https://panel.$DOMAIN"
    echo "  • Wings Node: https://wings.$DOMAIN"
    echo "  • Portainer: https://portainer.$DOMAIN"
    echo "  • Suwayomi: https://manga.$DOMAIN"
    echo ""
    echo -e "${YELLOW}⚠ Make sure your DNS is configured:${NC}"
    echo "  A record: panel.$DOMAIN → Your Server IP"
    echo "  A record: wings.$DOMAIN → Your Server IP"
    echo "  A record: portainer.$DOMAIN → Your Server IP"
    echo "  A record: manga.$DOMAIN → Your Server IP"
else
    echo -e "${GREEN}Your services are available at:${NC}"
    echo "  • Pelican Panel: http://panel.localhost"
    echo "  • Wings Node: http://wings.localhost (API)"
    echo "  • Portainer: http://portainer.localhost"
    echo "  • Suwayomi: http://manga.localhost"
fi

echo ""
echo -e "${BLUE}Game Server Ports:${NC}"
echo "  • Minecraft: 25565-25575"
echo "  • Source Games: 27015"
echo "  • Other Games: 7777-7780"
echo "  • SFTP: 2022"

echo ""
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo ""
echo "1. ${GREEN}Setup Pelican Panel:${NC}"
echo "   Visit panel URL → /installer"
if [ -n "$APP_KEY" ]; then
    echo "   ${GREEN}Your App Key: $APP_KEY${NC} (SAVE THIS!)"
fi

echo ""
echo "2. ${GREEN}Configure Wings:${NC}"
echo "   After Pelican setup, run: ./configure-wings.sh"

echo ""
echo "3. ${GREEN}Setup Portainer:${NC}"
echo "   Visit Portainer URL (create admin quickly - 5 min timeout)"

echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  • View logs:        docker compose logs -f"
echo "  • Restart services: docker compose restart"
echo "  • Stop everything:  docker compose down"
echo "  • Update services:  docker compose pull && docker compose up -d"
echo "  • Configure Wings:  ./configure-wings.sh"

echo ""
echo -e "${GREEN}✨ Enjoy your game server stack!${NC}"
echo ""

# Save installation info
cat > installation-info.txt << EOF
Installation completed at: $(date)
Type: $SETUP_TYPE
Directory: $(pwd)
$([ "$SETUP_TYPE" = "production" ] && echo "Domain: $DOMAIN")
$([ "$SETUP_TYPE" = "production" ] && echo "Email: $EMAIL")
$([ -n "$APP_KEY" ] && echo "Pelican App Key: $APP_KEY")

Services:
- Pelican Panel
- Wings (Game Server Daemon)
- Portainer (Docker Management)
- Suwayomi (Manga Server)
- Caddy (Reverse Proxy)

Ports:
- 80: HTTP
$([ "$SETUP_TYPE" = "production" ] && echo "- 443: HTTPS")
- 8080: Wings API
- 2022: SFTP
- 25565-25575: Minecraft
- 27015: Source Games
- 7777-7780: Other Games
EOF

print_info "Installation details saved to installation-info.txt"