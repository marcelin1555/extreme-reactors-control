"""
Gera o instalador único instalar.lua contendo todos os módulos empacotados.
"""
from pathlib import Path

def gerar():
    base = Path(__file__).resolve().parent
    files = ['config.lua', 'perifericos.lua', 'controlador.lua', 'relatorios.lua', 'interface.lua', 'startup.lua']
    linhas = [
        "-- instalar.lua",
        "-- Instalador All-in-One para Extreme Reactors Control (CC: Tweaked)",
        "-- Extrai todos os modulos automaticamente e inicia o sistema\n",
        "local arquivos = {}\n"
    ]

    for f in files:
        caminho = base / f
        conteudo = caminho.read_text(encoding='utf-8')
        linhas.append(f'arquivos["{f}"] = [====[\n{conteudo}]====]\n')

    linhas.append("""
print("================================================")
print(" Instalador: Extreme Reactors Control v2.0")
print("================================================")
if fs and not fs.exists("relatorios") then
    pcall(fs.makeDir, "relatorios")
end

for nome, conteudo in pairs(arquivos) do
    write("Instalando: " .. nome .. " ... ")
    local f = fs.open(nome, "w")
    if f then
        f.write(conteudo)
        f.close()
        print("[OK]")
    else
        print("[FALHA]")
    end
end

print("------------------------------------------------")
print("Instalacao concluida com sucesso!")
print("Deseja iniciar o sistema agora? (s/n)")
local resp = read and read() or "s"
if resp == "s" or resp == "S" or resp == "" then
    if shell then
        shell.run("startup")
    end
end
""")

    saida = base / "instalar.lua"
    saida.write_text("\n".join(linhas), encoding="utf-8")
    print(f"Instalador gerado: {saida} ({saida.stat().st_size} bytes)")

if __name__ == "__main__":
    gerar()
