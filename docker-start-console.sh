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
    echo "Generating Prisma Client for Console..."
    npx prisma generate --schema=webapps/console/prisma/schema.prisma || echo "Prisma generate failed, but continuing..."
    ls -R node_modules/.prisma || echo "Prisma client directory not found"
    if [ "$FORCE_UPDATE_DB" = "1" ] || [ "$FORCE_UPDATE_DB" = "yes" ] || [ "$FORCE_UPDATE_DB" = "true" ]; then
      echo "FORCE_UPDATE_DB is set, updating database schema..."
      npx prisma db push --skip-generate --schema webapps/console/prisma/schema.prisma --accept-data-loss
    elif [ "$UPDATE_DB" != "0" ] && [ "$UPDATE_DB" != "no" ] && [ "$UPDATE_DB" != "false" ]; then
      echo "Updating database schema..."
      npx prisma db push --skip-generate --schema webapps/console/prisma/schema.prisma
    fi

    # Run seed if SEED_DEMO_CONFIGURATION is set
    if [ ! -z "$SEED_DEMO_CONFIGURATION" ]; then
      echo "SEED_DEMO_CONFIGURATION is set, seeding demo configuration..."
      node /app/webapps/console/build/manage.js seed || echo "Seed failed or skipped (this is ok if already seeded)"
    fi

    # Automatic Seeding via .env
    if [ -n "$SEED_USER_EMAIL" ] && [ -n "$SEED_USER_PASSWORD" ]; then
        echo "🌱 Automatic seeding detected for $SEED_USER_EMAIL..."
        node -e "
    const { Client } = require('pg');
    const crypto = require('crypto');

    async function seed() {
        const client = new Client({
            connectionString: process.env.DATABASE_URL
        });
        try {
            await client.connect();
            
            const email = process.env.SEED_USER_EMAIL.toLowerCase().trim();
            const password = process.env.SEED_USER_PASSWORD;
            const userId = crypto.createHash('sha256').update(email).digest('hex');
            
            // Juava Hashing Logic (SHA512 + Salt)
            const randomSeed = 'abc123def456ghi789jkl012mno345pq';
            const globalSeed = process.env.GLOBAL_HASH_SECRET || process.env.CONSOLE_TOKEN_SECRET || 'dea42a58-acf4-45af-85bb-e77e94bd5025';
            const hash = randomSeed + '.' + crypto.createHash('sha512').update(password + randomSeed + globalSeed).digest('hex');

            console.log('  -> Injecting User: ' + email + ' (ID: ' + userId + ')');
            
            await client.query('INSERT INTO \"newjitsu\".\"Workspace\" (id, name, slug) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING', [userId + '-ws', 'Main Workspace', 'main']);
            await client.query('INSERT INTO \"newjitsu\".\"UserProfile\" (id, name, email, admin, \"loginProvider\", \"externalId\") VALUES ($1, $2, $3, true, $4, $5) ON CONFLICT DO NOTHING', [userId, email.split('@')[0], email, 'credentials', userId]);
            await client.query('INSERT INTO \"newjitsu\".\"UserPassword\" (id, \"userId\", hash, \"changeAtNextLogin\") VALUES ($1, $2, $3, false) ON CONFLICT DO NOTHING', [userId + '-pw', userId, hash]);
            await client.query('INSERT INTO \"newjitsu\".\"WorkspaceAccess\" (\"userId\", \"workspaceId\", role) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING', [userId, userId + '-ws', 'owner']);
            
            console.log('✅ Automatic seeding successful!');
        } catch (err) {
            console.error('❌ Automatic seeding failed:', err.message);
        } finally {
            await client.end();
        }
    }
    seed();
    "
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
