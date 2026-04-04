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
            USER_NAME="${EMAIL%%@*}"

            # Monta o SQL em arquivo temporário para evitar que o shell destrua os $ do hash BCrypt
            cat > /tmp/rescue.sql <<'EOSQL'
DO $$
BEGIN
    INSERT INTO "newjitsu"."Workspace" (id, name, slug, "updatedAt")
    VALUES ('__WS_ID__', 'Main Workspace', 'main', NOW())
    ON CONFLICT (slug) DO UPDATE SET slug = 'main';

    INSERT INTO "newjitsu"."UserProfile" (id, name, email, admin, "loginProvider", "externalId", "updatedAt")
    VALUES ('__USER_ID__', '__USER_NAME__', '__EMAIL__', true, 'credentials', '__EMAIL__', NOW())
    ON CONFLICT (id) DO UPDATE SET "externalId" = '__EMAIL__', admin = true;

    INSERT INTO "newjitsu"."UserPassword" (id, "userId", hash, "updatedAt", "createdAt")
    VALUES ('__USER_ID__-pw', '__USER_ID__', '$2b$10$N1RJDihy63pM6zuIndjvwu702oqEzlCceFEqgFl8XDSgVfzO.9TQy', NOW(), NOW())
    ON CONFLICT ("userId") DO UPDATE SET hash = '$2b$10$N1RJDihy63pM6zuIndjvwu702oqEzlCceFEqgFl8XDSgVfzO.9TQy';

    INSERT INTO "newjitsu"."WorkspaceAccess" ("userId", "workspaceId", role, "updatedAt", "createdAt")
    VALUES ('__USER_ID__', '__WS_ID__', 'owner', NOW(), NOW()) ON CONFLICT DO NOTHING;
END $$;
EOSQL
            # Substitui os placeholders (sem tocar nos $ do hash)
            sed -i "s|__USER_ID__|${USER_ID}|g" /tmp/rescue.sql
            sed -i "s|__WS_ID__|${WS_ID}|g" /tmp/rescue.sql
            sed -i "s|__EMAIL__|${EMAIL}|g" /tmp/rescue.sql
            sed -i "s|__USER_NAME__|${USER_NAME}|g" /tmp/rescue.sql

            cat /tmp/rescue.sql | npx prisma db execute --stdin --schema /app/schema.prisma && echo "✅ Rescue successful! Identity and Static Password synced." || echo "❌ Rescue failed."
            rm -f /tmp/rescue.sql
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
