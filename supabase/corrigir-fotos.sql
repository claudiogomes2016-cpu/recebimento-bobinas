-- =====================================================================
-- CORRIGE o erro ao salvar fotos:
--   "new row violates row-level security policy for table evidencias_bobinas [42501]"
--
-- Como usar: Supabase → SQL Editor → New query → cole TUDO → Run. (Pode rodar mais de uma vez.)
-- Não apaga nenhum dado: só refaz as REGRAS DE ACESSO (RLS) das fotos.
--
-- Regra que fica valendo (para quem está logado no app):
--   • ver fotos: sempre
--   • gravar/trocar foto: só enquanto o recebimento NÃO está concluído
--   • apagar registro de foto: liberado (usado ao trocar foto e no Excluir)
-- =====================================================================

-- 0) ANTES: mostra as regras atuais (aparece no resultado; útil para conferir)
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where tablename in ('evidencias_bobinas','recebimentos_bobinas')
   or (schemaname='storage' and tablename='objects')
order by tablename, policyname;

-- 1) Funções de apoio. "security definer" = a checagem lê o recebimento sem esbarrar
--    em outras regras de acesso (causa comum desse erro).
create or replace function public.rec_aberto(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from recebimentos_bobinas r
                 where r.id = p_id and coalesce(r.status,'') <> 'CONCLUIDO')
$$;
create or replace function public.rec_aberto_cod(p_cod text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from recebimentos_bobinas r
                 where r.codigo_recebimento = p_cod and coalesce(r.status,'') <> 'CONCLUIDO')
$$;
grant execute on function public.rec_aberto(uuid), public.rec_aberto_cod(text) to authenticated;

-- 2) Tabela evidencias_bobinas: remove TODAS as regras antigas e recria as certas
do $$ declare p record; begin
  for p in select policyname from pg_policies
           where schemaname='public' and tablename='evidencias_bobinas' loop
    execute format('drop policy %I on public.evidencias_bobinas', p.policyname);
  end loop;
end $$;
alter table public.evidencias_bobinas enable row level security;
grant select, insert, update, delete on public.evidencias_bobinas to authenticated;

create policy ev_select on public.evidencias_bobinas for select to authenticated using (true);
create policy ev_insert on public.evidencias_bobinas for insert to authenticated
  with check (public.rec_aberto(recebimento_id));
create policy ev_update on public.evidencias_bobinas for update to authenticated
  using (public.rec_aberto(recebimento_id)) with check (public.rec_aberto(recebimento_id));
create policy ev_delete on public.evidencias_bobinas for delete to authenticated using (true);

-- 3) Tipos de foto aceitos (inclui placa da carreta, etiquetas, avaria e bobina 2).
--    NOT VALID = não confere as linhas antigas, só as novas.
alter table public.evidencias_bobinas drop constraint if exists ev_tipo;
alter table public.evidencias_bobinas add constraint ev_tipo check (tipo_evidencia in (
  'placa','placa-carreta','carreta',
  'frente','lado-esquerdo','lado-direito','traseira','parte-superior','etiqueta-1','etiqueta-2','avaria',
  'frente-b2','lado-esquerdo-b2','lado-direito-b2','traseira-b2','parte-superior-b2','etiqueta-1-b2','etiqueta-2-b2','avaria-b2',
  'pallet','nota-fiscal','conhecimento')) not valid;

-- 4) Arquivos das fotos (Storage, bucket bobinas-evidencias): recria só as regras deste bucket
do $$ declare p record; begin
  for p in select policyname from pg_policies
           where schemaname='storage' and tablename='objects'
             and (coalesce(qual,'') || coalesce(with_check,'')) like '%bobinas-evidencias%' loop
    execute format('drop policy %I on storage.objects', p.policyname);
  end loop;
end $$;
create policy bob_select on storage.objects for select to authenticated
  using (bucket_id = 'bobinas-evidencias');
create policy bob_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'bobinas-evidencias' and public.rec_aberto_cod((storage.foldername(name))[1]));
create policy bob_update on storage.objects for update to authenticated
  using (bucket_id = 'bobinas-evidencias' and public.rec_aberto_cod((storage.foldername(name))[1]))
  with check (bucket_id = 'bobinas-evidencias');
create policy bob_delete on storage.objects for delete to authenticated
  using (bucket_id = 'bobinas-evidencias');

-- 5) DEPOIS: confira o recebimento que estava dando erro (troque o código se quiser)
select codigo_recebimento, status, usuario, data_hora,
       (select count(*) from evidencias_bobinas e where e.recebimento_id = r.id) as fotos_registradas
from recebimentos_bobinas r
order by data_hora desc
limit 5;
