#!/bin/bash
set -eo pipefail

# --- Define services that need databases ---
# (Names must be lowercase)
services=("keycloak" "profile" "learning" "scheduling" "payment")

# --- Dynamically build required_vars ---
required_vars=("POSTGRES_USER" "POSTGRES_PASSWORD")
for service in "${services[@]}"; do
  upper_service=$(echo "$service" | tr '[:lower:]' '[:upper:]')
  required_vars+=("${upper_service}_DB_USER")
  required_vars+=("${upper_service}_DB_PASS")
done

# --- Validate Required Environment Variables ---
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: variable '$var' must not be null." >&2
    exit 1
  fi
done

# --- Dynamically build db_configs map ---
declare -A db_configs
for service in "${services[@]}"; do
  upper_service=$(echo "$service" | tr '[:lower:]' '[:upper:]')
  
  # Construct the variable *names*
  user_var_name="${upper_service}_DB_USER"
  pass_var_name="${upper_service}_DB_PASS"

  # Get the *values* of those variables (using indirection)
  db_user="${!user_var_name}"
  db_pass="${!pass_var_name}"
  
  # Populate the associative array
  db_configs["$service"]="${db_user}:${db_pass}"
done


# --- Function: Create Role, Database, and Grant Privileges ---
create_role_and_db() {
  local dbname="$1"
  local dbuser="$2"
  local dbpass="$3"

  echo "Initializing database '$dbname' with owner '$dbuser'..."

  # Create the role if it does not exist.
  psql --username "$POSTGRES_USER" --dbname=postgres <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = '$dbuser') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '$dbuser', '$dbpass');
  END IF;
END
\$\$;
EOSQL

  # Conditionally create the database (CREATE DATABASE must execute outside a transaction block)
  DB_EXISTS=$(psql --username "$POSTGRES_USER" --dbname=postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$dbname'")
  if [ "$DB_EXISTS" != "1" ]; then
    echo "Creating database '$dbname' with owner '$dbuser'..."
    psql --username "$POSTGRES_USER" --dbname=postgres -c "CREATE DATABASE \"$dbname\" WITH OWNER = \"$dbuser\""
  else
    echo "Database '$dbname' already exists. Skipping creation."
  fi

  # Grant privileges on the database.
  psql --username "$POSTGRES_USER" --dbname=postgres <<EOSQL
GRANT ALL PRIVILEGES ON DATABASE "$dbname" TO "$dbuser";
EOSQL

  echo "Done initializing '$dbname'."
}

# --- Main Loop: Initialize Each Database ---
echo "Starting Postgres initialization..."

for db in "${!db_configs[@]}"; do
  IFS=':' read -r dbuser dbpass <<< "${db_configs[$db]}"
  create_role_and_db "$db" "$dbuser" "$dbpass"
done

echo "Postgres initialization complete."