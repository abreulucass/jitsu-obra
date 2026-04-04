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
      echo "Generating Prisma Client for Console..."
      npx prisma generate --schema /app/schema.prisma || echo "Prisma generate failed, but continuing..."
      ls -la node_modules/.prisma || echo "Prisma client directory not found"
      echo "Updating database schema..."
      npx prisma db push --accept-data-loss --skip-generate --schema /app/schema.prisma
    fi

    # Run seed if SEED_DEMO_CONFIGURATION is set
    if [ ! -z "$SEED_DEMO_CONFIGURATION" ]; then
      echo "SEED_DEMO_CONFIGURATION is set, seeding demo configuration..."
      node /app/webapps/console/build/manage.js seed || echo "Seed failed or skipped (this is ok if already seeded)"
    fi

    # Automatic Seeding via .env
    if [ -n "$SEED_USER_EMAIL" ] && [ -n "$SEED_USER_PASSWORD" ]; then
        echo "🌱 Automatic seeding detected for $SEED_USER_EMAIL..."
        
        # Calculate IDs and Hashes (using basic bash/node without external libs)
        EMAIL=$(echo "$SEED_USER_EMAIL" | tr '[:upper:]' '[:lower:]' | xargs)
        USER_ID=$(node -e "const crypto = require('crypto'); console.log(crypto.createHash('sha256').update('$EMAIL').digest('hex'))")
        
        # Juava Hashing Logic (SHA512 + Salt)
        GLOBAL_SEED=${GLOBAL_HASH_SECRET:-${CONSOLE_TOKEN_SECRET:-"dea42a58-acf4-45af-85bb-e77e94bd5025"}}
        RANDOM_SALT="abc123def456ghi789jkl012mno345pq"
        USER_HASH=$(node -e "const crypto = require('crypto'); console.log('$RANDOM_SALT.' + crypto.createHash('sha512').update('$SEED_USER_PASSWORD' + '$RANDOM_SALT' + '$GLOBAL_SEED').digest('hex'))")
        
        # Inject using Prisma DB Execute (Native and Safe)
        echo "  -> Injecting Administrative User via Prisma..."
        printf "
        INSERT INTO \"newjitsu\".\"Workspace\" (id, name, slug) VALUES ('${USER_ID}-ws', 'Main Workspace', 'main') ON CONFLICT DO NOTHING;
        INSERT INTO \"newjitsu\".\"UserProfile\" (id, name, email, admin, \"loginProvider\", \"externalId\") VALUES ('${USER_ID}', '${EMAIL%%@*}', '${EMAIL}', true, 'credentials', '${USER_ID}') ON CONFLICT DO NOTHING;
        INSERT INTO \"newjitsu\".\"UserPassword\" (id, \"userId\", hash, \"changeAtNextLogin\") VALUES ('${USER_ID}-pw', '${USER_ID}', '${USER_HASH}', false) ON CONFLICT DO NOTHING;
        INSERT INTO \"newjitsu\".\"WorkspaceAccess\" (\"userId\", \"workspaceId\", role) VALUES ('${USER_ID}', '${USER_ID}-ws', 'owner') ON CONFLICT DO NOTHING;
        " | npx prisma db execute --stdin --schema /app/schema.prisma && echo "✅ Automatic seeding successful!" || echo "❌ Automatic seeding failed (this is ok if already seeded)"
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
