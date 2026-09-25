-- Rode UMA vez no Supabase: SQL Editor → New query → cole tudo → Run.
-- Libera Editar e Excluir recebimentos para quem está logado no app.

drop policy if exists "app editar recebimentos"  on public.recebimentos_bobinas;
drop policy if exists "app excluir recebimentos" on public.recebimentos_bobinas;
drop policy if exists "app excluir evidencias"   on public.evidencias_bobinas;
drop policy if exists "app excluir fotos"        on storage.objects;

create policy "app editar recebimentos"  on public.recebimentos_bobinas
  for update to authenticated using (true) with check (true);
create policy "app excluir recebimentos" on public.recebimentos_bobinas
  for delete to authenticated using (true);
create policy "app excluir evidencias"   on public.evidencias_bobinas
  for delete to authenticated using (true);
create policy "app excluir fotos"        on storage.objects
  for delete to authenticated using (bucket_id = 'bobinas-evidencias');
