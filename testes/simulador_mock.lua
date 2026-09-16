-- testes/simulador_mock.lua
-- Ambiente simulado (Mock) do ComputerCraft e dos perifericos Extreme Reactors

local Mock = {}

-- Cores do CC
colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768
}

-- Teclas
keys = { r = 19, c = 46, e = 18, q = 16, p = 25 }

-- Terminal Mock
term = {
    _w = 51,
    _h = 19,
    _cx = 1,
    _cy = 1,
    _linhas = {},
    getSize = function() return term._w, term._h end,
    setCursorPos = function(x, y) term._cx = x; term._cy = y end,
    setTextColor = function(c) end,
    setBackgroundColor = function(c) end,
    clear = function() term._linhas = {} end,
    clearLine = function() end,
    write = function(txt)
        local y = term._cy
        term._linhas[y] = (term._linhas[y] or "") .. tostring(txt)
    end,
    isColor = function() return true end,
}

-- TextUtils Mock
textutils = {
    serialize = function(t)
        local function ser(val)
            if type(val) == "table" then
                local partes = {}
                for k, v in pairs(val) do
                    table.insert(partes, "[" .. string.format("%q", tostring(k)) .. "]=" .. ser(v))
                end
                return "{" .. table.concat(partes, ",") .. "}"
            elseif type(val) == "string" then
                return string.format("%q", val)
            else
                return tostring(val)
            end
        end
        return ser(t)
    end,
    unserialize = function(s)
        local fn = load("return " .. s)
        if fn then
            local ok, res = pcall(fn)
            if ok then return res end
        end
        return nil
    end,
    formatTime = function(t) return string.format("%02d:00", math.floor(t or 0)) end,
}

-- Sistema de Arquivos (fs) em memória
local _arquivos = {}
fs = {
    exists = function(caminho) return _arquivos[caminho] ~= nil end,
    makeDir = function(dir) end,
    getName = function(caminho) return caminho:match("[^/\\]+$") or caminho end,
    open = function(caminho, modo)
        local handle = {}
        if modo == "w" then
            _arquivos[caminho] = ""
            handle.write = function(txt) _arquivos[caminho] = _arquivos[caminho] .. tostring(txt) end
            handle.close = function() end
            return handle
        elseif modo == "a" then
            _arquivos[caminho] = _arquivos[caminho] or ""
            handle.write = function(txt) _arquivos[caminho] = _arquivos[caminho] .. tostring(txt) end
            handle.close = function() end
            return handle
        elseif modo == "r" then
            if not _arquivos[caminho] then return nil end
            handle.readAll = function() return _arquivos[caminho] end
            handle.close = function() end
            return handle
        end
        return nil
    end,
    _dump = function(caminho) return _arquivos[caminho] end
}

-- OS Mock
os.clock = os.clock or function() return 0 end
os.sleep = function(s) end
os.day = function() return 1 end

-- Perifericos Mocks
function Mock.criarReatorMock(isRefrigerado)
    local r = {
        _ativo = true,
        _tempComb = 350.0,
        _tempCarcaca = 280.0,
        _energia = 2000000,
        _energiaMax = 10000000,
        _combustivel = 9500,
        _combustivelMax = 10000,
        _lixo = 50,
        _barras = 30,
        _reatividade = 85.0,
        _refrigerado = isRefrigerado or false,
        _agua = 8000,
        _aguaMax = 10000,
        _vapor = 2000,
        _vaporMax = 10000,
        _vaporTick = 0,
        _energiaTick = 0,
        _consumoTick = 0.05,
    }

    r.getActive = function() return r._ativo end
    r.setActive = function(v) r._ativo = v end
    r.getFuelTemperature = function() return r._tempComb end
    r.getCasingTemperature = function() return r._tempCarcaca end
    r.getEnergyStored = function() return r._energia end
    r.getEnergyCapacity = function() return r._energiaMax end
    r.getFuelAmount = function() return r._combustivel end
    r.getFuelAmountMax = function() return r._combustivelMax end
    r.getWasteAmount = function() return r._lixo end
    r.getFuelReactivity = function() return r._reatividade end
    r.getEnergyProducedLastTick = function() return r._energiaTick end
    r.getHotFluidProducedLastTick = function() return r._vaporTick end
    r.getFuelConsumedLastTick = function() return r._consumoTick end
    r.isActivelyCooled = function() return r._refrigerado end
    r.getCoolantAmount = function() return r._agua end
    r.getCoolantAmountMax = function() return r._aguaMax end
    r.getHotFluidAmount = function() return r._vapor end
    r.getHotFluidAmountMax = function() return r._vaporMax end
    r.getNumberOfControlRods = function() return 4 end
    r.getControlRodLevel = function() return r._barras end
    r.setAllControlRodLevels = function(v) r._barras = v end
    r.setControlRodLevel = function(i, v) r._barras = v end
    r.doEjectWaste = function() r._lixo = 0 end

    -- Simula 1 tick da fisica do reator
    function r:_simularTick()
        if not self._ativo then
            self._tempComb = math.max(20, self._tempComb - 10)
            self._energiaTick = 0
            self._vaporTick = 0
            self._consumoTick = 0
            return
        end

        local potencia = (100 - self._barras) / 100
        self._tempComb = 300 + (potencia * 500)
        self._tempCarcaca = self._tempComb * 0.75
        self._consumoTick = 0.01 + (potencia * 0.08)

        if self._refrigerado then
            self._vaporTick = math.floor(potencia * 2000)
            self._vapor = math.min(self._vaporMax, self._vapor + self._vaporTick)
            self._energiaTick = 0
        else
            self._energiaTick = math.floor(potencia * 15000)
            self._energia = math.min(self._energiaMax, self._energia + self._energiaTick)
        end
    end

    return r
end

function Mock.criarTurbinaMock()
    local t = {
        _ativo = true,
        _rpm = 1500.0,
        _indutor = false,
        _vazao = 1800,
        _vazaoMax = 2000,
        _vazaoTeto = 2000,
        _energia = 500000,
        _energiaMax = 1000000,
        _energiaTick = 0,
        _eficienciaPas = 99.5,
        _modoRespiro = "overflow",
    }

    t.getActive = function() return t._ativo end
    t.setActive = function(v) t._ativo = v end
    t.getRotorSpeed = function() return t._rpm end
    t.getInductorEngaged = function() return t._indutor end
    t.setInductorEngaged = function(v) t._indutor = v end
    t.getFluidFlowRate = function() return t._vazao end
    t.getFluidFlowRateMax = function() return t._vazaoMax end
    t.getFluidFlowRateMaxMax = function() return t._vazaoTeto end
    t.setFluidFlowRateMax = function(v) t._vazaoMax = v end
    t.getEnergyProducedLastTick = function() return t._energiaTick end
    t.getEnergyStored = function() return t._energia end
    t.getEnergyCapacity = function() return t._energiaMax end
    t.getBladeEfficiency = function() return t._eficienciaPas end
    t.setVentOverflow = function() t._modoRespiro = "overflow" end
    t.setVentNone = function() t._modoRespiro = "none" end
    t.setVentAll = function() t._modoRespiro = "all" end

    function t:_simularTick()
        if not self._ativo then
            self._rpm = math.max(0, self._rpm - 20)
            self._energiaTick = 0
            return
        end

        local forcaVapor = self._vazaoMax / 2000
        local arrasto = self._indutor and 0.98 or 0.998

        -- Equilíbrio de RPM: com 2000 mB/t e indutor ligado atinge ~1800 RPM
        if self._indutor then
            self._rpm = (self._rpm * arrasto) + (forcaVapor * 36)
            self._energiaTick = math.floor((self._rpm / 1800) * 24000)
            self._energia = math.min(self._energiaMax, self._energia + self._energiaTick)
        else
            self._rpm = (self._rpm * arrasto) + (forcaVapor * 60)
            self._energiaTick = 0
        end
    end

    return t
end

-- Peripheral Mock Registry
peripheral = {
    _dispositivos = {},
    registrar = function(nome, tipo, obj)
        peripheral._dispositivos[nome] = { tipo = tipo, obj = obj }
    end,
    getNames = function()
        local nomes = {}
        for n, _ in pairs(peripheral._dispositivos) do table.insert(nomes, n) end
        return nomes
    end,
    getType = function(nome)
        local d = peripheral._dispositivos[nome]
        return d and d.tipo or nil
    end,
    wrap = function(nome)
        local d = peripheral._dispositivos[nome]
        return d and d.obj or nil
    end,
    find = function(tipoAlvo)
        for n, d in pairs(peripheral._dispositivos) do
            if d.tipo == tipoAlvo then return d.obj, n end
        end
        return nil
    end
}

return Mock
