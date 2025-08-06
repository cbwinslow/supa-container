#!/bin/bash

# ==============================================================================
# 11_logging_monitoring_base.sh
# Summary: Sets up fundamental logging and monitoring components, including
#          rsyslog and auditd for system-level events and file changes.
# Author: Gemini
# Date: July 23, 2025
# IMPORTANT: Run this script as the 'root' user.
# ==============================================================================

# --- Error Handling ---
set -e

# --- Functions ---
log_info() { echo -e "\n\e[1;34m[INFO]\e\e\e\e; then
    log_info "Creating custom rsyslog config for AI agent logs: $RSYSLOG_APP_CONF"
    cat <<EOF > "$RSYSLOG_APP_CONF"
# Log all messages from 'my_ai_agent' to a dedicated file
if \$programname == 'my_ai_agent' then /var/log/my_ai_agent.log
& stop # Stop processing this message further
EOF
    systemctl restart rsyslog |

| log_warn "Failed to restart rsyslog after adding custom config."
    log_success "Custom rsyslog configuration for AI agent logs created."
else
    log_info "Custom rsyslog config for AI agent logs already exists."
fi
log_success "rsyslog configured for granular logging."

# 2. File Change Monitoring and User Commands/Activity Monitoring (auditd)
log_info "Setting up auditd for file change and user activity monitoring..."
if! command -v auditctl &> /dev/null; then
    log_info "auditd not found, installing auditd..."
    apt install auditd audispd-plugins -y |

| log_error "Failed to install auditd."
    log_success "auditd installed."
else
    log_info "auditd is already installed."
fi

# Configure auditd rules (basic set for critical files and user commands)
AUDITD_RULES_FILE="/etc/audit/rules.d/99-custom.rules"
log_info "Creating custom auditd rules: $AUDITD_RULES_FILE"
cat <<EOF > "$AUDITD_RULES_FILE"
# Monitor critical system files for changes
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/ssh/sshd_config -p wa -k ssh_config_changes
-w /var/log/auth.log -p wa -k auth_log_changes

# Monitor execution of privileged commands by any user
-a always,exit -F arch=b64 -S execve -F euid=0 -k privileged_exec
-a always,exit -F arch=b32 -S execve -F euid=0 -k privileged_exec

# Monitor user login/logout and authentication events
-w /var/log/faillog -p wa -k faillog_events
-w /var/log/lastlog -p wa -k lastlog_events
-w /var/log/tallylog -p wa -k tallylog_events

# Immutable rules (make rules persistent and prevent tampering)
-e 2
EOF

# Load auditd rules
log_info "Loading auditd rules..."
auditctl -R "$AUDITD_RULES_FILE" |

| log_error "Failed to load auditd rules. Check syntax in $AUDITD_RULES_FILE."
log_success "Auditd rules loaded."

# Enable and start auditd service
log_info "Enabling and starting auditd service..."
systemctl enable auditd |

| log_error "Failed to enable auditd."
systemctl start auditd |

| log_error "Failed to start auditd."
log_success "auditd installed and running."
log_warn "Auditd generates a lot of logs. Ensure your logging stack (Loki/OpenSearch) is configured to ingest /var/log/audit/audit.log."

# 3. Log Rotation for System and Application Logs
log_info "Ensuring logrotate is installed and configured..."
if! command -v logrotate &> /dev/null; then
    apt install logrotate -y |

| log_error "Failed to install logrotate."
    log_success "logrotate installed."
else
    log_info "logrotate is already installed."
fi

# Example: Create a custom logrotate configuration for AI agent logs
LOGROTATE_APP_CONF="/etc/logrotate.d/my-ai-agent"
if; then
    log_info "Creating custom logrotate config for AI agent logs: $LOGROTATE_APP_CONF"
    cat <<EOF > "$LOGROTATE_APP_CONF"
/var/log/my_ai_agent.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root adm
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF
    log_success "Custom logrotate configuration for AI agent logs created."
else
    log_info "Custom logrotate config for AI agent logs already exists."
fi
log_success "logrotate configured."

log_success "11_logging_monitoring_base.sh completed."
