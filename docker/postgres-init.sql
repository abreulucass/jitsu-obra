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
