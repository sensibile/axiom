-- Dedicated axiom test database only. No destructive reset.
CREATE TABLE IF NOT EXISTS axiom_tenants (
  id text PRIMARY KEY,
  assignment_revision bigint NOT NULL DEFAULT 0 CHECK (assignment_revision >= 0),
  policy_generation bigint NOT NULL DEFAULT 0 CHECK (policy_generation >= 0),
  policy_release_id bigint
);
CREATE TABLE IF NOT EXISTS axiom_roles (
  tenant_id text NOT NULL REFERENCES axiom_tenants(id),
  key text NOT NULL,
  PRIMARY KEY (tenant_id, key)
);
CREATE TABLE IF NOT EXISTS axiom_nodes (
  tenant_id text NOT NULL REFERENCES axiom_tenants(id),
  key text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('person','service','team','document','project')),
  status text NOT NULL CHECK (status IN ('active','suspended')),
  PRIMARY KEY (tenant_id,key)
);
CREATE TABLE IF NOT EXISTS axiom_drafts (
  tenant_id text PRIMARY KEY REFERENCES axiom_tenants(id),
  revision bigint NOT NULL CHECK (revision > 0),
  body jsonb NOT NULL CHECK (jsonb_typeof(body) = 'object')
);
CREATE TABLE IF NOT EXISTS axiom_releases (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id text NOT NULL REFERENCES axiom_tenants(id),
  draft_revision bigint NOT NULL,
  body jsonb NOT NULL,
  digest text NOT NULL,
  actor text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tenant_id,id)
);
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'axiom_head_release_fk' AND connamespace = current_schema()::regnamespace) THEN
  ALTER TABLE axiom_tenants ADD CONSTRAINT axiom_head_release_fk
    FOREIGN KEY (id,policy_release_id) REFERENCES axiom_releases(tenant_id,id);
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS axiom_assignments (
  tenant_id text NOT NULL,
  principal text NOT NULL,
  role text NOT NULL,
  scope text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','revoked')),
  PRIMARY KEY(tenant_id,principal,role,scope),
  FOREIGN KEY(tenant_id,principal) REFERENCES axiom_nodes(tenant_id,key),
  FOREIGN KEY(tenant_id,role) REFERENCES axiom_roles(tenant_id,key),
  FOREIGN KEY(tenant_id,scope) REFERENCES axiom_nodes(tenant_id,key)
);
CREATE TABLE IF NOT EXISTS axiom_relations (
  tenant_id text NOT NULL,
  subject text NOT NULL,
  relation text NOT NULL CHECK (relation IN ('member','owner')),
  object text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','revoked')),
  PRIMARY KEY(tenant_id,subject,relation,object),
  FOREIGN KEY(tenant_id,subject) REFERENCES axiom_nodes(tenant_id,key),
  FOREIGN KEY(tenant_id,object) REFERENCES axiom_nodes(tenant_id,key)
);
CREATE TABLE IF NOT EXISTS axiom_assignment_events (
  tenant_id text NOT NULL REFERENCES axiom_tenants(id),
  revision bigint NOT NULL,
  kind text NOT NULL,
  payload jsonb NOT NULL,
  actor text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(tenant_id,revision)
);
CREATE TABLE IF NOT EXISTS axiom_publications (
  tenant_id text NOT NULL REFERENCES axiom_tenants(id),
  generation bigint NOT NULL,
  kind text NOT NULL CHECK(kind IN ('publish','rollback')),
  from_release bigint,
  to_release bigint NOT NULL,
  actor text NOT NULL,
  reason text NOT NULL,
  request_id text NOT NULL,
  fingerprint text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(tenant_id,generation),
  UNIQUE(tenant_id,request_id),
  FOREIGN KEY(tenant_id,from_release) REFERENCES axiom_releases(tenant_id,id),
  FOREIGN KEY(tenant_id,to_release) REFERENCES axiom_releases(tenant_id,id)
);
CREATE OR REPLACE FUNCTION axiom_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 RAISE EXCEPTION 'axiom immutable row' USING ERRCODE = '23514';
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['axiom_releases','axiom_assignment_events','axiom_publications'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname = t || '_immutable' AND tgrelid = to_regclass(t)) THEN
   EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION axiom_immutable()',t || '_immutable',t);
  END IF;
 END LOOP;
END $$;

-- Exact logical scopes. No placement, QueryCut, wildcard or inherited grant.
CREATE TABLE IF NOT EXISTS axiom_resource_scopes (
  tenant_id text NOT NULL,
  space_id text NOT NULL CHECK (space_id ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  scenario_id text NOT NULL CHECK (scenario_id ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  local_id text NOT NULL CHECK (local_id ~ '^[a-z][a-z0-9_.-]{0,63}$'),
  node_key text NOT NULL,
  PRIMARY KEY(tenant_id,space_id,scenario_id,local_id),
  UNIQUE(tenant_id,node_key),
  FOREIGN KEY(tenant_id,node_key) REFERENCES axiom_nodes(tenant_id,key)
);
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'axiom_resource_scopes_immutable' AND tgrelid = to_regclass('axiom_resource_scopes')) THEN
  CREATE TRIGGER axiom_resource_scopes_immutable BEFORE UPDATE OR DELETE ON axiom_resource_scopes FOR EACH ROW EXECUTE FUNCTION axiom_immutable();
 END IF;
END $$;
