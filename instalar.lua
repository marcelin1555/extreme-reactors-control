-- instalar.lua
-- Instalador All-in-One para Extreme Reactors Control (CC: Tweaked)
-- Extrai todos os modulos automaticamente e inicia o sistema

local arquivos = {}

arquivos["config.lua"] = [====[
-- config.lua
-- Configuracoes do Sistema de Gerenciamento de Extreme Reactors
-- Todas as variaveis possuem valores padrao otimizados para maxima eficiencia

local M = {}

-- Configuracoes Padrao
M.padrao = {
    -- Modo de operacao: "auto" (detecta passivo ou ativo+turbina), "passivo", "ativo"
    modo_operacao = "auto",

    -- Perfil de Operação: "eficiencia" (menor queima de combustível) ou "potencia" (máxima geração de RF/t e vapor)
    perfil_operacao = "eficiencia",

    -- Parametros do Reator
    reator = {
        -- Limiares do Buffer de Energia (% de 0 a 100)
        buffer_energia_min = 25,   -- Se cair abaixo, aumenta producao
        buffer_energia_max = 88,   -- Se passar disso, reduz/desliga para evitar perda
        buffer_energia_alvo = 60,  -- Ponto de equilibrio da modulacao suave

        -- Parametros Termicos (°C)
        temp_alvo_combustivel = 650,  -- Temperatura ideal para consumo eficiente (Perfil Eficiência)
        temp_max_segura = 950,        -- Acima disso o consumo cresce desproporcionalmente
        temp_max_potencia = 1350,     -- Limite termico em modo Potencia (trabalha quente com seguranca)
        temp_scram = 1500,            -- Desligamento de emergencia forcado

        -- Barras de Controle (%)
        min_nivel_barras = 0,    -- 0% = barras recolhidas (potencia maxima)
        max_nivel_barras = 100,  -- 100% = barras totalmente inseridas (parada)
        passo_ajuste = 2,        -- Sensibilidade do ajuste por ciclo

        -- Manutencao
        auto_ejetar_lixo = true, -- Ejetar cianita/residuos automaticamente
    },

    -- Parametros das Turbinas
    turbina = {
        -- Rotação Alvo (1800 RPM é o ponto ideal clássico de aerodinâmica)
        rpm_alvo = 1800,
        rpm_tolerancia = 12,          -- Faixa estavel (1788 a 1812 RPM)
        rpm_engajar_indutor = 1792,   -- Engaja bobina quando atingir esse valor
        rpm_desengajar_indutor = 1680, -- Desengaja se cair abaixo para retomar giro rápido
        
        -- Controle de Fluxo de Vapor
        vazao_max_limite = 2000,      -- Limite padrao de mB/t de vapor
        passo_vazao = 25,             -- Ajuste fino de mB/t por tick de controle
        modo_respiro = "overflow",    -- "none", "overflow", "all"
    },

    -- Parametros do Sistema e Relatórios
    sistema = {
        intervalo_tick = 0.5,            -- Frequencia do loop de controle em segundos
        intervalo_telemetria_csv = 5,    -- Salva linha em CSV a cada X segundos (0 para desligar)
        arquivo_telemetria = "relatorios/telemetria.csv",
        pasta_relatorios = "relatorios/",
        manter_historico_pontos = 60,    -- Pontos guardados em memoria para calculo de medias
    }
}

-- Tabela ativa de configuracao
M.ativo = {}

-- Copia recursiva de tabelas
local function clonar(origem)
    local copia = {}
    for k, v in pairs(origem) do
        if type(v) == "table" then
            copia[k] = clonar(v)
        else
            copia[k] = v
        end
    end
    return copia
end

-- Mescla configuracoes parciais sobre a base
local function mesclar(base, nova)
    for k, v in pairs(nova) do
        if type(v) == "table" and type(base[k]) == "table" then
            mesclar(base[k], v)
        else
            base[k] = v
        end
    end
end

-- Inicializa com os valores padrao
M.ativo = clonar(M.padrao)

-- Caminho do arquivo no disco
local ARQUIVO_CFG = "config_reator.txt"

function M.salvar(caminho)
    caminho = caminho or ARQUIVO_CFG
    local arq = fs and fs.open(caminho, "w")
    if arq then
        arq.write(textutils.serialize(M.ativo))
        arq.close()
        return true
    end
    return false
end

function M.carregar(caminho)
    caminho = caminho or ARQUIVO_CFG
    if fs and fs.exists(caminho) then
        local arq = fs.open(caminho, "r")
        if arq then
            local conteudo = arq.readAll()
            arq.close()
            local dados = textutils.unserialize(conteudo)
            if type(dados) == "table" then
                mesclar(M.ativo, dados)
                return true
            end
        end
    end
    return false
end

return M
]====]

arquivos["perifericos.lua"] = [====[
-- perifericos.lua
-- Descoberta e abstracao unificada de perifericos do Extreme Reactors e Big Reactors

local M = {}

-- Tipos conhecidos de perifericos
local TIPOS_REATOR = {
    ["extremereactor-reactorComputerPort"] = true,
    ["BigReactors-Reactor"] = true,
    ["BigReactors-ReactorComputerPort"] = true,
}

local TIPOS_TURBINA = {
    ["extremereactor-turbineComputerPort"] = true,
    ["BigReactors-Turbine"] = true,
    ["BigReactors-TurbineComputerPort"] = true,
}

-- Verifica se um objeto parece ser um reator (mesmo com nomes customizados)
local function pareceReator(p)
    if not p or type(p) ~= "table" then return false end
    return (p.getFuelTemperature ~= nil) and (p.getNumberOfControlRods ~= nil or p.getControlRodsLevels ~= nil)
end

-- Verifica se um objeto parece ser uma turbina
local function pareceTurbina(p)
    if not p or type(p) ~= "table" then return false end
    return (p.getRotorSpeed ~= nil) and (p.setInductorEngaged ~= nil)
end

-- Wrapper seguro para chamar funcoes que podem nao existir em versoes antigas
local function seguro(obj, metodo, padrao, ...)
    if obj and type(obj[metodo]) == "function" then
        local ok, res = pcall(obj[metodo], ...)
        if not ok then
            -- Fallback para mocks ou tabelas OOP que esperam self
            local ok2, res2 = pcall(obj[metodo], obj, ...)
            if ok2 then
                if res2 ~= nil then return res2 else return padrao end
            end
        else
            if res ~= nil then return res else return padrao end
        end
    end
    return padrao
end

-- Cria wrapper padronizado para o Reator
local function envolverReator(p, nome)
    local w = {
        _raw = p,
        nome = nome or "Reator",
    }

    function w.ativo()
        return seguro(p, "getActive", false)
    end

    function w.setAtivo(estado)
        return seguro(p, "setActive", false, estado and true or false)
    end

    function w.tempCombustivel()
        return math.floor(seguro(p, "getFuelTemperature", 0) * 10) / 10
    end

    function w.tempCarcaca()
        return math.floor(seguro(p, "getCasingTemperature", 0) * 10) / 10
    end

    function w.energiaArmazenada()
        return seguro(p, "getEnergyStored", 0)
    end

    function w.energiaCapacidade()
        local cap = seguro(p, "getEnergyCapacity", 0)
        if cap <= 0 then cap = 10000000 end -- Fallback de segurança (10M RF)
        return cap
    end

    function w.energiaPorcentagem()
        local cap = w.energiaCapacidade()
        if cap <= 0 then return 0 end
        local pct = (w.energiaArmazenada() / cap) * 100
        return math.max(0, math.min(100, pct))
    end

    function w.energiaProduzidaTick()
        return seguro(p, "getEnergyProducedLastTick", 0)
    end

    function w.vaporProduzidoTick()
        return seguro(p, "getHotFluidProducedLastTick", 0)
    end

    function w.combustivelArmazenado()
        return seguro(p, "getFuelAmount", 0)
    end

    function w.combustivelMax()
        return seguro(p, "getFuelAmountMax", 1)
    end

    function w.combustivelPorcentagem()
        local maximo = w.combustivelMax()
        if maximo <= 0 then return 0 end
        return math.max(0, math.min(100, (w.combustivelArmazenado() / maximo) * 100))
    end

    function w.lixoArmazenado()
        return seguro(p, "getWasteAmount", 0)
    end

    function w.reatividade()
        return seguro(p, "getFuelReactivity", 0)
    end

    function w.consumoCombustivelTick()
        return seguro(p, "getFuelConsumedLastTick", 0)
    end

    function w.isAtivoRefrigerado()
        return seguro(p, "isActivelyCooled", false)
    end

    function w.liquidoRefrigerante()
        return seguro(p, "getCoolantAmount", 0)
    end

    function w.liquidoRefrigeranteMax()
        return seguro(p, "getCoolantAmountMax", 1)
    end

    function w.vaporArmazenado()
        return seguro(p, "getHotFluidAmount", 0)
    end

    function w.vaporMax()
        return seguro(p, "getHotFluidAmountMax", 1)
    end

    function w.getNumBarras()
        return seguro(p, "getNumberOfControlRods", 1)
    end

    function w.getNivelBarras()
        -- Tenta pegar niveis de todas as barras
        local niveis = seguro(p, "getControlRodsLevels", nil)
        if type(niveis) == "table" and #niveis > 0 then
            local soma = 0
            for _, v in ipairs(niveis) do soma = soma + v end
            return math.floor(soma / #niveis)
        end
        -- Fallback: le a barra 0 ou 1
        local n0 = seguro(p, "getControlRodLevel", nil, 0)
        if n0 ~= nil then return n0 end
        local n1 = seguro(p, "getControlRodLevel", 0, 1)
        return n1
    end

    function w.setBarras(nivel)
        nivel = math.max(0, math.min(100, math.floor(nivel)))
        -- Tenta o metodo que altera todas
        if p.setAllControlRodLevels then
            local ok = pcall(p.setAllControlRodLevels, nivel)
            if ok then return true end
        end
        -- Se falhar, itera por barra
        local qtd = w.getNumBarras()
        for i = 0, qtd - 1 do
            pcall(p.setControlRodLevel, i, nivel)
        end
        return true
    end

    function w.ejetarLixo()
        if p.doEjectWaste then
            pcall(p.doEjectWaste)
            return true
        end
        return false
    end

    return w
end

-- Cria wrapper padronizado para a Turbina
local function envolverTurbina(p, nome)
    local w = {
        _raw = p,
        nome = nome or "Turbina",
    }

    function w.ativo()
        return seguro(p, "getActive", false)
    end

    function w.setAtivo(estado)
        return seguro(p, "setActive", false, estado and true or false)
    end

    function w.rpm()
        return math.floor(seguro(p, "getRotorSpeed", 0) * 10) / 10
    end

    function w.indutorAtivo()
        return seguro(p, "getInductorEngaged", false)
    end

    function w.setIndutor(estado)
        return seguro(p, "setInductorEngaged", false, estado and true or false)
    end

    function w.vazaoAtual()
        return seguro(p, "getFluidFlowRate", 0)
    end

    function w.vazaoMax()
        return seguro(p, "getFluidFlowRateMax", 0)
    end

    function w.vazaoTeto()
        local teto = seguro(p, "getFluidFlowRateMaxMax", 2000)
        if teto <= 0 then teto = 2000 end
        return teto
    end

    function w.setVazao(taxa)
        taxa = math.max(0, math.min(w.vazaoTeto(), math.floor(taxa)))
        return seguro(p, "setFluidFlowRateMax", false, taxa)
    end

    function w.energiaProduzidaTick()
        return seguro(p, "getEnergyProducedLastTick", 0)
    end

    function w.energiaArmazenada()
        return seguro(p, "getEnergyStored", 0)
    end

    function w.energiaCapacidade()
        local cap = seguro(p, "getEnergyCapacity", 0)
        if cap <= 0 then cap = 1000000 end
        return cap
    end

    function w.eficienciaPas()
        local eff = seguro(p, "getBladeEfficiency", 0)
        -- Normaliza para 0 - 100%
        if eff <= 1.0 and eff > 0 then eff = eff * 100 end
        return math.floor(eff * 10) / 10
    end

    function w.respiro(modo)
        modo = string.lower(tostring(modo))
        if modo == "none" and p.setVentNone then
            pcall(p.setVentNone)
        elseif modo == "all" and p.setVentAll then
            pcall(p.setVentAll)
        elseif p.setVentOverflow then
            pcall(p.setVentOverflow)
        end
    end

    function w.nivelEntrada()
        return seguro(p, "getInputAmount", 0)
    end

    function w.nivelSaida()
        return seguro(p, "getOutputAmount", 0)
    end

    function w.tanqueMax()
        return seguro(p, "getFluidAmountMax", 1)
    end

    return w
end

-- Escaneia e descobre todos os perifericos conectados
function M.escanear()
    local resultado = {
        reator = nil,
        turbinas = {},
        monitor = nil,
        erros = {}
    }

    if not peripheral then
        table.insert(resultado.erros, "API peripheral nao esta presente.")
        return resultado
    end

    local nomes = peripheral.getNames()
    for _, nome in ipairs(nomes) do
        local tipo = peripheral.getType(nome)
        local obj = peripheral.wrap(nome)

        -- Verifica se e monitor
        if tipo == "monitor" and not resultado.monitor then
            resultado.monitor = obj
        end

        -- Verifica se e reator
        if (TIPOS_REATOR[tipo] or pareceReator(obj)) and not resultado.reator then
            resultado.reator = envolverReator(obj, nome)
        end

        -- Verifica se e turbina
        if TIPOS_TURBINA[tipo] or pareceTurbina(obj) then
            table.insert(resultado.turbinas, envolverTurbina(obj, nome))
        end
    end

    -- Se nao achou reator pela lista, tenta peripheral.find
    if not resultado.reator and peripheral.find then
        for tipo, _ in pairs(TIPOS_REATOR) do
            local achado, nomeAchado = peripheral.find(tipo)
            if achado then
                resultado.reator = envolverReator(achado, nomeAchado)
                break
            end
        end
    end

    -- Se nao achou monitor, tenta peripheral.find("monitor")
    if not resultado.monitor and peripheral.find then
        resultado.monitor = peripheral.find("monitor")
    end

    if not resultado.reator then
        table.insert(resultado.erros, "Nenhum Reactor Computer Port detectado.")
    end

    return resultado
end

return M
]====]

arquivos["controlador.lua"] = [====[
-- controlador.lua
-- Nucleo logico de controle de alta eficiencia para Extreme Reactors e Turbinas

local M = {}

-- Estados possiveis
M.ESTADOS = {
    OPERANDO = "OPERANDO",
    STANDBY = "STANDBY",
    EMERGENCIA = "SCRAM (EMERGENCIA)",
    CALIBRANDO = "CALIBRANDO",
    MANUAL = "MANUAL",
}

function M.novo(cfg, perifericos)
    local c = {
        ESTADOS = M.ESTADOS,
        cfg = cfg,
        peri = perifericos,
        estado = M.ESTADOS.STANDBY,
        modo = "DESCONHECIDO", -- "PASSIVO" ou "ATIVO_TURBINA"
        perfil = string.upper(cfg.ativo.perfil_operacao or "EFICIENCIA"), -- "EFICIENCIA" ou "POTENCIA"
        scram_manual = false,
        motivo_alerta = "Sistema iniciado",
        
        -- Estatisticas e telemetria
        stats = {
            tempo_operacao = 0,
            eficiencia_media_rf_mb = 0,
            consumo_total_mb = 0,
            energia_total_rf = 0,
            vapor_total_mb = 0,
            barras_alvo = 50,
            turbinas_sincronizadas = 0,
            dados_recentes = {}
        }
    }

    -- Alterna entre Perfil de Eficiencia (Economia) e Potencia Maxima
    function c:alternarPerfil()
        if self.perfil == "POTENCIA" then
            self.perfil = "EFICIENCIA"
        else
            self.perfil = "POTENCIA"
        end
        self.cfg.ativo.perfil_operacao = string.lower(self.perfil)
        pcall(self.cfg.salvar)
        self.motivo_alerta = "Perfil alterado para: " .. self.perfil
        return self.perfil
    end

    -- Determina o modo de operacao automaticamente ou forca config
    function c:determinarModo()
        local modoCfg = self.cfg.ativo.modo_operacao
        if modoCfg == "passivo" then
            self.modo = "PASSIVO"
        elseif modoCfg == "ativo" then
            self.modo = "ATIVO_TURBINA"
        else
            -- Modo auto
            local r = self.peri.reator
            local temTurbinas = (#self.peri.turbinas > 0)
            if temTurbinas or (r and r.isAtivoRefrigerado()) then
                self.modo = "ATIVO_TURBINA"
            else
                self.modo = "PASSIVO"
            end
        end
    end

    -- Dispara desligamento de emergencia
    function c:acionarScram(motivo)
        self.estado = M.ESTADOS.EMERGENCIA
        self.motivo_alerta = motivo or "SCRAM Acionado!"
        if self.peri.reator then
            self.peri.reator.setBarras(100)
            self.peri.reator.setAtivo(false)
        end
        for _, t in ipairs(self.peri.turbinas) do
            t.setIndutor(false)
            t.setVazao(0)
        end
    end

    -- Cancela o scram caso as condicoes estejam seguras
    function c:limparScram()
        self.scram_manual = false
        self.estado = M.ESTADOS.STANDBY
        self.motivo_alerta = "SCRAM redefinido. Sistema em espera."
    end

    -- Alterna SCRAM Manual pelo teclado/usuario
    function c:alternarScramManual()
        self.scram_manual = not self.scram_manual
        if self.scram_manual then
            self:acionarScram("SCRAM manual acionado pelo operador")
        else
            self:limparScram()
        end
    end

    -- Loop de controle para Modo Passivo (Somente Reator)
    function c:processarPassivo()
        local r = self.peri.reator
        if not r then return end

        local cfgR = self.cfg.ativo.reator
        local tempComb = r.tempCombustivel()
        local bufferPct = r.energiaPorcentagem()
        local energiaRF = r.energiaProduzidaTick()
        local consumoMB = r.consumoCombustivelTick()

        -- 1. Verificacao de Seguranca Termica
        if tempComb >= cfgR.temp_scram then
            self:acionarScram(string.format("Temperatura critica no nucleo: %.1f C", tempComb))
            return
        end

        -- 2. Logica de Descarte de Lixo (Cianita)
        if cfgR.auto_ejetar_lixo and r.lixoArmazenado() > 1000 then
            r.ejetarLixo()
        end

        -- 3. Execução por Perfil de Operação
        if self.perfil == "POTENCIA" then
            -- =================================================================
            -- PERFIL: POTÊNCIA MÁXIMA (Overdrive / Máxima Geração de RF/t)
            -- =================================================================
            if not r.ativo() then
                r.setAtivo(true)
            end

            local nivelFinal = 0 -- 0% de barras = potência máxima de reação!

            -- Se a rede elétrica saturar completamente (>96%), protege o buffer
            if bufferPct >= 96 then
                nivelFinal = 100
                if bufferPct >= 99 then
                    r.setAtivo(false)
                end
                self.estado = M.ESTADOS.STANDBY
                self.motivo_alerta = "[POTENCIA] Buffer cheio (96%+). Em pausa."
            -- Freio térmico de segurança (se aproximar do limite alto de potência)
            elseif tempComb >= cfgR.temp_max_potencia then
                local excesso = tempComb - cfgR.temp_max_potencia
                nivelFinal = math.min(95, math.floor(excesso * 2))
                self.estado = M.ESTADOS.OPERANDO
                self.motivo_alerta = string.format("[POTENCIA] Freio Termico: %d%% barras | Temp: %.1f C", nivelFinal, tempComb)
            else
                self.estado = M.ESTADOS.OPERANDO
                self.motivo_alerta = string.format("[POTENCIA MAXIMA] Barras em 0%% | +%d RF/t | Temp: %.1f C",
                    energiaRF, tempComb)
            end

            r.setBarras(nivelFinal)
            self.stats.barras_alvo = nivelFinal

        else
            -- =================================================================
            -- PERFIL: EFICIÊNCIA MÁXIMA (Eco / Economia de Urânio)
            -- =================================================================
            if bufferPct >= cfgR.buffer_energia_max then
                r.setBarras(100)
                if bufferPct >= 96 then
                    r.setAtivo(false)
                end
                self.estado = M.ESTADOS.STANDBY
                self.motivo_alerta = string.format("Buffer cheio (%.1f%%). Economizando combustivel.", bufferPct)
                self.stats.barras_alvo = 100
                return
            end

            if bufferPct <= cfgR.buffer_energia_min then
                if not r.ativo() then
                    r.setAtivo(true)
                end
                self.estado = M.ESTADOS.OPERANDO
            end

            if not r.ativo() and bufferPct < (cfgR.buffer_energia_max - 5) then
                r.setAtivo(true)
                self.estado = M.ESTADOS.OPERANDO
            end

            local span = math.max(1, cfgR.buffer_energia_max - cfgR.buffer_energia_min)
            local fatorCarga = (bufferPct - cfgR.buffer_energia_min) / span
            fatorCarga = math.max(0, math.min(1, fatorCarga))

            local nivelBase = fatorCarga * 85
            local excessoTermico = math.max(0, tempComb - cfgR.temp_alvo_combustivel)
            local freioTermico = (excessoTermico / 20) * 1.5

            local nivelFinal = math.min(99, math.max(0, math.floor(nivelBase + freioTermico)))

            r.setBarras(nivelFinal)
            self.stats.barras_alvo = nivelFinal
            self.motivo_alerta = string.format("[ECO EFICIENCIA] Barras: %d%% | Temp: %.1f C | Buffer: %.1f%%",
                nivelFinal, tempComb, bufferPct)
        end

        -- Atualiza calculo de eficiencia instantanea (RF por mB de combustivel)
        if consumoMB > 0.00001 then
            local eff = energiaRF / consumoMB
            if self.stats.eficiencia_media_rf_mb == 0 then
                self.stats.eficiencia_media_rf_mb = eff
            else
                self.stats.eficiencia_media_rf_mb = (self.stats.eficiencia_media_rf_mb * 0.9) + (eff * 0.1)
            end
        end
    end

    -- Loop de controle para Modo Ativo + Turbinas
    function c:processarAtivoComTurbinas()
        local r = self.peri.reator
        local turbinas = self.peri.turbinas
        local cfgT = self.cfg.ativo.turbina
        local cfgR = self.cfg.ativo.reator

        if not r then return end

        local tempComb = r.tempCombustivel()
        local liqRefrig = r.liquidoRefrigerante()
        local liqMax = r.liquidoRefrigeranteMax()
        local liqPct = (liqMax > 0) and (liqRefrig / liqMax * 100) or 100

        -- 1. Seguranca: SCRAM por superaquecimento ou falta critica de agua
        if tempComb >= cfgR.temp_scram then
            self:acionarScram(string.format("Temperatura critica no nucleo: %.1f C", tempComb))
            return
        end
        if r.isAtivoRefrigerado() and liqPct < 8 then
            self:acionarScram("Agua de refrigeracao esgotada! Risco de fusao seca.")
            return
        end

        -- Garante que o reator esta ligado
        if not r.ativo() then
            r.setAtivo(true)
        end

        local demandaVaporTotal = 0
        local turbinasOk = 0

        -- 2. Controle Individual de Cada Turbina (Foco: 1800 RPM exatos)
        for _, t in ipairs(turbinas) do
            if not t.ativo() then t.setAtivo(true) end
            t.respiro(cfgT.modo_respiro)

            local rpm = t.rpm()
            local indutor = t.indutorAtivo()
            local vazaoAtual = t.vazaoMax()
            local tetoVazao = math.min(cfgT.vazao_max_limite, t.vazaoTeto())

            -- Logica de Partida e Giro Livre:
            -- Enquanto estiver abaixo da rotacao de engate, desliga o indutor para cortar
            -- o atrito magnetico e acelerar em segundos.
            if rpm < cfgT.rpm_engajar_indutor then
                if indutor then
                    t.setIndutor(false)
                end
                -- Abre fluxo para acelerar
                t.setVazao(tetoVazao)
            else
                -- Turbina atingiu a faixa ideal (~1800 RPM)
                if not indutor then
                    t.setIndutor(true)
                end

                -- Ajuste Fino de Fluxo de Vapor (Manutencao dos 1800 RPM)
                if rpm > (cfgT.rpm_alvo + cfgT.rpm_tolerancia) then
                    -- Rotação subindo alem do sweet spot -> diminui vapor
                    local novaVazao = math.max(50, vazaoAtual - cfgT.passo_vazao)
                    t.setVazao(novaVazao)
                elseif rpm < (cfgT.rpm_alvo - cfgT.rpm_tolerancia) then
                    -- Rotação caindo -> aumenta vapor
                    local novaVazao = math.min(tetoVazao, vazaoAtual + cfgT.passo_vazao)
                    t.setVazao(novaVazao)
                else
                    -- Exatamente no ponto doce (1800 RPM +/- tolerancia)
                    turbinasOk = turbinasOk + 1
                end
            end

            demandaVaporTotal = demandaVaporTotal + t.vazaoMax()
        end

        self.stats.turbinas_sincronizadas = turbinasOk

        -- 3. Balanceamento do Reator Ativo para Gerar o Vapor Exato
        -- Compara a producao atual de vapor com a demanda total das turbinas
        local vaporGerado = r.vaporProduzidoTick()
        local nivelVaporTanque = (r.vaporMax() > 0) and (r.vaporArmazenado() / r.vaporMax() * 100) or 50
        local nivelBarras = r.getNivelBarras()

        if demandaVaporTotal <= 0 then
            demandaVaporTotal = 2000 -- Fallback se turbina estiver vazia
        end

        -- Se o tanque de vapor do reator estiver estufando (>80%), insere barras
        if nivelVaporTanque > 80 then
            local novoNivel = math.min(100, nivelBarras + 3)
            r.setBarras(novoNivel)
            self.stats.barras_alvo = novoNivel
        -- Se o vapor produzido for menor que a demanda, recua as barras para ferver mais agua
        elseif vaporGerado < (demandaVaporTotal * 0.95) then
            local novoNivel = math.max(0, nivelBarras - 1)
            r.setBarras(novoNivel)
            self.stats.barras_alvo = novoNivel
        -- Se estiver produzindo vapor em excesso alem da demanda das turbinas, sobe barras
        elseif vaporGerado > (demandaVaporTotal * 1.05) then
            local novoNivel = math.min(99, nivelBarras + 1)
            r.setBarras(novoNivel)
            self.stats.barras_alvo = novoNivel
        end

        -- 4. Eficiencia Global
        local consumoMB = r.consumoCombustivelTick()
        local energiaTotalTurbinas = 0
        for _, t in ipairs(turbinas) do
            energiaTotalTurbinas = energiaTotalTurbinas + t.energiaProduzidaTick()
        end

        if consumoMB > 0.00001 then
            local eff = energiaTotalTurbinas / consumoMB
            if self.stats.eficiencia_media_rf_mb == 0 then
                self.stats.eficiencia_media_rf_mb = eff
            else
                self.stats.eficiencia_media_rf_mb = (self.stats.eficiencia_media_rf_mb * 0.9) + (eff * 0.1)
            end
        end

        self.estado = M.ESTADOS.OPERANDO
        self.motivo_alerta = string.format("Turbinas a 1800 RPM: %d/%d | Demanda Vapor: %d mB/t | Reator: %d mB/t",
            turbinasOk, #turbinas, demandaVaporTotal, vaporGerado)
    end

    -- Ciclo principal chamado periodicamente
    function c:atualizar()
        if not self.peri.reator then
            self.estado = M.ESTADOS.STANDBY
            self.motivo_alerta = "Aguardando conexao do reator..."
            return
        end

        if self.scram_manual or self.estado == M.ESTADOS.EMERGENCIA then
            -- Permanece parado ate limpeza de erro
            if self.peri.reator.ativo() then
                self.peri.reator.setAtivo(false)
                self.peri.reator.setBarras(100)
            end
            return
        end

        if self.estado == M.ESTADOS.CALIBRANDO then
            -- O controle e assumido temporariamente pela rotina de calibracao
            return
        end

        self:determinarModo()

        if self.modo == "ATIVO_TURBINA" and #self.peri.turbinas > 0 then
            self:processarAtivoComTurbinas()
        else
            self:processarPassivo()
        end

        self.stats.tempo_operacao = self.stats.tempo_operacao + self.cfg.ativo.sistema.intervalo_tick
    end

    -- Coleta um instantaneo de dados atualizados para relatorios e interface
    function c:coletarSnapshot()
        local r = self.peri.reator
        local dados = {
            tempo = os and (os.date and os.date("%Y-%m-%d %H:%M:%S") or os.time()) or "0",
            modo = self.modo,
            perfil = self.perfil,
            estado = self.estado,
            alerta = self.motivo_alerta,
            reator = nil,
            turbinas = {},
            eficiencia_rf_mb = math.floor(self.stats.eficiencia_media_rf_mb),
            barras_alvo = self.stats.barras_alvo,
        }

        if r then
            dados.reator = {
                nome = r.nome,
                ativo = r.ativo(),
                temp_combustivel = r.tempCombustivel(),
                temp_carcaca = r.tempCarcaca(),
                energia_armazenada = r.energiaArmazenada(),
                energia_capacidade = r.energiaCapacidade(),
                energia_pct = r.energiaPorcentagem(),
                energia_tick = r.energiaProduzidaTick(),
                vapor_tick = r.vaporProduzidoTick(),
                combustivel_armazenado = r.combustivelArmazenado(),
                combustivel_max = r.combustivelMax(),
                combustivel_pct = r.combustivelPorcentagem(),
                lixo_armazenado = r.lixoArmazenado(),
                consumo_tick = r.consumoCombustivelTick(),
                reatividade = r.reatividade(),
                ativo_refrigerado = r.isAtivoRefrigerado(),
                agua = r.liquidoRefrigerante(),
                agua_max = r.liquidoRefrigeranteMax(),
                vapor = r.vaporArmazenado(),
                vapor_max = r.vaporMax(),
                barras_nivel = r.getNivelBarras(),
            }
        end

        for _, t in ipairs(self.peri.turbinas) do
            table.insert(dados.turbinas, {
                nome = t.nome,
                ativo = t.ativo(),
                rpm = t.rpm(),
                indutor = t.indutorAtivo(),
                vazao_atual = t.vazaoAtual(),
                vazao_max = t.vazaoMax(),
                energia_tick = t.energiaProduzidaTick(),
                energia_armazenada = t.energiaArmazenada(),
                energia_capacidade = t.energiaCapacidade(),
                eficiencia_pas = t.eficienciaPas(),
            })
        end

        return dados
    end

    return c
end

return M
]====]

arquivos["relatorios.lua"] = [====[
-- relatorios.lua
-- Gerador de Relatorios Analiticos, Logs de Telemetria (CSV) e Benchmarks de Desenvolvimento

local M = {}

-- Formata numeros com separador de milhar (ex: 1,500,000)
local function formatarNumero(n)
    if not n then return "0" end
    local formatado = string.format("%.0f", n)
    local k
    while true do
        formatado, k = string.gsub(formatado, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatado
end

-- Gera timestamp seguro mesmo em ambientes CC sem os.date completo
local function obterTimestamp()
    if os.date then
        local ok, data = pcall(os.date, "%Y-%m-%d %H:%M:%S")
        if ok and data then return data end
    end
    return string.format("Dia %d, %s", os.day and os.day() or 0, textutils and textutils.formatTime(os.time(), true) or tostring(os.time()))
end

local function obterNomeArquivoSeguro()
    if os.date then
        local ok, data = pcall(os.date, "%Y%m%d_%H%M%S")
        if ok and data then return "relatorio_" .. data .. ".txt" end
    end
    return string.format("relatorio_d%s_t%s.txt", tostring(os.day and os.day() or 0), tostring(math.floor(os.time() * 100)))
end

-- 1. GERADOR DE RELATORIO ANALITICO EM TEXTO (.txt)
function M.gerarRelatorioTexto(dados, pastaDestino)
    pastaDestino = pastaDestino or "relatorios/"
    if fs and not fs.exists(pastaDestino) then
        pcall(fs.makeDir, pastaDestino)
    end

    local r = dados.reator
    local turbinas = dados.turbinas or {}
    local dataStr = obterTimestamp()
    local nomeArquivo = obterNomeArquivoSeguro()
    local caminhoCompleto = pastaDestino .. nomeArquivo

    local linhas = {}
    local function add(l) table.insert(linhas, l or "") end

    add("================================================================================")
    add("            RELATORIO DE DESEMPENHO E EFICIENCIA - EXTREME REACTORS              ")
    add("================================================================================")
    add(string.format(" Data da Coleta:     %s", dataStr))
    add(string.format(" Modo do Sistema:    %s", dados.modo or "DESCONHECIDO"))
    add(string.format(" Perfil de Operacao: %s (%s)", dados.perfil or "EFICIENCIA", (dados.perfil == "POTENCIA") and "MAXIMA POTENCIA" or "ECO EFICIENCIA"))
    add(string.format(" Status Operacional: %s", dados.estado or "DESCONHECIDO"))
    add(string.format(" Alerta / Mensagem:  %s", dados.alerta or "Nenhum"))
    add("--------------------------------------------------------------------------------")
    add(" 1. METRICAS GERAIS DE EFICIENCIA")
    add("--------------------------------------------------------------------------------")
    add(string.format("  Eficiencia Global:        %s RF / mB de Combustivel", formatarNumero(dados.eficiencia_rf_mb)))
    
    if r then
        local energiaRF = r.energia_tick or 0
        local queimaMB = r.consumo_tick or 0
        local queimaMinuto = queimaMB * 20 * 60
        add(string.format("  Geracao Direta Reator:    %s RF/t", formatarNumero(energiaRF)))
        add(string.format("  Taxa de Queima:           %.4f mB/t  (~%.2f mB por minuto)", queimaMB, queimaMinuto))
        add(string.format("  Nivel Medio das Barras:   %d%% (Alvo do Algoritmo: %d%%)", r.barras_nivel or 0, dados.barras_alvo or 0))
    end

    add("--------------------------------------------------------------------------------")
    add(" 2. NUCLEO DO REATOR (CONDICOES TERMICAS E MATERIAIS)")
    add("--------------------------------------------------------------------------------")
    if r then
        add(string.format("  Temp. do Combustivel:     %.1f C  (Faixa Ideal: 550 C - 750 C)", r.temp_combustivel or 0))
        add(string.format("  Temp. da Carcaca:         %.1f C", r.temp_carcaca or 0))
        add(string.format("  Combustivel Armazenado:   %s / %s mB (%.1f%%)",
            formatarNumero(r.combustivel_armazenado), formatarNumero(r.combustivel_max), r.combustivel_pct or 0))
        add(string.format("  Residuo Acumulado (Lixo): %s mB", formatarNumero(r.lixo_armazenado)))
        add(string.format("  Reatividade Nuclear:      %.1f%%", r.reatividade or 0))
        add(string.format("  Buffer de Energia:        %s / %s RF (%.1f%%)",
            formatarNumero(r.energia_armazenada), formatarNumero(r.energia_capacidade), r.energia_pct or 0))

        if r.ativo_refrigerado then
            add(string.format("  Tanque Refrigerante:      %s / %s mB (Agua)", formatarNumero(r.agua), formatarNumero(r.agua_max)))
            add(string.format("  Tanque Vapor (Vapor):     %s / %s mB | Producao: %s mB/t",
                formatarNumero(r.vapor), formatarNumero(r.vapor_max), formatarNumero(r.vapor_tick)))
        end
    else
        add("  [!] Nenhum Reator Conectado.")
    end

    add("--------------------------------------------------------------------------------")
    add(" 3. TURBINAS E GERADORES DE VAPOR (" .. tostring(#turbinas) .. " CONECTADAS)")
    add("--------------------------------------------------------------------------------")
    if #turbinas > 0 then
        local somaRFTurbinas = 0
        local somaVazaoTurbinas = 0
        for i, t in ipairs(turbinas) do
            somaRFTurbinas = somaRFTurbinas + (t.energia_tick or 0)
            somaVazaoTurbinas = somaVazaoTurbinas + (t.vazao_max or 0)
            local deltaRPM = (t.rpm or 0) - 1800
            local sinal = deltaRPM >= 0 and "+" or ""
            local statusRpm = (math.abs(deltaRPM) <= 15) and "[OTIMO: 100% EFICIENCIA]" or "[AJUSTANDO FLUXO]"
            
            add(string.format("  [Turbina #%d - %s]", i, t.nome or "Turbina"))
            add(string.format("    Rotacao:                %.1f RPM (%s%.1f RPM do Ponto Doce) %s", t.rpm or 0, sinal, deltaRPM, statusRpm))
            add(string.format("    Indutor / Bobina:       %s", t.indutor and "ENGAJADO (GERANDO ENERGIA)" or "LIVRE (EM ACELERACAO)"))
            add(string.format("    Vazao de Vapor:         %s mB/t (Consumo Real: %s mB/t)", formatarNumero(t.vazao_max), formatarNumero(t.vazao_atual)))
            add(string.format("    Eficiencia das Pas:     %.1f%%", t.eficiencia_pas or 0))
            add(string.format("    Energia Produzida:      %s RF/t", formatarNumero(t.energia_tick)))
        end
        add("  ------------------------------------------------------------------------------")
        add(string.format("  TOTAL TURBINAS: %s RF/t  |  DEMANDA TOTAL DE VAPOR: %s mB/t",
            formatarNumero(somaRFTurbinas), formatarNumero(somaVazaoTurbinas)))
    else
        add("  [Nenhuma turbina detectada. Sistema operando em modo de geracao passiva direta]")
    end

    add("--------------------------------------------------------------------------------")
    add(" 4. DIAGNOSTICO E DICAS DE DESENVOLVIMENTO / ENGENHARIA")
    add("--------------------------------------------------------------------------------")
    local avisos = 0
    if r then
        if (r.temp_combustivel or 0) > 850 then
            avisos = avisos + 1
            add(string.format("  [DICA-TERMICA] Temp. do combustivel elevada (%.1f C). O consumo cresce", r.temp_combustivel))
            add("                 exponencialmente acima de 800 C. Considere refrigeracao criogenica ou elevar as barras.")
        end
        if (r.energia_pct or 0) > 90 then
            avisos = avisos + 1
            add("  [DICA-ENERGIA] Buffer de RF quase cheio (>90%). O sistema reduziu a queima para evitar perdas.")
        end
        if r.ativo_refrigerado and #turbinas > 0 then
            local vaporGerado = r.vapor_tick or 0
            local somaVazao = 0
            for _, t in ipairs(turbinas) do somaVazao = somaVazao + (t.vazao_max or 0) end
            if vaporGerado < somaVazao * 0.9 then
                avisos = avisos + 1
                add(string.format("  [DICA-VAPOR] Producao de vapor (%d mB/t) inferior a demanda das turbinas (%d mB/t).", vaporGerado, somaVazao))
                add("               As turbinas podem sofrer queda de RPM. Aumente as barras ou expanda o reator.")
            end
        end
    end
    if avisos == 0 then
        add("  [EXCELENTE] O sistema esta operando em parametros otimizados de maxima eficiencia.")
    end

    add("================================================================================")
    add("                  FIM DO RELATORIO - GERADO VIA CC: TWEAKED                     ")
    add("================================================================================")

    local conteudo = table.concat(linhas, "\n")

    if fs then
        local arq = fs.open(caminhoCompleto, "w")
        if arq then
            arq.write(conteudo)
            arq.close()
            return true, caminhoCompleto, conteudo
        end
    end

    return false, caminhoCompleto, conteudo
end

-- 2. REGISTRADOR DE TELEMETRIA CONTÍNUA EM CSV
function M.registrarLinhaCSV(dados, arquivoCSV)
    arquivoCSV = arquivoCSV or "relatorios/telemetria.csv"
    if not fs then return false end

    -- Se o arquivo nao existe, cria com cabecalho
    if not fs.exists(arquivoCSV) then
        local cabecalho = "Timestamp,Modo,Estado,RF_Total_Tick,Consumo_Combustivel_mBt,Eficiencia_RF_mB,Temp_Combustivel_C,Temp_Carcaca_C,Energia_Buffer_Pct,Barras_Nivel_Pct,Turbinas_Qtd,Turbina1_RPM,Turbina1_RFt\n"
        local arq = fs.open(arquivoCSV, "w")
        if arq then
            arq.write(cabecalho)
            arq.close()
        end
    end

    local r = dados.reator
    local turbinas = dados.turbinas or {}
    local dataStr = obterTimestamp()

    local rfTotal = 0
    if r then rfTotal = rfTotal + (r.energia_tick or 0) end
    for _, t in ipairs(turbinas) do rfTotal = rfTotal + (t.energia_tick or 0) end

    local turb1Rpm = (#turbinas > 0) and turbinas[1].rpm or 0
    local turb1RF = (#turbinas > 0) and turbinas[1].energia_tick or 0

    local linha = string.format("%s,%s,%s,%d,%.4f,%d,%.1f,%.1f,%.1f,%d,%d,%.1f,%d\n",
        dataStr,
        dados.modo or "N/A",
        dados.estado or "N/A",
        rfTotal,
        (r and r.consumo_tick) or 0,
        dados.eficiencia_rf_mb or 0,
        (r and r.temp_combustivel) or 0,
        (r and r.temp_carcaca) or 0,
        (r and r.energia_pct) or 0,
        (r and r.barras_nivel) or 0,
        #turbinas,
        turb1Rpm,
        turb1RF
    )

    local arq = fs.open(arquivoCSV, "a")
    if arq then
        arq.write(linha)
        arq.close()
        return true
    end
    return false
end

-- 3. BENCHMARK E CURVA DE EFICIENCIA
function M.executarBenchmark(controlador, cbProgresso)
    local r = controlador.peri.reator
    if not r then
        return nil, "Reator nao disponivel para benchmark."
    end

    local estadoOriginal = controlador.estado
    controlador.estado = controlador.ESTADOS.CALIBRANDO

    local niveis = { 0, 20, 40, 60, 80 }
    local resultados = {}

    -- Garante que o reator esta ligado
    r.setAtivo(true)

    for idx, nivel in ipairs(niveis) do
        r.setBarras(nivel)
        if cbProgresso then
            cbProgresso(string.format("Testando barras em %d%% (%d/%d)... Aguardando estabilizacao", nivel, idx, #niveis))
        end

        -- Aguarda estabilizacao termica (aproximadamente 6 segundos no jogo)
        if os.sleep then
            for _ = 1, 6 do
                os.sleep(1)
            end
        end

        -- Coleta dados medios
        local temp = r.tempCombustivel()
        local rf = r.energiaProduzidaTick()
        local consumo = r.consumoCombustivelTick()
        local vapor = r.vaporProduzidoTick()
        local eff = (consumo > 0.00001) and (rf / consumo) or 0

        table.insert(resultados, {
            nivel_barras = nivel,
            temperatura = temp,
            energia_rf_t = rf,
            vapor_mb_t = vapor,
            consumo_mb_t = consumo,
            eficiencia_rf_mb = math.floor(eff)
        })
    end

    -- Restaura estado
    controlador.estado = estadoOriginal
    controlador:determinarModo()

    -- Encontra o melhor patamar de eficiencia e o de melhor potencia
    local melhorEff = resultados[1]
    local melhorPot = resultados[1]
    for _, res in ipairs(resultados) do
        if res.eficiencia_rf_mb > (melhorEff.eficiencia_rf_mb or 0) then
            melhorEff = res
        end
        local valPotAtual = (res.energia_rf_t and res.energia_rf_t > 0) and res.energia_rf_t or (res.vapor_mb_t or 0)
        local valPotMelhor = (melhorPot.energia_rf_t and melhorPot.energia_rf_t > 0) and melhorPot.energia_rf_t or (melhorPot.vapor_mb_t or 0)
        if valPotAtual > valPotMelhor then
            melhorPot = res
        end
    end

    -- Salva relatorio de benchmark em arquivo
    local dataStr = obterTimestamp()
    local nomeBenchmark = "relatorios/benchmark_" .. (os.date and os.date("%Y%m%d_%H%M%S") or "resultado") .. ".txt"
    local linhasBench = {
        "================================================================================",
        "            RESULTADO DO BENCHMARK DA CURVA DE RENDIMENTO                       ",
        "================================================================================",
        string.format(" Data do Teste: %s", dataStr),
        "",
        string.format(" %-12s | %-12s | %-14s | %-14s | %-16s", "Barras (%)", "Temp (C)", "Geracao (RF/t)", "Queima (mB/t)", "Eficiencia (RF/mB)"),
        "--------------------------------------------------------------------------------",
    }

    for _, res in ipairs(resultados) do
        table.insert(linhasBench, string.format(" %-12d | %-12.1f | %-14s | %-14.4f | %-16s",
            res.nivel_barras, res.temperatura, formatarNumero(res.energia_rf_t), res.consumo_mb_t, formatarNumero(res.eficiencia_rf_mb)))
    end

    table.insert(linhasBench, "--------------------------------------------------------------------------------")
    table.insert(linhasBench, string.format(" [★] MELHOR POTENCIA BRUTA:    Barras em %d%% (Gera %s RF/t | %s mB/t vapor)",
        melhorPot.nivel_barras, formatarNumero(melhorPot.energia_rf_t), formatarNumero(melhorPot.vapor_mb_t)))
    table.insert(linhasBench, string.format(" [★] MELHOR EFICIENCIA (ECO):  Barras em %d%% (%s RF/mB de combustivel)",
        melhorEff.nivel_barras, formatarNumero(melhorEff.eficiencia_rf_mb)))
    table.insert(linhasBench, "================================================================================")

    local relatorioFinal = table.concat(linhasBench, "\n")
    if fs then
        local arq = fs.open(nomeBenchmark, "w")
        if arq then
            arq.write(relatorioFinal)
            arq.close()
        end
    end

    return resultados, nomeBenchmark, relatorioFinal
end

return M
]====]

arquivos["interface.lua"] = [====[
-- interface.lua
-- Interface Visual Rica para Terminal do Computador e Monitores do CC: Tweaked

local M = {}

local function formatarNumero(n)
    if not n then return "0" end
    local formatado = string.format("%.0f", n)
    local k
    while true do
        formatado, k = string.gsub(formatado, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatado
end

function M.novo(dispositivoSaida)
    local ui = {
        term = dispositivoSaida or term,
        notificacao = nil,
        tempoNotificacao = 0,
    }

    function ui:definirDispositivo(d)
        self.term = d or term
    end

    function ui:notificar(msg)
        self.notificacao = msg
        self.tempoNotificacao = os.clock and os.clock() or 0
    end

    -- Desenha barra de progresso horizontal
    function ui:barraProgresso(x, y, largura, porcentagem, corCheio, corVazio)
        porcentagem = math.max(0, math.min(100, porcentagem or 0))
        local preenchido = math.floor((porcentagem / 100) * largura)
        local vazio = largura - preenchido

        self.term.setCursorPos(x, y)
        if self.term.isColor and self.term.isColor() then
            self.term.setTextColor(corCheio or colors.green)
            self.term.write(string.rep("=", preenchido))
            self.term.setTextColor(corVazio or colors.gray)
            self.term.write(string.rep("-", vazio))
            self.term.setTextColor(colors.white)
        else
            self.term.write(string.rep("#", preenchido) .. string.rep("-", vazio))
        end
    end

    function ui:escrever(x, y, texto, corTexto, corFundo)
        local w, h = self.term.getSize()
        if y > h or y < 1 then return end
        self.term.setCursorPos(x, y)
        if self.term.isColor and self.term.isColor() then
            if corFundo then self.term.setBackgroundColor(corFundo) end
            if corTexto then self.term.setTextColor(corTexto) end
        end
        self.term.write(texto)
        if self.term.isColor and self.term.isColor() then
            self.term.setBackgroundColor(colors.black)
            self.term.setTextColor(colors.white)
        end
    end

    function ui:renderizar(dados)
        local t = self.term
        local w, h = t.getSize()
        local isColor = t.isColor and t.isColor()

        t.setBackgroundColor(colors.black)
        t.clear()

        -- 1. Cabecalho Superior
        t.setCursorPos(1, 1)
        t.setBackgroundColor(colors.gray)
        t.clearLine()
        
        if isColor then t.setTextColor(colors.yellow) end
        t.write(" EXTREME REACTORS ")
        if isColor then t.setTextColor(colors.white) end
        
        -- Perfil de Operação
        local perfilTxt = (dados.perfil == "POTENCIA") and "[POTENCIA]" or "[EFICIENCIA]"
        if isColor then
            t.setTextColor((dados.perfil == "POTENCIA") and colors.magenta or colors.lime)
        end
        t.write(perfilTxt .. " ")

        if isColor then t.setTextColor(colors.lightGray) end
        t.write(dados.modo == "ATIVO_TURBINA" and "TURBINA" or "PASSIVO")

        local statusTxt = " [" .. tostring(dados.estado) .. "] "
        t.setCursorPos(math.max(1, w - #statusTxt + 1), 1)
        if isColor then
            if string.find(dados.estado, "SCRAM") then
                t.setTextColor(colors.red)
            elseif dados.estado == "OPERANDO" then
                t.setTextColor(colors.lime)
            else
                t.setTextColor(colors.orange)
            end
        end
        t.write(statusTxt)
        t.setBackgroundColor(colors.black)
        t.setTextColor(colors.white)

        -- 2. Secao Reator
        local r = dados.reator
        if not r then
            self:escrever(2, 3, "ERRO: Nenhum reator conectado!", colors.red)
            return
        end

        local lin = 3
        -- Barra de Buffer de Energia
        local pctEnergia = r.energia_pct or 0
        local txtEnergia = string.format("Buffer Energia: %5.1f%% (%s / %s RF)",
            pctEnergia, formatarNumero(r.energia_armazenada), formatarNumero(r.energia_capacidade))
        self:escrever(2, lin, txtEnergia, colors.cyan)
        lin = lin + 1
        self:barraProgresso(2, lin, math.min(30, w - 4), pctEnergia, colors.lightBlue, colors.gray)
        self:escrever(34, lin, string.format("+%s RF/t", formatarNumero(r.energia_tick)), colors.yellow)
        lin = lin + 2

        -- Temperatura do Combustivel e Carcaca
        local tempComb = r.temp_combustivel or 0
        local corTemp = colors.green
        if tempComb > 950 then
            corTemp = colors.red
        elseif tempComb > 750 then
            corTemp = colors.orange
        end

        local txtTemp = string.format("Temp Combustivel: %.1f C | Carcaca: %.1f C", tempComb, r.temp_carcaca or 0)
        self:escrever(2, lin, txtTemp, corTemp)
        lin = lin + 1
        local pctTemp = math.min(100, (tempComb / 1500) * 100)
        self:barraProgresso(2, lin, math.min(30, w - 4), pctTemp, corTemp, colors.gray)
        self:escrever(34, lin, string.format("Barras: %d%%", r.barras_nivel or 0), colors.white)
        lin = lin + 2

        -- Combustivel & Eficiencia
        local txtComb = string.format("Combustivel: %.1f%% (%s mB) | Queima: %.4f mB/t",
            r.combustivel_pct or 0, formatarNumero(r.combustivel_armazenado), r.consumo_tick or 0)
        self:escrever(2, lin, txtComb, colors.yellow)
        lin = lin + 1

        -- Indicador de Eficiencia em Destaque
        local txtEff = string.format("EFICIENCIA: %s RF / mB  (Alvo Barras: %d%%)",
            formatarNumero(dados.eficiencia_rf_mb or 0), dados.barras_alvo or 0)
        self:escrever(2, lin, txtEff, colors.lime)
        lin = lin + 2

        -- 3. Secao de Turbinas (se houver)
        local turbinas = dados.turbinas or {}
        if #turbinas > 0 and lin < (h - 3) then
            self:escrever(2, lin, string.format("--- TURBINAS (%d Conectadas) ---", #turbinas), colors.purple)
            lin = lin + 1
            for i, t in ipairs(turbinas) do
                if lin >= (h - 2) then break end
                local deltaRPM = math.abs((t.rpm or 0) - 1800)
                local corRpm = (deltaRPM <= 15) and colors.lime or (deltaRPM <= 50 and colors.yellow or colors.orange)
                local indutorTxt = t.indutor and "[INDUTOR: LIGADO]" or "[INDUTOR: DESLIGADO]"

                local linhaTurb = string.format("T#%d: %6.1f RPM %s | %s RF/t | %d mB/t",
                    i, t.rpm or 0, indutorTxt, formatarNumero(t.energia_tick), t.vazao_max or 0)
                self:escrever(2, lin, linhaTurb, corRpm)
                lin = lin + 1
            end
        elseif r.ativo_refrigerado and lin < (h - 3) then
            -- Reator refrigerado sem turbina direta
            local txtRefrig = string.format("Refrigerante: %s mB | Vapor: %s mB (+%s mB/t)",
                formatarNumero(r.agua), formatarNumero(r.vapor), formatarNumero(r.vapor_tick))
            self:escrever(2, lin, txtRefrig, colors.cyan)
            lin = lin + 1
        end

        -- 4. Notificacao / Alerta Flutuante
        if self.notificacao then
            local decorrido = (os.clock and os.clock() or 0) - self.tempoNotificacao
            if decorrido < 6 then
                self:escrever(2, h - 2, ">> " .. self.notificacao, colors.yellow)
            else
                self.notificacao = nil
            end
        elseif dados.alerta then
            local corAlerta = string.find(dados.alerta, "SCRAM") and colors.red or colors.lightGray
            self:escrever(2, h - 2, dados.alerta, corAlerta)
        end

        -- 5. Rodape de Teclas de Atalho
        t.setCursorPos(1, h)
        t.setBackgroundColor(colors.gray)
        t.clearLine()
        if isColor then t.setTextColor(colors.white) end
        t.write(" [P] Perfil  [R] Relatorio  [C] Benchmark  [E] SCRAM  [Q] Sair")
        t.setBackgroundColor(colors.black)
    end

    return ui
end

return M
]====]

arquivos["startup.lua"] = [====[
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
    print("  startup --potencia   Inicia forçando o perfil de Máxima Potência")
    print("  startup --eficiencia Inicia forçando o perfil de Máxima Eficiência (Eco)")
    print("  startup --relatorio  Gera um relatorio instantaneo e sai")
    print("  startup --benchmark  Executa o teste da curva de rendimento e sai")
    return
end

-- Carrega arquivo de configuracao salvo no disco, se existir
config.carregar()

-- Permite sobrescrever perfil pela linha de comando
if args[1] == "--potencia" then
    config.ativo.perfil_operacao = "potencia"
elseif args[1] == "--eficiencia" then
    config.ativo.perfil_operacao = "eficiencia"
end

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

        -- Tecla [P]: Alternar Perfil (Eficiência vs Potência)
        if tecla == keys.p then
            local novoPerfil = ctrl:alternarPerfil()
            local msgPerfil = "Perfil alterado para: " .. novoPerfil
            uiTerm:notificar(msgPerfil)
            if uiMon then uiMon:notificar(msgPerfil) end
            local dados = ctrl:coletarSnapshot()
            uiTerm:renderizar(dados)
            if uiMon then uiMon:renderizar(dados) end

        -- Tecla [R]: Gerar Relatorio Instantaneo
        elseif tecla == keys.r then
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
]====]


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
