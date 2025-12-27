-- =============================================================================
-- PostgreSQL Database Initialization for Homelab
-- =============================================================================
-- This script runs on first container startup to create databases for services.
-- Add new databases here as needed.
-- =============================================================================

-- Nextcloud database
CREATE DATABASE nextcloud;

-- Grant permissions (the main user already has superuser access)
-- Add more databases below as needed, e.g.:
-- CREATE DATABASE grafana;
-- CREATE DATABASE homeassistant;
