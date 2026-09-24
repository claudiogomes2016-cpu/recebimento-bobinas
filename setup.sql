-- Recebimento de Bobina Metálica — execute no SQL Editor do Supabase

create table if not exists recebimentos_bobinas (
  id uuid primary key default gen_random_uuid(),
  codigo_recebimento text not null unique,
  data_hora timestamptz not null default now(),
  usuario text,
  origem text,
  transportadora text,
  placa text,
  nota_fiscal text,
  conhecimento_transporte text,
  quantidade_bobinas int check (quantidade_bobinas is null or quantidade_bobinas > 0),
  avaria boolean,
  clima text check (clima in ('sol','parcial','nublado','chuva')),
  clima_data_hora timestamptz,
  observacoes text,
  status text not null default 'EM_ANDAMENTO' check (status in ('EM_ANDAMENTO','CONCLUIDO')),
  created_at timestamptz not null default now(),
  finalized_at timestamptz
);

create table if not exists evidencias_bobinas (
  id uuid primary key default gen_random_uuid(),
  recebimento_id uuid not null references recebimentos_bobinas(id) on delete restrict,
  tipo_evidencia text not null,
  nome_arquivo text not null,
  storage_path text not null,
  url text not null,
  data_hora timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists idx_rec_data on recebimentos_bobinas (data_hora desc);
create index if not exists idx_rec_status on recebimentos_bobinas (status);
create index if not exists idx_rec_placa on recebimentos_bobinas (placa);
create index if not exists idx_evid_rec on evidencias_bobinas (recebimento_id);

alter table recebimentos_bobinas enable row level security;
alter table evidencias_bobinas enable row level security;

-- Recebimentos: ler tudo, criar, editar só enquanto não concluído, nunca apagar
create policy rec_select on recebimentos_bobinas for select to anon using (true);
create policy rec_insert on recebimentos_bobinas for insert to anon with check (status = 'EM_ANDAMENTO');
create policy rec_update on recebimentos_bobinas for update to anon using (status <> 'CONCLUIDO') with check (true);

-- Evidências: ler tudo; inserir/apagar só se o recebimento não estiver concluído; nunca alterar
create policy ev_select on evidencias_bobinas for select to anon using (true);
create policy ev_insert on evidencias_bobinas for insert to anon
  with check (exists (select 1 from recebimentos_bobinas r where r.id = recebimento_id and r.status <> 'CONCLUIDO'));
create policy ev_delete on evidencias_bobinas for delete to anon
  using (exists (select 1 from recebimentos_bobinas r where r.id = recebimento_id and r.status <> 'CONCLUIDO'));

-- Storage: bucket e políticas (pasta = código do recebimento)
insert into storage.buckets (id, name, public) values ('bobinas-evidencias', 'bobinas-evidencias', true)
on conflict (id) do nothing;

create policy bob_select on storage.objects for select to anon using (bucket_id = 'bobinas-evidencias');
create policy bob_insert on storage.objects for insert to anon with check (
  bucket_id = 'bobinas-evidencias' and exists (select 1 from recebimentos_bobinas r
    where r.codigo_recebimento = (storage.foldername(name))[1] and r.status <> 'CONCLUIDO'));
create policy bob_update on storage.objects for update to anon
  using (bucket_id = 'bobinas-evidencias' and exists (select 1 from recebimentos_bobinas r
    where r.codigo_recebimento = (storage.foldername(name))[1] and r.status <> 'CONCLUIDO'))
  with check (bucket_id = 'bobinas-evidencias');
-- Sem política de delete no storage: fotos nunca são apagadas pelo app.
