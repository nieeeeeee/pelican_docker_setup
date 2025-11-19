#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Docker Stack Auto-Setup Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Function to print colored messages
print_status() {
    echo -e "${YELLOW}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Ask user for setup type
echo "Choose your setup type:"
echo "1) Local development (localhost)"
echo "2) Production with domain"
echo -n "Enter choice [1-2]: "
read -r choice

case $choice in
    1)
        print_status "Setting up local development environment..."
        SETUP_TYPE="local"
        ;;
    2)
        print_status "Setting up production environment..."
        SETUP_TYPE="production"
        
        # Get domain name
        echo -n "Enter your domain (e.g., atus.ovh): "
        read -r DOMAIN
        
        # Get email
        echo -n "Enter your email for SSL certificates: "
        read -r EMAIL
        ;;
    *)
        print_error "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Create project directory
INSTALL_DIR="docker-stack"
print_status "Creating project directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit

# Clean up any existing containers
print_status "Cleaning up any existing containers..."
docker compose down 2>/dev/null || true

if [ "$SETUP_TYPE" = "local" ]; then
    # Create docker-compose.yml for localhost
    print_status "Creating docker-compose.yml for localhost..."
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
  portainer-data:
  suwayomi-data:

networks:
  web:
EOF

    # Create Caddyfile for localhost
    print_status "Creating Caddyfile for localhost..."
    cat > Caddyfile << 'EOF'
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
    respond "Services:
• Pelican: http://panel.localhost
• Portainer: http://portainer.localhost
• Suwayomi: http://manga.localhost"
}
EOF

else
    # Production setup
    print_status "Creating docker-compose.yml for production..."
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
  portainer-data:
  suwayomi-data:

networks:
  web:
EOF

    # Create Caddyfile for production
    print_status "Creating Caddyfile for production..."
    cat > Caddyfile << EOF
{
    email $EMAIL
}

panel.$DOMAIN {
    reverse_proxy pelican:80
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
fi

# Create pelican-caddyfile (same for both)
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

# Pull images
print_status "Pulling Docker images (this may take a while)..."
docker compose pull

# Start services
print_status "Starting all services..."
docker compose up -d

# Wait for services to start
print_status "Waiting for services to initialize..."
sleep 10

# Check if services are running
print_status "Checking service status..."
docker compose ps

# Get Pelican app key
print_success "Services started successfully!"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$SETUP_TYPE" = "local" ]; then
    echo "Access your services at:"
    echo "  • Pelican Panel: http://panel.localhost"
    echo "  • Portainer: http://portainer.localhost"
    echo "  • Suwayomi: http://manga.localhost"
    echo "  • Main page: http://localhost"
else
    echo "Access your services at:"
    echo "  • Pelican Panel: https://panel.$DOMAIN"
    echo "  • Portainer: https://portainer.$DOMAIN"
    echo "  • Suwayomi: https://manga.$DOMAIN"
    echo "  • Main domain: https://$DOMAIN"
    echo ""
    echo -e "${YELLOW}Note: Make sure your DNS is configured:${NC}"
    echo "  - panel.$DOMAIN → Your Server IP"
    echo "  - portainer.$DOMAIN → Your Server IP"
    echo "  - manga.$DOMAIN → Your Server IP"
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Pelican: Go to panel URL + /installer to complete setup"
echo "2. Portainer: Create admin account (5 minute timeout)"
echo "3. Save Pelican encryption key:"
echo "   docker compose logs pelican | grep 'Generated app key:'"
echo ""
echo -e "${GREEN}Useful commands:${NC}"
echo "  • View logs: docker compose logs -f"
echo "  • Stop services: docker compose down"
echo "  • Restart services: docker compose restart"
echo "  • Update services: docker compose pull && docker compose up -d"
echo ""
print_success "Installation complete! Enjoy your stack!"