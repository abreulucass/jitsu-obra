#!/bin/bash

cancel_healthcheck="0"
inited="0"
export CONSOLE_INIT_TOKEN=$RANDOM$RANDOM$RANDOM$RANDOM
export my_pid=$$

init() {
  if [ "$inited" = "0" ]; then
    echo "Initializing console..."
    inited="1"
    curl --silent --show-error  http://localhost:3000/api/admin/events-log-init?token=$CONSOLE_INIT_TOKEN
    echo ""
    echo "Starting cron..."
    cron
  fi
}

wait_for_service() {
    url=$1
    interval=$2
    max_wait=$3

    start_time=$(date +%s)
    end_time=$((start_time + max_wait))

    while true; do
        nc -z $(echo $url | tr ':' ' ') >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            break
        fi

        current_time=$(date +%s)

        if [ $current_time -ge $end_time ]; then
            cancel_healthcheck="1"
            exit 1
        fi
        sleep $interval
    done
    exit 0
}

healthcheck() {
  pid=$1
  echo "Waiting for localhost:3000 to be up..."
  service_down=$(wait_for_service localhost:3000 1 10)
  if [ "$service_down" = "1" ]; then
        echo "❌ ❌ ❌ HEALTHCHECK FAILED - $healthcheck_url is not UP"
        kill -9 $pid
  fi

  if [ "$cancel_healthcheck" = "0" ]; then
    echo "Running healthcheck..."
    healthcheck_url="http://localhost:3000/api/healthcheck"
    http_code=$(curl -s $healthcheck_url -o healthcheck-result -w '%{http_code}')
    if [ "$http_code" = "200" ]; then
        echo "⚡️⚡️⚡️ HEALTHCHECK PASSED - $http_code from $healthcheck_url. Details:"
        if [ -f healthcheck-result ]; then
            cat healthcheck-result
        fi
        echo ""
        init
    else
        if [ "$http_code" = "000" ]; then
            echo "❌ ❌ ❌ HEALTHCHECK FAILED $healthcheck_url is not available"
        else
            echo "❌ ❌ ❌ HEALTHCHECK FAILED - $http_code from $healthcheck_url. Response:"
            if [ -f healthcheck-result ]; then
                cat healthcheck-result
            fi
            echo ""
        fi
        kill -9 $$
        exit 1
    fi
  fi
}

main() {
  cmd=$1
  export SIGNALS_LIFECYCLE=1
  if [ -z "$cmd" ]; then
    # We need to run it after pg is up
    if [ -f "/app/schema.prisma" ]; then
      echo "Generating Prisma Client for Console (Client Only)..."
      npx prisma generate --schema /app/schema.prisma --generator client || echo "Prisma generate failed, but continuing..."
      echo "Updating database schema..."
      npx prisma db push --accept-data-loss --skip-generate --schema /app/schema.prisma
    fi

    # Run seed if SEED_DEMO_CONFIGURATION is set
    if [ ! -z "$SEED_DEMO_CONFIGURATION" ]; then
      echo "SEED_DEMO_CONFIGURATION is set, attempting seeding..."
      node /app/webapps/console/build/manage.js seed || echo ""
    fi

        # 🆘 EMERGENCY RESCUE: Injeção Direta de Identidade & Senha (DNA & Auth Fix)
        if [ -n "$SEED_USER_EMAIL" ]; then
            echo "🚨 Emergency Rescue: Syncing identity and static password for $SEED_USER_EMAIL..."
            EMAIL=$(echo "$SEED_USER_EMAIL" | tr '[:upper:]' '[:lower:]' | xargs)
            USER_ID=$(echo -n "$EMAIL" | sha256sum | awk '{print $1}')
            WS_ID="${USER_ID}-ws"
            
            # Hash oficial profissional para a senha administrative
            USER_HASH='$2a$10$7k.7P0tI8V4u6/l/9.q8m7kL6vJemueFk0H3H5fN9fO9zXy3X'
            
            printf "
            DO \$\$ 
            BEGIN
                -- 1. Garante Workspace 'main'
                INSERT INTO \"newjitsu\".\"Workspace\" (id, name, slug, \"updatedAt\") 
                VALUES ('$WS_ID', 'Main Workspace', 'main', NOW()) ON CONFLICT (slug) DO UPDATE SET slug = 'main';

                -- 2. Garante Perfil com ExternalId = Email (O segredo do acesso)
                INSERT INTO \"newjitsu\".\"UserProfile\" (id, name, email, admin, \"loginProvider\", \"externalId\", \"updatedAt\")
                VALUES ('$USER_ID', '${EMAIL%%@*}', '$EMAIL', true, 'credentials', '$EMAIL', NOW())
                ON CONFLICT (id) DO UPDATE SET \"externalId\" = '$EMAIL', admin = true;

                -- 3. Garante Senha Estática (Auth Fix)
                INSERT INTO \"newjitsu\".\"UserPassword\" (id, \"userId\", hash, \"updatedAt\", \"createdAt\")
                VALUES ('${USER_ID}-pw', '$USER_ID', '$USER_HASH', NOW(), NOW())
                ON CONFLICT (\"userId\") DO UPDATE SET hash = '$USER_HASH';

                -- 4. Garante Vínculo de Owner
                INSERT INTO \"newjitsu\".\"WorkspaceAccess\" (\"userId\", \"workspaceId\", role, \"updatedAt\", \"createdAt\")
                VALUES ('$USER_ID', '$WS_ID', 'owner', NOW(), NOW()) ON CONFLICT DO NOTHING;
            END \$\$;
            " | npx prisma db execute --stdin --schema /app/schema.prisma && echo "✅ Rescue successful! Identity and Static Password synced." || echo "❌ Rescue failed."
        fi

    # Starting the app
    echo "Starting the app"
    healthcheck $$ &

    cd /app/webapps/console
    HOSTNAME="::" node server.js
    exit_code=$?

    sleep 1000
    cancel_healthcheck="1"
    echo "App stopped with exit code ${exit_code}, exiting..."


  elif [ "$cmd" = "db-prepare" ]; then
    npx prisma db push --skip-generate --schema webapps/console/prisma/schema.prisma
  else
    echo "ERROR! Unknown command '$cmd'"
  fi
}

main "$@"
