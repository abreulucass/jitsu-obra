-- Esquemas fundamentais para Jitsu Core e Enterprise
-- Usaremos 'newjitsu' como o esquema principal (Console/Core) e 'newjitsuee' para o Enterprise (Rotor)
CREATE SCHEMA IF NOT EXISTS newjitsu;
CREATE SCHEMA IF NOT EXISTS newjitsuee;

-- Configurar o search_path global para garantir resolução de nomes rápida
-- Priorizamos o 'newjitsu' para que o Console encontre suas tabelas CamelCase
ALTER DATABASE postgres SET search_path TO newjitsu, public, newjitsuee;

-- Tabela KVStore (Obrigatória no esquema newjitsuee para o Rotor e módulo EE)
CREATE TABLE IF NOT EXISTS newjitsuee.kvstore (
    id TEXT NOT NULL,
    namespace TEXT NOT NULL,
    obj JSONB NOT NULL DEFAULT '{}'::jsonb,
    expire TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (id, namespace)
);

-- Permissões totais para o usuário postgres em todos os esquemas
GRANT ALL PRIVILEGES ON SCHEMA newjitsu TO postgres;
GRANT ALL PRIVILEGES ON SCHEMA newjitsuee TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA newjitsu TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA newjitsuee TO postgres;

-- =========================================================================
-- SEEDING PERMANENTE E PORTÁTIL (ADMIN JITSU)
-- =========================================================================
-- Garante que o usuário administrativo administrativo nasça com o acesso correto
-- no esquema 'newjitsu' em qualquer servidor (Dokploy/VPS).

DO $$ 
DECLARE 
    v_user_id TEXT := 'ec627411bf9246658916790675d929ca93ba97321bfce039960a806f99919776';
    v_email TEXT := 'osmar@obra.ag';
    v_workspace_id TEXT := v_user_id || '-ws';
    v_password_hash TEXT := '$2b$12$N9qo8uLOickgx2ZMRZoMyeIjZAgNIvU6xL.0j2K2mYp7Z7YI6l6lG'; -- Hash para 'obra123456'
BEGIN
    -- 1. Inserir UserProfile (Dono)
    INSERT INTO newjitsu."UserProfile" (id, email, name, admin, "loginProvider", "externalId", "updatedAt")
    VALUES (v_user_id, v_email, 'Osmar', true, 'credentials', v_email, NOW())
    ON CONFLICT (id) DO UPDATE SET "externalId" = v_email;

    -- 2. Inserir Senha (obra123456)
    INSERT INTO newjitsu."UserPassword" (id, "userId", hash, "updatedAt")
    VALUES (gen_random_uuid()::text, v_user_id, v_password_hash, NOW())
    ON CONFLICT ("userId") DO NOTHING;

    -- 3. Inserir Workspace (Main)
    INSERT INTO newjitsu."Workspace" (id, name, slug, "updatedAt")
    VALUES (v_workspace_id, 'Main Workspace', 'main', NOW())
    ON CONFLICT (id) DO NOTHING;

    -- 4. Garantir Vínculo de Owner (WorkspaceAccess)
    INSERT INTO newjitsu."WorkspaceAccess" ("workspaceId", "userId", role, "updatedAt", "createdAt")
    VALUES (v_workspace_id, v_user_id, 'owner', NOW(), NOW())
    ON CONFLICT ("workspaceId", "userId") DO NOTHING;

    RAISE NOTICE 'Seeding administrativo concluído para %', v_email;
END $$;
