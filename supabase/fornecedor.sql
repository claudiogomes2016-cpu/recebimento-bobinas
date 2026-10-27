-- =====================================================================
-- ATIVA o campo FORNECEDOR no app (Xiamen = embalagem vermelha · Nanshan = embalagem azul)
-- Como usar: Supabase → SQL Editor → New query → cole TUDO → Run. (Pode rodar mais de uma vez.)
-- Não altera nenhum dado: só cria a coluna nova (vazia nos recebimentos antigos).
-- =====================================================================
alter table public.recebimentos_bobinas add column if not exists fornecedor text;

alter table public.recebimentos_bobinas drop constraint if exists rec_fornecedor;
alter table public.recebimentos_bobinas add constraint rec_fornecedor
  check (fornecedor is null or fornecedor in ('Xiamen','Nanshan'));

create index if not exists idx_rec_fornecedor on public.recebimentos_bobinas (fornecedor);

-- avisa a API do Supabase que existe uma coluna nova (o app enxerga na hora)
notify pgrst, 'reload schema';

-- conferência: quantos recebimentos ainda estão sem fornecedor
select coalesce(fornecedor,'(sem fornecedor)') as fornecedor, count(*) as recebimentos
from public.recebimentos_bobinas group by 1 order by 1;
