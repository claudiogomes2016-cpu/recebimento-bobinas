-- Execute DEPOIS do setup.sql. Fecha o acesso anônimo e move as regras críticas para o banco.

-- 1. Remove o acesso anônimo
drop policy if exists rec_select on recebimentos_bobinas;
drop policy if exists rec_insert on recebimentos_bobinas;
drop policy if exists rec_update on recebimentos_bobinas;
drop policy if exists ev_select on evidencias_bobinas;
drop policy if exists ev_insert on evidencias_bobinas;
drop policy if exists ev_delete on evidencias_bobinas;
drop policy if exists bob_select on storage.objects;
drop policy if exists bob_insert on storage.objects;
drop policy if exists bob_update on storage.objects;
revoke all on recebimentos_bobinas, evidencias_bobinas from anon;

-- 2. Colunas e restrições
alter table recebimentos_bobinas add column if not exists user_id uuid default auth.uid();
alter table evidencias_bobinas alter column url drop not null;  -- links agora são assinados na hora, não ficam no banco
alter table evidencias_bobinas drop constraint if exists ev_tipo;
alter table evidencias_bobinas add constraint ev_tipo check (tipo_evidencia in
  ('frente','lado-esquerdo','lado-direito','traseira','parte-superior','pallet','carreta','placa','nota-fiscal','conhecimento'));
create unique index if not exists ux_ev_tipo on evidencias_bobinas (recebimento_id, tipo_evidencia);

-- 3. Políticas: somente usuários autenticados
create policy rec_select on recebimentos_bobinas for select to authenticated using (true);
create policy rec_insert on recebimentos_bobinas for insert to authenticated with check (status = 'EM_ANDAMENTO');
create policy rec_update on recebimentos_bobinas for update to authenticated using (status <> 'CONCLUIDO') with check (true);
create policy ev_select on evidencias_bobinas for select to authenticated using (true);
create policy ev_insert on evidencias_bobinas for insert to authenticated with check (exists (
  select 1 from recebimentos_bobinas r where r.id = recebimento_id and r.status <> 'CONCLUIDO'
  and storage_path like r.codigo_recebimento || '/%'));
create policy ev_delete on evidencias_bobinas for delete to authenticated using (exists (
  select 1 from recebimentos_bobinas r where r.id = recebimento_id and r.status <> 'CONCLUIDO'));

create policy bob_select on storage.objects for select to authenticated using (bucket_id = 'bobinas-evidencias');
create policy bob_insert on storage.objects for insert to authenticated with check (bucket_id = 'bobinas-evidencias'
  and exists (select 1 from recebimentos_bobinas r where r.codigo_recebimento = (storage.foldername(name))[1] and r.status <> 'CONCLUIDO'));
create policy bob_update on storage.objects for update to authenticated using (bucket_id = 'bobinas-evidencias'
  and exists (select 1 from recebimentos_bobinas r where r.codigo_recebimento = (storage.foldername(name))[1] and r.status <> 'CONCLUIDO'))
  with check (bucket_id = 'bobinas-evidencias');

-- 4. Bucket privado, só JPEG, máximo 10 MB
update storage.buckets set public = false, file_size_limit = 10485760, allowed_mime_types = array['image/jpeg']
where id = 'bobinas-evidencias';

-- 4b. Nomes de exibição dos operadores (aparecem nos relatórios e no WhatsApp)
create table if not exists perfis (email text primary key, nome text not null);
alter table perfis enable row level security;
revoke all on perfis from anon;
drop policy if exists perfis_select on perfis;
create policy perfis_select on perfis for select to authenticated using (true);
insert into perfis (email, nome) values
 ('claudio.gomes@example.com','Claudio Gomes'),
 ('rickson.carmo@example.com','Rickson Carmo'),
 ('rafael.cunha@example.com','Rafael Cunha'),
 ('treslec@ball.com','Expedição / InHaus')
on conflict (email) do update set nome = excluded.nome;

-- 5. Regras críticas no servidor (não dependem do navegador)
create or replace function trg_recebimento() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.user_id := auth.uid();
    new.usuario := coalesce((select nome from perfis where email = lower(auth.jwt() ->> 'email')),
      initcap(replace(split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1), '.', ' ')));
    new.status := 'EM_ANDAMENTO'; new.finalized_at := null; new.created_at := now();
  else
    if old.status = 'CONCLUIDO' then raise exception 'Recebimento concluído não pode ser alterado'; end if;
    new.id := old.id; new.codigo_recebimento := old.codigo_recebimento; new.user_id := old.user_id;
    new.usuario := old.usuario; new.created_at := old.created_at; new.data_hora := old.data_hora;
    if new.status = 'CONCLUIDO' then
      if (select count(distinct tipo_evidencia) from evidencias_bobinas where recebimento_id = old.id) < 10
         or (select count(*) from storage.objects where bucket_id = 'bobinas-evidencias'
             and name like old.codigo_recebimento || '/%') < 10
      then raise exception 'As 10 evidências precisam estar salvas na nuvem'; end if;
      if coalesce(new.transportadora,'') = '' or coalesce(new.placa,'') = '' or coalesce(new.nota_fiscal,'') = ''
         or coalesce(new.conhecimento_transporte,'') = '' or coalesce(new.origem,'') = ''
         or new.avaria is null or new.clima is null or coalesce(new.quantidade_bobinas,0) < 1
      then raise exception 'Dados obrigatórios incompletos'; end if;
      new.finalized_at := now();
    else
      new.finalized_at := null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists t_recebimento on recebimentos_bobinas;
create trigger t_recebimento before insert or update on recebimentos_bobinas
  for each row execute function trg_recebimento();
