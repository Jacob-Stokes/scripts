#!/bin/bash

# Script to manage Nginx and Certbot configuration for a specified domain
# Options: 1. Setup, 2. List Configs, 3. Help, 4. Exit

# Function to send notifications to ntfy
function send_notification() {
    local action=$1
    local domain=$2
    local port=$3
    local message="Action: $action, Domain: $domain, Port: $port"
    
    curl -d "$message" -H "Title: Nginx Update" "https://ntfy.jacobstokes.com/droplet-nginx"
}

# Helper functions
function show_help() {
    echo "This script helps you manage Nginx and Certbot for a domain."
    echo "Options:"
    echo "  1) Setup: Creates an Nginx config, enables HTTPS with Certbot"
    echo "  2) List Configurations: Lists all domains and ports currently configured"
    echo "  3) Help: Displays this help information"
    echo "  4) Exit: Exits the script"
}

function setup_nginx_certbot() {
    read -p "Enter the domain name (e.g., example.com): " DOMAIN_NAME
    read -p "Enter the application port (e.g., 3000): " PORT

    NGINX_CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN_NAME"
    sudo tee $NGINX_CONFIG_FILE > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

    sudo ln -s $NGINX_CONFIG_FILE /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
    sudo certbot --nginx -d $DOMAIN_NAME --non-interactive --agree-tos -m your-email@example.com
    echo "Setup complete! HTTPS has been enabled for $DOMAIN_NAME."

    # Send notification
    send_notification "Proxy Created" "$DOMAIN_NAME" "$PORT"
}

function manage_config() {
    DOMAIN=$1
    NGINX_CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"
    NGINX_SYMLINK="/etc/nginx/sites-enabled/$DOMAIN"

    while true; do
        echo ""
        echo "Managing configuration for $DOMAIN"
        echo "Please choose an action:"
        echo "  1) Edit config"
        echo "  2) Renew certificate"
        echo "  3) Purge configuration and certificate"
        echo "  4) Return to main menu"
        read -p "Enter your choice [1-4]: " ACTION

        case $ACTION in
            1)
                sudo nano "$NGINX_CONFIG_FILE"
                ;;
            2)
                sudo certbot renew --cert-name "$DOMAIN"
                echo "Certificate renewal attempted for $DOMAIN."
                # Send notification
                send_notification "Certificate Renewal" "$DOMAIN" "N/A"
                ;;
            3)
                # Purge option
                if [ -f "$NGINX_CONFIG_FILE" ]; then
                    sudo rm "$NGINX_CONFIG_FILE"
                    echo "Removed Nginx config for $DOMAIN."
                else
                    echo "No Nginx config found for $DOMAIN."
                fi

                if [ -L "$NGINX_SYMLINK" ]; then
                    sudo rm "$NGINX_SYMLINK"
                    echo "Removed Nginx symlink for $DOMAIN."
                else
                    echo "No symlink found in sites-enabled for $DOMAIN."
                fi

                sudo certbot delete --cert-name "$DOMAIN"
                sudo systemctl reload nginx
                echo "Purge complete! Configuration and SSL for $DOMAIN have been removed."

                # Send notification
                send_notification "Proxy Purged" "$DOMAIN" "N/A"
                break
                ;;
            4)
                return
                ;;
            *)
                echo "Invalid choice. Please enter a number between 1 and 4."
                ;;
        esac
    done
}

function list_configs() {
    CONFIG_FILES=($(ls /etc/nginx/sites-available))
    if [ ${#CONFIG_FILES[@]} -eq 0 ]; then
        echo "No configurations found in /etc/nginx/sites-available."
        return
    fi

    echo "Configured Domains and Ports:"
    echo "0) Return to main menu"
    for i in "${!CONFIG_FILES[@]}"; do
        DOMAIN=${CONFIG_FILES[$i]}
        PORT=$(grep -oP '(?<=proxy_pass http://localhost:)[0-9]+' /etc/nginx/sites-available/$DOMAIN)
        echo "$((i + 1))) Domain: $DOMAIN, Port: $PORT"
    done

    read -p "Enter the number of the configuration to manage, or 0 to return: " CHOICE

    if [[ "$CHOICE" -eq 0 ]]; then
        return
    elif [[ "$CHOICE" -gt 0 && "$CHOICE" -le ${#CONFIG_FILES[@]} ]]; then
        manage_config "${CONFIG_FILES[$((CHOICE - 1))]}"
    else
        echo "Invalid choice. Returning to main menu."
    fi
}

function reload_nginx() {
    sudo systemctl reload nginx
    echo "Nginx configuration reloaded."
    send_notification "Nginx Reloaded" "N/A" "N/A"
}

function restart_nginx() {
    sudo systemctl restart nginx
    echo "Nginx has been restarted."
    send_notification "Nginx Restarted" "N/A" "N/A"
}

# Main menu loop
while true; do
    echo ""
    echo "Basic NGINX config manager"
    echo "Please choose an option:"
    echo "  1) Setup Nginx and Certbot for a domain"
    echo "  2) List Configurations"
    echo "  3) Help"
    echo "  4) Exit"
    echo "  5) Reload Nginx"
    echo "  6) Restart Nginx"
    read -p "Enter your choice [1-6]: " CHOICE

    case $CHOICE in
        1)
            setup_nginx_certbot
            ;;
        2)
            list_configs
            ;;
        3)
            show_help
            ;;
        4)
            echo "Exiting. Goodbye!"
            exit 0
            ;;
        5)
            reload_nginx
            ;;
        6)
            restart_nginx
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 6."
            ;;
    esac
done