#!/bin/bash
set -e
# For commands run as root in this script, HOME might be /root.
# For commands run via su - frappe, frappe's $HOME will be /home/frappe.
# The path to bench installed by pipx for the frappe user is typically /home/frappe/.local/bin/bench.
export PATH="/home/frappe/.local/bin:$PATH"

echo "🚀 Initializing ERPNext…"

# ensure correct ownership on persistent home
chown -R frappe:frappe /home/frappe

# only do the heavy bench init + site create once
if [ ! -d "/home/frappe/frappe-bench/apps/frappe" ]; then
  echo "🛠️ Installing & configuring bench…"
  su - frappe -c "bench init --skip-redis-config-generation /home/frappe/frappe-bench"

  echo "⚙️ Pointing at your DB & Redis containers…"
  su - frappe -c "cd /home/frappe/frappe-bench && \
    bench set-mariadb-host mariadb && \
    bench set-config -g redis_cache 'redis://redis:6379' && \
    bench set-config -g redis_queue 'redis://redis:6379' && \
    bench set-config -g redis_socketio 'redis://redis:6379'"

  echo "📦 Fetching apps…"
  su - frappe -c "cd /home/frappe/frappe-bench && \
    bench get-app erpnext && \
    bench get-app builder && \
    bench get-app hrms"

  echo "🌐 Creating site & installing apps…"
  FRAPPE_SITE_NAME="erpnext.local" # Or your actual site name if different
  su - frappe -c "cd /home/frappe/frappe-bench && \
    bench new-site \"$FRAPPE_SITE_NAME\" \
      --force \
      --mariadb-root-password=Moomkenwe0909 \
      --admin-password=admin \
      --mariadb-user-host-login-scope='%' && \
    bench --site \"$FRAPPE_SITE_NAME\" install-app erpnext && \
    bench --site \"$FRAPPE_SITE_NAME\" install-app builder && \
    bench --site \"$FRAPPE_SITE_NAME\" install-app hrms && \
    bench --site \"$FRAPPE_SITE_NAME\" set-config developer_mode 1 && \
    bench --site \"$FRAPPE_SITE_NAME\" clear-cache"

  # Set current site for bench commands, ensuring currentsite.txt is created
  su - frappe -c "cd /home/frappe/frappe-bench && bench use \"$FRAPPE_SITE_NAME\""

  echo "✅ Bench setup complete!"
fi

# Generate a proper Supervisor conf from bench itself,
# then symlink it into /etc so supervisord picks it up
echo "⚙️ Generating Supervisor config…"

SUPERVISOR_CONFIG_FILE="/home/frappe/frappe-bench/config/supervisor.conf"

rm -f "$SUPERVISOR_CONFIG_FILE"
# bench setup supervisor will use the site from currentsite.txt (set by 'bench use' above if new bench)
su - frappe -c "cd /home/frappe/frappe-bench && bench setup supervisor --skip-redis"

# --- START: Modification to change Gunicorn to bench serve (with debugging) ---
echo "DEBUG: Supervisor config file BEFORE awk modification ($SUPERVISOR_CONFIG_FILE):"
if [ -f "$SUPERVISOR_CONFIG_FILE" ]; then
    cat "$SUPERVISOR_CONFIG_FILE"
else
    echo "ERROR: $SUPERVISOR_CONFIG_FILE does not exist before awk!"
fi
echo "----------------------------------------------------"

echo "🔄 Modifying Supervisor config to use 'bench serve' for web process..."
NEW_WEB_COMMAND="/home/frappe/.local/bin/bench serve --port 8000"
NEW_WEB_DIRECTORY="/home/frappe/frappe-bench"
TEMP_AWK_OUTPUT_FILE="${SUPERVISOR_CONFIG_FILE}.tmp"

if [ ! -f "$SUPERVISOR_CONFIG_FILE" ]; then
    echo "ERROR: Cannot modify $SUPERVISOR_CONFIG_FILE because it was not generated."
else
    # Using classic awk state machine pattern for robustness
    awk -v cmd="$NEW_WEB_COMMAND" -v dir="$NEW_WEB_DIRECTORY" '
    BEGIN {
        # state 0 = outside target section
        # state 1 = inside target section [program:frappe-bench-frappe-web]
        state = 0;
    }

    # Rule 1: Enter the web section
    /\[program:frappe-bench-frappe-web\]/ {
        state = 1;
        print $0; # Print the section header
        next;     # Move to next line of input
    }

    # Rule 2: Exit the web section if in state 1 and another program section starts
    (state == 1 && $0 ~ /^[[:space:]]*\[program:/ && $0 !~ /\[program:frappe-bench-frappe-web\]/) {
        state = 0;
        # This line ($0) is the new section header, it will be printed by the default rule below.
    }

    # Rule 3: Process lines based on state
    (state == 1) { # We are inside the [program:frappe-bench-frappe-web] section
        if ($0 ~ /^command=/) {
            print "command=" cmd; # Use variable cmd passed with -v
            next;
        }
        if ($0 ~ /^directory=/) {
            print "directory=" dir; # Use variable dir passed with -v
            next;
        }
        # Comment out any other Gunicorn-related parameter lines that might be present
        if ($0 ~ /gunicorn/ || $0 ~ /frappe\.app:application/ || $0 ~ /--preload/ || $0 ~ /^-w[[:space:]]+[0-9]+/ || $0 ~ /^-b[[:space:]]+[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+/) {
            print "# (Original gunicorn-related line commented out by script) " $0;
            next;
        }
        # If none of the above conditions in this block matched and did a "next", print the original line within the section
        print $0;
        next;
    }

    # Default rule: print all lines that havent been handled by a "next"
    # This primarily handles lines when state = 0 (outside web section),
    # or section headers that cause state transition but werent explicitly printed and nexted.
    { print $0; }

    ' "$SUPERVISOR_CONFIG_FILE" > "$TEMP_AWK_OUTPUT_FILE"

    awk_exit_status=$?
    if [ $awk_exit_status -eq 0 ]; then
        echo "DEBUG: awk command completed successfully. Moving $TEMP_AWK_OUTPUT_FILE to $SUPERVISOR_CONFIG_FILE"
        mv "$TEMP_AWK_OUTPUT_FILE" "$SUPERVISOR_CONFIG_FILE"
        chown frappe:frappe "$SUPERVISOR_CONFIG_FILE"
        echo "✅ Supervisor config modified for 'bench serve'."
    else
        echo "ERROR: awk command failed with exit status $awk_exit_status. Original supervisor.conf may be unchanged or .tmp file may exist."
        echo "DEBUG: Contents of temp awk output file ($TEMP_AWK_OUTPUT_FILE):"
        if [ -f "$TEMP_AWK_OUTPUT_FILE" ]; then
            cat "$TEMP_AWK_OUTPUT_FILE"
        else
            echo "DEBUG: Temp awk output file does not exist."
        fi
    fi
fi # End check if SUPERVISOR_CONFIG_FILE exists

echo "DEBUG: Supervisor config file AFTER awk modification attempt ($SUPERVISOR_CONFIG_FILE):"
if [ -f "$SUPERVISOR_CONFIG_FILE" ]; then
    cat "$SUPERVISOR_CONFIG_FILE"
else
    echo "ERROR: $SUPERVISOR_CONFIG_FILE does not exist after awk!"
fi
echo "----------------------------------------------------"
# --- END: Debugging and Modification ---

ln -sf "$SUPERVISOR_CONFIG_FILE" /etc/supervisor/conf.d/frappe-bench.conf

echo "✅ Starting Supervisor in the foreground…"
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
