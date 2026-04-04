-- Esquemas fundamentais para Jitsu Core e Enterprise
-- Usaremos o 'public' para o Console (Core) e 'newjitsuee' para o Enterprise (Rotor)
CREATE SCHEMA IF NOT EXISTS public;
CREATE SCHEMA IF NOT EXISTS newjitsuee;

-- Configurar o search_path global para garantir resolução de nomes rápida
ALTER DATABASE postgres SET search_path TO public, newjitsuee, "$user";

-- Tabela KVStore (Obrigatória no esquema newjitsuee para o Rotor e módulo EE)
-- Nota: O Rotor busca explicitamente por newjitsuee.kvstore
CREATE TABLE IF NOT EXISTS newjitsuee.kvstore (
    id TEXT NOT NULL,
    namespace TEXT NOT NULL,
    obj JSONB NOT NULL DEFAULT '{}'::jsonb,
    expire TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (id, namespace)
);

-- Permissões globais para evitar erros de acesso
GRANT ALL PRIVILEGES ON SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON SCHEMA newjitsuee TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA newjitsuee TO postgres;
