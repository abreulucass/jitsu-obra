-- Esquemas fundamentais para Jitsu Core e Enterprise
CREATE SCHEMA IF NOT EXISTS newjitsu;
CREATE SCHEMA IF NOT EXISTS newjitsuee;

-- Tabela KVStore (Obrigatória no esquema newjitsuee para o Rotor e módulo EE)
CREATE TABLE IF NOT EXISTS newjitsuee.kvstore (
    id TEXT NOT NULL,
    namespace TEXT NOT NULL,
    obj JSONB NOT NULL DEFAULT '{}'::jsonb,
    expire TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (id, namespace)
);

-- Permissões globais em ambos os namespaces
GRANT USAGE ON SCHEMA newjitsu TO PUBLIC;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA newjitsu TO PUBLIC;
GRANT USAGE ON SCHEMA newjitsuee TO PUBLIC;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA newjitsuee TO PUBLIC;
