import random, sys
random.seed(5)
cidades = ['São Paulo','Rio de Janeiro','Recife','Curitiba','Porto Alegre','Salvador','Belo Horizonte','Belém']
cats = ['Eletrônicos','Livros','Alimentos','Vestuário','Casa & Jardim']
status = ['Pago','Pendente','Cancelado','Enviado']
nomes = ['Ana Souza','Bruno Lima','Carla Dias','Diego Alves','Elisa Rocha','Felipe Nunes','Gabriela Melo','Heitor Pinto','Isabela Cruz','João Vidal']
path = sys.argv[1]
blocks = int(sys.argv[2])      # 100k linhas por bloco
with open(path, 'w', encoding='utf-8', newline='') as f:
    f.write('pedido;cliente;cidade;categoria;quantidade;valor_total;data_pedido;status;observacao\n')
    for b in range(blocks):
        rows = []
        for i in range(1000):
            rows.append('PED-%05d%05d;%s;%s;%s;%d;%s;%02d/%02d/202%d;%s;%s' % (
                b, i, random.choice(nomes), random.choice(cidades), random.choice(cats),
                random.randint(1, 20), ('%.2f' % random.uniform(15, 4800)).replace('.', ','),
                random.randint(1, 28), random.randint(1, 12), random.randint(3, 5),
                random.choice(status),
                random.choice(['', 'entrega expressa', 'cliente VIP', 'pedido com "urgência", conferir'])))
        f.write('\n'.join(rows) + '\n')
        if b % 25 == 0:
            print('bloco %d/%d' % (b, blocks), flush=True)
print('pronto')
