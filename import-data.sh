#!/bin/bash

# Database Import Script - Comprehensive version
# This script handles both .dump and .sql files and creates tables with data

echo "=== Database Import Script ==="
echo "Starting database import process..."

# Function to check if container is ready
check_db_ready() {
    local container_name=$1
    local db_name=$2
    local max_attempts=30
    local attempt=1
    
    echo "Checking if $container_name is ready..."
    while [ $attempt -le $max_attempts ]; do
        if docker exec $container_name pg_isready -U postgres -d $db_name >/dev/null 2>&1; then
            echo "$container_name is ready!"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts - waiting for $container_name..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "ERROR: $container_name failed to become ready!"
    return 1
}

# Wait for databases to be ready
check_db_ready "merchant-db" "admin" || exit 1
check_db_ready "transaction-db" "transactions-log" || exit 1

echo "Both databases are ready. Starting import..."

# Function to import database
import_database() {
    local container_name=$1
    local db_name=$2
    local dump_file=$3
    local sql_file=$4
    local db_type=$5
    
    echo "=== Importing $db_type database ==="
    
    # Check for .dump file first (custom format)
    if [ -f "$dump_file" ]; then
        echo "Found custom format dump file: $dump_file"
        echo "Copying dump file to container..."
        docker cp "$dump_file" "$container_name:/tmp/import.dump"
        
        echo "Restoring database from custom dump..."
        docker exec $container_name pg_restore \
            --host=localhost \
            --port=5432 \
            --username=postgres \
            --dbname=$db_name \
            --no-password \
            --verbose \
            --clean \
            --if-exists \
            --no-owner \
            --no-privileges \
            /tmp/import.dump
            
        if [ $? -eq 0 ]; then
            echo "✅ $db_type database imported successfully from dump file!"
        else
            echo "❌ Error importing $db_type database from dump file"
        fi
        
    # Check for .sql file
    elif [ -f "$sql_file" ]; then
        echo "Found SQL file: $sql_file"
        echo "Copying SQL file to container..."
        docker cp "$sql_file" "$container_name:/tmp/import.sql"
        
        echo "Importing database from SQL file..."
        docker exec $container_name psql \
            --host=localhost \
            --port=5432 \
            --username=postgres \
            --dbname=$db_name \
            --file=/tmp/import.sql \
            --echo-errors \
            --quiet
            
        if [ $? -eq 0 ]; then
            echo "✅ $db_type database imported successfully from SQL file!"
        else
            echo "❌ Error importing $db_type database from SQL file"
        fi
    else
        echo "❌ No import file found for $db_type database!"
        echo "Looking for: $dump_file or $sql_file"
        echo "Available files in ./db-export-06-08-2025/:"
        ls -la ./db-export-06-08-2025/ 2>/dev/null || echo "Directory not found"
    fi
}

# Import merchant database
import_database "merchant-db" "admin" \
    "./db-export-06-08-2025/merchant-db-export.dump" \
    "./db-export-06-08-2025/merchant-db-export.sql" \
    "Merchant"

# Try alternative filenames for merchant database
if [ ! -f "./db-export-06-08-2025/merchant-db-export.dump" ] && [ ! -f "./db-export-06-08-2025/merchant-db-export.sql" ]; then
    echo "Trying alternative merchant database filenames..."
    import_database "merchant-db" "admin" \
        "./db-export-06-08-2025/merchant-db-export-$(date +%Y%m%d).dump" \
        "./db-export-06-08-2025/merchant-db-export-$(date +%Y%m%d).sql" \
        "Merchant"
fi

# Import transaction database
import_database "transaction-db" "transactions-log" \
    "./db-export-06-08-2025/transaction-db-export.dump" \
    "./db-export-06-08-2025/transaction-db-export.sql" \
    "Transaction"

# Try alternative filenames for transaction database
if [ ! -f "./db-export-06-08-2025/transaction-db-export.dump" ] && [ ! -f "./db-export-06-08-2025/transaction-db-export.sql" ]; then
    echo "Trying alternative transaction database filenames..."
    import_database "transaction-db" "transactions-log" \
        "./db-export-06-08-2025/transaction-db-export-$(date +%Y%m%d).dump" \
        "./db-export-06-08-2025/transaction-db-export-$(date +%Y%m%d).sql" \
        "Transaction"
fi

echo "=== Import process completed! ==="

# Verify imports by checking tables
echo "=== Verifying Merchant Database ==="
docker exec merchant-db psql -U postgres -d admin -c "\dt+" 2>/dev/null || echo "No tables found or connection error"

echo "=== Verifying Transaction Database ==="
docker exec transaction-db psql -U postgres -d transactions-log -c "\dt+" 2>/dev/null || echo "No tables found or connection error"

# Show row counts if tables exist
echo "=== Checking data in tables ==="
echo "Merchant database table counts:"
docker exec merchant-db psql -U postgres -d admin -c "
SELECT schemaname,tablename,n_tup_ins as \"rows\" 
FROM pg_stat_user_tables 
ORDER BY n_tup_ins DESC;" 2>/dev/null || echo "No user tables found"

echo "Transaction database table counts:"
docker exec transaction-db psql -U postgres -d transactions-log -c "
SELECT schemaname,tablename,n_tup_ins as \"rows\" 
FROM pg_stat_user_tables 
ORDER BY n_tup_ins DESC;" 2>/dev/null || echo "No user tables found"

echo "=== Import verification completed ==="