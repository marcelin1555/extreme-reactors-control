"""
Testes automatizados do Sistema de Gerenciamento do Extreme Reactors.
Executa os scripts reais em Lua contra o ambiente simulado (CC Mock) utilizando lupa.
"""

import sys
from pathlib import Path
from lupa import LuaRuntime

DIR_PROJETO = Path(__file__).resolve().parent.parent

def checar_sintaxe():
    print("--- [1/4] Verificacao de Sintaxe Lua ---")
    lua = LuaRuntime(unpack_returned_tuples=True)
    compilar = lua.eval("""
        function(codigo, nome)
            local fn, erro = load(codigo, nome)
            return (fn ~= nil), tostring(erro or '')
        end
    """)

    erros = 0
    for caminho in sorted(DIR_PROJETO.glob("*.lua")):
        nome = caminho.name
        conteudo = caminho.read_text(encoding="utf-8")
        ok, err = compilar(conteudo, "@" + nome)
        if ok:
            print(f"  [OK] {nome}")
        else:
            print(f"  [FALHA] {nome}: {err}")
            erros += 1

    assert erros == 0, f"{erros} arquivos com erro de sintaxe!"
    print("  >> Todos os arquivos .lua compilaram com sucesso!\n")

def testar_modo_passivo():
    print("--- [2/4] Teste do Modo Passivo (Somente Reator) ---")
    lua = LuaRuntime(unpack_returned_tuples=True)
    
    # Configura o path do Lua para o diretorio do projeto
    lua.execute(f"""
        package.path = package.path .. ';{DIR_PROJETO.as_posix()}/?.lua'
        local Mock = require("testes.simulador_mock")
        
        -- Cria e registra reator passivo
        local reator = Mock.criarReatorMock(false)
        peripheral.registrar("bottom", "extremereactor-reactorComputerPort", reator)
        
        local config = require("config")
        local perifericos = require("perifericos")
        local controlador = require("controlador")
        local relatorios = require("relatorios")
        local interface = require("interface")
        
        local peri = perifericos.escanear()
        assert(peri.reator ~= nil, "Reator passivo nao foi detectado!")
        assert(#peri.turbinas == 0, "Turbinas nao deveriam existir neste teste!")
        
        local ctrl = controlador.novo(config, peri)
        ctrl:determinarModo()
        assert(ctrl.modo == "PASSIVO", "Modo incorreto: " .. tostring(ctrl.modo))
        
        -- Simula 10 ciclos de controle
        for i = 1, 10 do
            reator:_simularTick()
            ctrl:atualizar()
        end
        
        -- Coleta snapshot
        local snap = ctrl:coletarSnapshot()
        assert(snap.reator.temp_combustivel > 0, "Temperatura zerada!")
        assert(snap.barras_alvo >= 0 and snap.barras_alvo <= 100, "Barras fora do limite!")
        
        -- Testa geracao de relatorio em texto
        local okRel, caminhoRel, conteudoRel = relatorios.gerarRelatorioTexto(snap, "relatorios/")
        assert(okRel == true, "Falha ao gerar relatorio!")
        assert(string.find(conteudoRel, "RELATORIO DE DESEMPENHO"), "Cabecalho do relatorio ausente!")
        assert(string.find(conteudoRel, "METRICAS GERAIS DE EFICIENCIA"), "Secao de eficiencia ausente!")
        
        -- Testa gravacao em CSV
        local okCSV = relatorios.registrarLinhaCSV(snap, "relatorios/telemetria.csv")
        assert(okCSV == true, "Falha ao gravar CSV!")
        local csvConteudo = fs._dump("relatorios/telemetria.csv")
        assert(string.find(csvConteudo, "Timestamp,Modo,Estado"), "Cabecalho CSV ausente!")
        
        -- Testa renderizacao de UI
        local ui = interface.novo(term)
        ui:renderizar(snap)
        assert(#term._linhas > 0, "Interface nao renderizou linhas!")
    """)
    print("  [OK] Modo Passivo: Deteccao, regulagem de barras, relatorios e UI funcionando perfeitamente!\n")

def testar_modo_turbinas():
    print("--- [3/4] Teste do Modo Ativo + Turbina (Sincronizacao 1800 RPM) ---")
    lua = LuaRuntime(unpack_returned_tuples=True)
    
    lua.execute(f"""
        package.path = package.path .. ';{DIR_PROJETO.as_posix()}/?.lua'
        local Mock = require("testes.simulador_mock")
        
        -- Cria reator ativo (vapor) e 1 turbina
        local reator = Mock.criarReatorMock(true)
        local turbina = Mock.criarTurbinaMock()
        turbina._rpm = 1200 -- Inicia abaixo do sweet spot
        
        peripheral.registrar("bottom", "extremereactor-reactorComputerPort", reator)
        peripheral.registrar("top", "extremereactor-turbineComputerPort", turbina)
        
        local config = require("config")
        local perifericos = require("perifericos")
        local controlador = require("controlador")
        local relatorios = require("relatorios")
        
        local peri = perifericos.escanear()
        assert(peri.reator ~= nil, "Reator nao detectado!")
        assert(#peri.turbinas == 1, "Turbina nao detectada!")
        
        local ctrl = controlador.novo(config, peri)
        ctrl:determinarModo()
        assert(ctrl.modo == "ATIVO_TURBINA", "Modo deveria ser ATIVO_TURBINA!")
        
        -- Ciclo 1: RPM baixo (1200). Indutor deve estar DESENGAJADO para acelerar rapido.
        reator:_simularTick()
        turbina:_simularTick()
        ctrl:atualizar()
        assert(turbina:getInductorEngaged() == false, "Indutor deveria estar desligado em baixa rotacao!")
        
        -- Acelera turbina para exatamente 1800 RPM
        turbina._rpm = 1800
        ctrl:atualizar()
        
        -- Indutor deve ter sido ENGAJADO e turbina sincronizada
        assert(turbina:getInductorEngaged() == true, "Indutor deveria estar ligado em 1800 RPM!")
        assert(ctrl.stats.turbinas_sincronizadas == 1, "Turbina deveria estar classificada como sincronizada!")
        
        -- Gera relatorio com turbina
        local snap = ctrl:coletarSnapshot()
        local okRel, caminhoRel, conteudoRel = relatorios.gerarRelatorioTexto(snap, "relatorios/")
        assert(okRel == true, "Falha ao gerar relatorio com turbina!")
        assert(string.find(conteudoRel, "1800 RPM"), "Relatorio nao menciona 1800 RPM!")
        assert(string.find(conteudoRel, "ENGAJADO"), "Relatorio nao registrou indutor engajado!")
    """)
    print("  [OK] Modo Turbina: Partida livre, engajamento a 1800 RPM e relatorio integrados!\n")

def testar_benchmark():
    print("--- [4/4] Teste da Ferramenta de Benchmark / Curva de Rendimento ---")
    lua = LuaRuntime(unpack_returned_tuples=True)
    
    lua.execute(f"""
        package.path = package.path .. ';{DIR_PROJETO.as_posix()}/?.lua'
        local Mock = require("testes.simulador_mock")
        
        local reator = Mock.criarReatorMock(false)
        peripheral.registrar("bottom", "extremereactor-reactorComputerPort", reator)
        
        local config = require("config")
        local perifericos = require("perifericos")
        local controlador = require("controlador")
        local relatorios = require("relatorios")
        
        local peri = perifericos.escanear()
        local ctrl = controlador.novo(config, peri)
        
        -- Executa benchmark
        local res, caminho, txt = relatorios.executarBenchmark(ctrl, function(msg)
            -- callback
        end)
        
        assert(res ~= nil, "Benchmark retornou nulo!")
        assert(#res == 5, "Deveriam ser 5 patamares de teste (0, 20, 40, 60, 80)!")
        assert(string.find(txt, "RESULTADO DO BENCHMARK"), "Relatorio de benchmark sem cabecalho!")
        assert(string.find(txt, "PONTO DE MAXIMA EFICIENCIA"), "Ponto otimo nao identificado!")
    """)
    print("  [OK] Benchmark: Curva de teste e deteccao de ponto otimo executados com sucesso!\n")

if __name__ == "__main__":
    try:
        checar_sintaxe()
        testar_modo_passivo()
        testar_modo_turbinas()
        testar_benchmark()
        print("=========================================================")
        print("  TODOS OS TESTES AUTOMATIZADOS PASSARAM COM SUCESSO!     ")
        print("=========================================================")
    except Exception as e:
        print(f"\n[ERRO CRITICO] Falha no teste: {e}")
        sys.exit(1)
