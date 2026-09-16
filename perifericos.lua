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
