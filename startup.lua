-- startup.lua
-- Inicializador do Sistema de Gerenciamento Extreme Reactors

local config = require("config")
local perifericos = require("perifericos")
local controlador = require("controlador")
local relatorios = require("relatorios")
local interface = require("interface")

local args = { ... }

-- Ajuda rápida por linha de comando
if args[1] == "--ajuda" or args[1] == "-h" or args[1] == "--help" then
    print("=== Extreme Reactors Control ===")
    print("Uso: startup [opcoes]")
    print("  startup              Inicia o painel interativo")
    print("  startup --relatorio  Gera um relatorio instantaneo e sai")
    print("  startup --benchmark  Executa o teste da curva de rendimento e sai")
    return
end

-- Carrega arquivo de configuracao salvo no disco, se existir
config.carregar()

-- Escaneia os componentes fisicos
print("Escaneando perifericos...")
local peri = perifericos.escanear()

if not peri.reator then
    print("\n[ERRO] Reator nao detectado!")
    print("Certifique-se de que ha um 'Reactor Computer Port' adjacente ao computador")
    print("ou conectado atraves de um Wired Modem ativo.")
    return
end

print("Reator detectado: " .. peri.reator.nome)
print("Turbinas detectadas: " .. tostring(#peri.turbinas))
if peri.monitor then
    print("Monitor externo detectado!")
    peri.monitor.setTextScale(0.5)
end

-- Inicializa o controlador
local ctrl = controlador.novo(config, peri)
ctrl:determinarModo()

-- Se o usuario pediu apenas para gerar um relatorio avulso
if args[1] == "--relatorio" then
    local dados = ctrl:coletarSnapshot()
    local ok, caminho = relatorios.gerarRelatorioTexto(dados)
    if ok then
        print("[SUCESSO] Relatorio gerado em: " .. caminho)
    else
        print("[ERRO] Falha ao salvar relatorio.")
    end
    return
end

-- Se o usuario pediu para rodar benchmark direto
if args[1] == "--benchmark" then
    print("Iniciando Benchmark da Curva de Eficiencia...")
    local resultados, caminho = relatorios.executarBenchmark(ctrl, function(msg)
        print(">> " .. msg)
    end)
    print("\n[CONCLUIDO] Benchmark salvo em: " .. tostring(caminho))
    return
end

-- Instancia a interface visual (Terminal + Monitor)
local uiTerm = interface.novo(term)
local uiMon = peri.monitor and interface.novo(peri.monitor) or nil

local executando = true
local proximoTickCSV = 0

-- Rotina 1: Loop de Controle & Atualizacao de Telas
local function rotinaControle()
    while executando do
        ctrl:atualizar()
        local dados = ctrl:coletarSnapshot()

        -- Registra telemetria em CSV se habilitado
        local agora = os.clock and os.clock() or 0
        local cfgSis = config.ativo.sistema
        if cfgSis.intervalo_telemetria_csv > 0 and agora >= proximoTickCSV then
            relatorios.registrarLinhaCSV(dados, cfgSis.arquivo_telemetria)
            proximoTickCSV = agora + cfgSis.intervalo_telemetria_csv
        end

        -- Renderiza na tela do computador
        uiTerm:renderizar(dados)

        -- Se houver monitor externo, renderiza nele tambem
        if uiMon then
            uiMon:renderizar(dados)
        end

        os.sleep(cfgSis.intervalo_tick)
    end
end

-- Rotina 2: Captura de Teclas Interativas
local function rotinaTeclado()
    while executando do
        local evento, tecla, isHeld = os.pullEvent("key")

        -- Tecla [R]: Gerar Relatorio Instantaneo
        if tecla == keys.r then
            local dados = ctrl:coletarSnapshot()
            local ok, caminho = relatorios.gerarRelatorioTexto(dados)
            local msg = ok and ("Relatorio salvo: " .. fs.getName(caminho)) or "Erro ao salvar relatorio!"
            uiTerm:notificar(msg)
            if uiMon then uiMon:notificar(msg) end

        -- Tecla [C]: Executar Benchmark
        elseif tecla == keys.c then
            uiTerm:notificar("Iniciando Benchmark... Aguarde estabilizacao")
            if uiMon then uiMon:notificar("Benchmark em andamento...") end
            
            local res, caminho = relatorios.executarBenchmark(ctrl, function(msg)
                uiTerm:notificar(msg)
                if uiMon then uiMon:notificar(msg) end
                local dados = ctrl:coletarSnapshot()
                uiTerm:renderizar(dados)
            end)

            local msgFim = "Benchmark concluido: " .. fs.getName(caminho)
            uiTerm:notificar(msgFim)
            if uiMon then uiMon:notificar(msgFim) end

        -- Tecla [E]: SCRAM Manual de Emergencia
        elseif tecla == keys.e then
            ctrl:alternarScramManual()
            local msgScram = ctrl.scram_manual and "SCRAM ATIVADO PELO OPERADOR!" or "SCRAM REDEFINIDO."
            uiTerm:notificar(msgScram)
            if uiMon then uiMon:notificar(msgScram) end

        -- Tecla [Q]: Sair do programa
        elseif tecla == keys.q then
            executando = false
        end
    end
end

-- Executa concorrentemente o loop de controle e o listener de teclado
parallel.waitForAny(rotinaControle, rotinaTeclado)

-- Limpeza ao sair
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Extreme Reactors Control finalizado.")
print("Relatorios e telemetrias arquivados em: relatorios/")
