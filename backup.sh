#!/bin/bash
echo "Executing backup script..."

# Source environment configuration to get FRAPPE_SITE_NAME if needed
# This ensures the script uses the site name defined in env.config
SITE_NAME_FOR_BACKUP="all" # Default to 'all' sites
if [ -f "/home/frappe/env.config" ]; then
  source "/home/frappe/env.config" # Load FRAPPE_SITE_NAME
  if [ -n "$FRAPPE_SITE_NAME" ]; then
    SITE_NAME_FOR_BACKUP="$FRAPPE_SITE_NAME"
  fi
fi

echo "Backing up site: $SITE_NAME_FOR_BACKUP"

# Ensure script is run as frappe user if it needs bench context
# This is a placeholder; actual execution might need `su - frappe -c "..."` if run by root
# cd /home/frappe/frappe-bench && bench --site "$SITE_NAME_FOR_BACKUP" backup --with-files >> /home/frappe/frappe-bench/logs/backup.log 2>&1

echo "Backup script placeholder finished. Implement actual backup commands."
# Example:
# su - frappe -c "cd /home/frappe/frappe-bench && bench --site \"$SITE_NAME_FOR_BACKUP\" backup --with-files"
