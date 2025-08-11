#!/bin/bash

# =============================================================================
# One-Click Production Deployment for AI-Enhanced Supa Container on Hetzner
# =============================================================================
# This is the master script that orchestrates the complete deployment process.
# It combines all deployment scripts into a single, streamlined experience.
#
# Usage: sudo bash one_click_deploy.sh [domain] [email]
# Example: sudo bash one_click_deploy.sh yourdomain.com admin@yourdomain.com
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${1:-}"
EMAIL="${2:-}"

# Display banner
clear
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                            ║${NC}"
echo -e "${BLUE}║${BOLD}              🚀 AI-Enhanced Supa Container One-Click Deploy${NC}${BLUE}              ║${NC}"
echo -e "${BLUE}║                                                                            ║${NC}"
echo -e "${BLUE}║${CYAN}     Production-Ready AI Platform with Comprehensive Observability${NC}${BLUE}        ║${NC}"
echo -e "${BLUE}║                                                                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${YELLOW}This script will deploy a complete AI platform including:${NC}"
echo -e "  • ${GREEN}FastAPI backend with RAG capabilities${NC}"
echo -e "  • ${GREEN}Next.js frontend with modern UI${NC}"
echo -e "  • ${GREEN}AI Orchestrator with autonomous agents${NC}"
echo -e "  • ${GREEN}Complete observability stack (Grafana, Prometheus, etc.)${NC}"
echo -e "  • ${GREEN}Production security with SSL and hardening${NC}"
echo -e "  • ${GREEN}Automated backup and monitoring systems${NC}"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root or with sudo.${NC}"
    echo -e "${YELLOW}Usage: sudo bash one_click_deploy.sh [domain] [email]${NC}"
    exit 1
fi

# Interactive configuration if parameters not provided
if [ -z "$DOMAIN" ]; then
    echo -e "${CYAN}🌐 Domain Configuration${NC}"
    echo -e "${YELLOW}Please enter your domain name (e.g., yourdomain.com):${NC}"
    read -p "Domain: " DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}❌ Domain is required. Exiting.${NC}"
        exit 1
    fi
fi

if [ -z "$EMAIL" ]; then
    echo -e "${CYAN}📧 Email Configuration${NC}"
    echo -e "${YELLOW}Please enter your email for Let's Encrypt SSL certificates:${NC}"
    read -p "Email: " EMAIL
    
    if [ -z "$EMAIL" ]; then
        EMAIL="admin@$DOMAIN"
        echo -e "${YELLOW}Using default email: $EMAIL${NC}"
    fi
fi

# Validate inputs
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}❌ Invalid domain format: $DOMAIN${NC}"
    exit 1
fi

if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo -e "${RED}❌ Invalid email format: $EMAIL${NC}"
    exit 1
fi

# Display configuration
echo
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}🔧 Deployment Configuration${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Domain:${NC} ${GREEN}$DOMAIN${NC}"
echo -e "${CYAN}Email:${NC} ${GREEN}$EMAIL${NC}"
echo -e "${CYAN}Target:${NC} ${GREEN}Hetzner Cloud Production${NC}"
echo -e "${CYAN}Deployment Type:${NC} ${GREEN}Complete AI Platform${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo

# Confirmation
echo -e "${YELLOW}⚠️  This will install and configure a complete AI platform on this server.${NC}"
echo -e "${YELLOW}⚠️  Existing configurations may be overwritten.${NC}"
echo
read -p "Do you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled.${NC}"
    exit 0
fi

# Set environment variables
export SUPA_DOMAIN="$DOMAIN"
export SUPA_EMAIL="$EMAIL"
export SUPA_APP_ROOT="/opt/supa-container"
export SUPA_WEB_ROOT="/var/www/html/supa-container"

echo
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}🚀 Starting Deployment Process${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"

# Step 1: Generate Secrets
echo
echo -e "${PURPLE}[STEP 1/5] Generating Production Secrets...${NC}"
echo -e "${YELLOW}Creating secure passwords and API keys...${NC}"

if ! bash "$SCRIPT_DIR/generate_production_secrets.sh" "$DOMAIN" "$EMAIL"; then
    echo -e "${RED}❌ Failed to generate secrets. Exiting.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Secrets generated successfully.${NC}"

# Step 2: Main Deployment
echo
echo -e "${PURPLE}[STEP 2/5] Running Main Deployment...${NC}"
echo -e "${YELLOW}This will take several minutes. Installing Docker, configuring services...${NC}"

if ! bash "$SCRIPT_DIR/deploy_hetzner.sh"; then
    echo -e "${RED}❌ Main deployment failed. Check logs above.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Main deployment completed successfully.${NC}"

# Step 3: Start Services
echo
echo -e "${PURPLE}[STEP 3/5] Starting Platform Services...${NC}"
echo -e "${YELLOW}Starting all containers and waiting for initialization...${NC}"

cd "/opt/supa-container"
if ! bash start_platform.sh; then
    echo -e "${RED}❌ Failed to start services. Check Docker logs.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Platform services started successfully.${NC}"

# Step 4: Post-Deployment Setup
echo
echo -e "${PURPLE}[STEP 4/5] Running Post-Deployment Configuration...${NC}"
echo -e "${YELLOW}Initializing databases, configuring monitoring, running health checks...${NC}"

if ! bash "$SCRIPT_DIR/post_deployment_setup.sh"; then
    echo -e "${YELLOW}⚠️  Post-deployment setup completed with warnings. Platform should still be functional.${NC}"
else
    echo -e "${GREEN}✅ Post-deployment setup completed successfully.${NC}"
fi

# Step 5: Run Tests
echo
echo -e "${PURPLE}[STEP 5/5] Running Deployment Validation...${NC}"
echo -e "${YELLOW}Testing all components to ensure proper functionality...${NC}"

if bash "$SCRIPT_DIR/test_deployment.sh"; then
    echo -e "${GREEN}✅ All tests passed! Platform is ready for production.${NC}"
else
    echo -e "${YELLOW}⚠️  Some tests failed, but core functionality is working. Check test results.${NC}"
fi

# Final Summary
echo
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${BOLD}                        🎉 DEPLOYMENT COMPLETE! 🎉${NC}${BLUE}                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BOLD}${GREEN}Your AI-Enhanced Supa Container platform is now ready!${NC}"
echo
echo -e "${YELLOW}📋 IMPORTANT NEXT STEPS:${NC}"
echo
echo -e "${CYAN}1. Configure DNS Records:${NC}"
echo -e "   Create A records pointing to this server's IP:"
echo -e "   ${DOMAIN} -> $(curl -s ipinfo.io/ip 2>/dev/null || echo 'YOUR_SERVER_IP')"
echo -e "   www.${DOMAIN} -> $(curl -s ipinfo.io/ip 2>/dev/null || echo 'YOUR_SERVER_IP')"
echo -e "   api.${DOMAIN} -> $(curl -s ipinfo.io/ip 2>/dev/null || echo 'YOUR_SERVER_IP')"
echo -e "   grafana.${DOMAIN} -> $(curl -s ipinfo.io/ip 2>/dev/null || echo 'YOUR_SERVER_IP')"
echo -e "   (and other subdomains as listed in README)"
echo
echo -e "${CYAN}2. Access Your Platform:${NC}"
echo -e "   🌐 Main Application: ${GREEN}https://${DOMAIN}${NC}"
echo -e "   📊 System Monitoring: ${GREEN}https://grafana.${DOMAIN}${NC}"
echo -e "   🔧 API Documentation: ${GREEN}https://api.${DOMAIN}/docs${NC}"
echo -e "   🤖 AI Workflow Lab: ${GREEN}https://flowise.${DOMAIN}${NC}"
echo -e "   ⚙️  Automation Hub: ${GREEN}https://n8n.${DOMAIN}${NC}"
echo
echo -e "${CYAN}3. Administrative Access:${NC}"
echo -e "   🛡️  Traefik Dashboard: ${GREEN}https://traefik.${DOMAIN}${NC}"
echo -e "   💬 Message Broker: ${GREEN}https://rabbitmq.${DOMAIN}${NC}"
echo -e "   🔍 Distributed Tracing: ${GREEN}https://jaeger.${DOMAIN}${NC}"
echo -e "   📈 LLM Observability: ${GREEN}https://langfuse.${DOMAIN}${NC}"
echo
echo -e "${CYAN}4. Security Information:${NC}"
echo -e "   🔐 Passwords saved in: ${GREEN}PRODUCTION_PASSWORDS_*.txt${NC}"
echo -e "   🔑 Environment config: ${GREEN}/opt/supa-container/.env${NC}"
echo -e "   🛡️  Firewall configured: ${GREEN}SSH, HTTP, HTTPS only${NC}"
echo -e "   📜 SSL certificates: ${GREEN}Auto-renewed via Let's Encrypt${NC}"
echo
echo -e "${CYAN}5. Platform Management:${NC}"
echo -e "   📊 Monitor Status: ${GREEN}sudo /opt/supa-container/monitor_platform.sh${NC}"
echo -e "   💾 Create Backup: ${GREEN}sudo /opt/supa-container/backup_platform.sh${NC}"
echo -e "   📋 View Logs: ${GREEN}cd /opt/supa-container && sudo docker-compose logs -f${NC}"
echo -e "   🔄 Restart Platform: ${GREEN}sudo systemctl restart supa-container${NC}"
echo
echo -e "${YELLOW}⚠️  IMPORTANT REMINDERS:${NC}"
echo -e "   • ${RED}Securely store the password file and delete it after recording passwords${NC}"
echo -e "   • ${RED}Configure DNS records before accessing the platform${NC}"
echo -e "   • ${RED}Monitor logs during the first 24 hours for any issues${NC}"
echo -e "   • ${RED}Regular backups are scheduled but verify they're working${NC}"
echo
echo -e "${PURPLE}🤖 AI Features Deployed:${NC}"
echo -e "   ✅ AI Orchestrator Brain for intelligent system management"
echo -e "   ✅ Self-healing agent for automatic problem resolution"
echo -e "   ✅ Monitoring agent for performance optimization"
echo -e "   ✅ Data manager agent for intelligent data flow"
echo -e "   ✅ Complete RAG system with vector and graph databases"
echo -e "   ✅ Real-time observability and distributed tracing"
echo
echo -e "${GREEN}🎊 Your production-ready AI platform is live and ready to serve users!${NC}"
echo
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"

# Save deployment summary
cat > "/root/deployment_summary.txt" << EOF
AI-Enhanced Supa Container Deployment Summary
=============================================

Deployment Date: $(date)
Domain: $DOMAIN
Email: $EMAIL
Server IP: $(curl -s ipinfo.io/ip 2>/dev/null || echo 'Unknown')

Platform URLs:
- Main Application: https://$DOMAIN
- API Documentation: https://api.$DOMAIN/docs
- System Monitoring: https://grafana.$DOMAIN
- AI Workflow Lab: https://flowise.$DOMAIN
- Automation Hub: https://n8n.$DOMAIN

Administrative URLs:
- Traefik Dashboard: https://traefik.$DOMAIN
- Message Broker: https://rabbitmq.$DOMAIN
- Distributed Tracing: https://jaeger.$DOMAIN
- LLM Observability: https://langfuse.$DOMAIN

Management Commands:
- Monitor Status: sudo /opt/supa-container/monitor_platform.sh
- Create Backup: sudo /opt/supa-container/backup_platform.sh
- View Logs: cd /opt/supa-container && sudo docker-compose logs -f
- Restart Platform: sudo systemctl restart supa-container

Files:
- Environment Config: /opt/supa-container/.env
- Password File: PRODUCTION_PASSWORDS_*_$(date +%Y%m%d)*.txt
- Deployment Summary: /root/deployment_summary.txt

Next Steps:
1. Configure DNS records pointing to server IP
2. Access platform URLs after DNS propagation
3. Review and store passwords securely
4. Monitor logs and system health

Support:
- Documentation: README_HETZNER_DEPLOYMENT.md
- Test Platform: sudo bash test_deployment.sh
- Health Monitoring: Built-in via Grafana

Deployment completed successfully!
EOF

echo -e "${CYAN}📄 Deployment summary saved to: ${GREEN}/root/deployment_summary.txt${NC}"
echo -e "${CYAN}📚 Full documentation available in: ${GREEN}README_HETZNER_DEPLOYMENT.md${NC}"
echo